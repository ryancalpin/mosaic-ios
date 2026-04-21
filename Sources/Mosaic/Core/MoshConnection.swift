import Foundation
import mosh
import Citadel
import NIOCore
import Crypto

// MARK: - MoshConnection
//
// TerminalConnection backed by mosh (UDP, roaming-capable).
//
// Flow:
//   1. SSH into the server via Citadel and exec `mosh-server new` to get (ip, port, key).
//   2. Close the SSH connection.
//   3. Wire two Pipes for bidirectional I/O with mosh_main().
//   4. Run mosh_main() on a dedicated background Thread (it blocks until the session ends).
//   5. Stream pipe output into the outputStream continuation.

@MainActor
public final class MoshConnection: TerminalConnection {
    public let id            = UUID()
    public let connectionInfo: ConnectionInfo

    @MainActor private(set) public var state: ConnectionState = .disconnected {
        didSet { yieldState(state) }
    }

    private let continuationLock = NSLock()
    private var _stateContinuation:  AsyncStream<ConnectionState>.Continuation?
    private var _outputContinuation: AsyncStream<Data>.Continuation?

    private var stdinWriteHandle: FileHandle?
    private var currentCols: Int32 = 80
    private var currentRows: Int32 = 24

    // MARK: - Streams

    public lazy var stateStream: AsyncStream<ConnectionState> = {
        AsyncStream { continuation in
            self.continuationLock.lock()
            self._stateContinuation = continuation
            self.continuationLock.unlock()
        }
    }()

    public lazy var outputStream: AsyncStream<Data> = {
        AsyncStream { continuation in
            self.continuationLock.lock()
            self._outputContinuation = continuation
            self.continuationLock.unlock()
        }
    }()

    // MARK: - Init

    public init(connectionInfo: ConnectionInfo) {
        self.connectionInfo = connectionInfo
        _ = stateStream
        _ = outputStream
    }

    // MARK: - Helpers

    private func yieldState(_ s: ConnectionState) {
        continuationLock.lock()
        let c = _stateContinuation
        continuationLock.unlock()
        c?.yield(s)
    }

    private func yieldOutput(_ data: Data) {
        continuationLock.lock()
        let c = _outputContinuation
        continuationLock.unlock()
        c?.yield(data)
    }

    private func finishStreams() {
        continuationLock.lock()
        let sc = _stateContinuation
        let oc = _outputContinuation
        _stateContinuation  = nil
        _outputContinuation = nil
        continuationLock.unlock()
        sc?.finish()
        oc?.finish()
    }

    // MARK: - TerminalConnection

    @MainActor
    public func connect() async throws {
        state = .connecting

        let info         = connectionInfo
        let credentialID = info.credentialID.uuidString
        let privateKey   = KeychainHelper.loadPrivateKey(connectionID: credentialID)
        let password     = KeychainHelper.loadPassword(connectionID: credentialID)

        let authMethod = try buildAuthMethod(
            username:   info.username,
            password:   password,
            privateKey: privateKey
        )

        // Step 1: SSH bootstrap — start mosh-server and get connection params
        let (ip, moshPort, moshKey) = try await bootstrapMoshServer(
            host:       info.hostname,
            sshPort:    info.port,
            authMethod: authMethod
        )

        // Step 2: Pipes for mosh_main I/O
        let inPipe  = Pipe()   // app writes → mosh reads (stdin)
        let outPipe = Pipe()   // mosh writes → app reads (stdout)

        stdinWriteHandle = inPipe.fileHandleForWriting

        let cols        = currentCols
        let rows        = currentRows
        let inReadFD    = inPipe.fileHandleForReading.fileDescriptor
        let outWriteFD  = outPipe.fileHandleForWriting.fileDescriptor
        let outReadHandle = outPipe.fileHandleForReading

        // Step 3: Stream mosh output into the continuation
        outReadHandle.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            guard !data.isEmpty else {
                fh.readabilityHandler = nil
                return
            }
            Task { @MainActor [weak self] in
                self?.yieldOutput(data)
            }
        }

        // Step 4: Run mosh_main on a dedicated thread — it blocks until session ends
        let thread = Thread { [weak self] in
            guard let fIn  = fdopen(inReadFD,  "r"),
                  let fOut = fdopen(outWriteFD, "w") else {
                Task { @MainActor [weak self] in
                    self?.state = .disconnected
                    self?.finishStreams()
                }
                return
            }

            var ws = winsize()
            ws.ws_col    = UInt16(cols)
            ws.ws_row    = UInt16(rows)
            ws.ws_xpixel = 0
            ws.ws_ypixel = 0

            ip.withCString { ipPtr in
                moshPort.withCString { portPtr in
                    moshKey.withCString { keyPtr in
                        "adaptive".withCString { predictPtr in
                            _ = mosh_main(fIn, fOut, &ws, nil, nil,
                                          ipPtr, portPtr, keyPtr, predictPtr,
                                          nil, 0, nil)
                        }
                    }
                }
            }

            fclose(fIn)
            fclose(fOut)
            outReadHandle.readabilityHandler = nil

            Task { @MainActor [weak self] in
                self?.state = .disconnected
                self?.finishStreams()
            }
        }
        thread.name = "mosh-session"
        thread.qualityOfService = .userInteractive
        thread.start()

        state = .connected
    }

    @MainActor
    public func disconnect() async {
        // Closing stdin causes mosh_main to see EOF and exit cleanly
        try? stdinWriteHandle?.close()
        stdinWriteHandle = nil
        state = .disconnected
        finishStreams()
    }

    @MainActor
    public func send(_ input: String) async throws {
        guard state == .connected, let handle = stdinWriteHandle else {
            throw ConnectionError.unknown("Not connected")
        }
        guard let data = input.data(using: .utf8) else { return }
        try handle.write(contentsOf: data)
    }

    @MainActor
    public func sendData(_ data: Data) async throws {
        guard state == .connected, let handle = stdinWriteHandle else {
            throw ConnectionError.unknown("Not connected")
        }
        try handle.write(contentsOf: data)
    }

    @MainActor
    public func resize(cols: Int, rows: Int) async throws {
        currentCols = Int32(cols)
        currentRows = Int32(rows)
        // mosh manages its own terminal state synchronization internally;
        // the new dimensions will be picked up on the next state-sync cycle.
    }

    // MARK: - SSH Bootstrap

    private func bootstrapMoshServer(
        host:       String,
        sshPort:    Int,
        authMethod: SSHAuthenticationMethod
    ) async throws -> (ip: String, port: String, key: String) {
        let client = try await SSHClient.connect(
            host:                 host,
            port:                 sshPort,
            authenticationMethod: authMethod,
            hostKeyValidator:     .acceptAnything(),
            reconnect:            .never
        )
        defer { Task { try? await client.close() } }

        let command = "mosh-server new -p 60001 -c 256 -s -l LANG=en_US.UTF-8 2>/dev/null"
        let buffer: ByteBuffer
        do {
            buffer = try await client.executeCommand(command)
        } catch {
            throw ConnectionError.moshServerNotFound
        }

        var copy   = buffer
        let output = copy.readString(length: copy.readableBytes) ?? ""

        // Parse: "MOSH CONNECT <port> <key>\n"
        let pattern = #"MOSH CONNECT (\d+) ([A-Za-z0-9+/=]+)"#
        guard let regex    = try? NSRegularExpression(pattern: pattern),
              let match    = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let portRange = Range(match.range(at: 1), in: output),
              let keyRange  = Range(match.range(at: 2), in: output) else {
            throw ConnectionError.moshServerNotFound
        }

        return (ip: host, port: String(output[portRange]), key: String(output[keyRange]))
    }

    // MARK: - Auth

    private func buildAuthMethod(
        username:   String,
        password:   String?,
        privateKey: String?
    ) throws -> SSHAuthenticationMethod {
        if let pem = privateKey, !pem.isEmpty {
            if let key = try? P256.Signing.PrivateKey(pemRepresentation: pem) {
                return .p256(username: username, privateKey: key)
            }
            if let key = try? P384.Signing.PrivateKey(pemRepresentation: pem) {
                return .p384(username: username, privateKey: key)
            }
            if let key = try? P521.Signing.PrivateKey(pemRepresentation: pem) {
                return .p521(username: username, privateKey: key)
            }
            if let key = try? Curve25519.Signing.PrivateKey(
                rawRepresentation: Data(base64Encoded:
                    pem.components(separatedBy: "\n")
                       .filter { !$0.hasPrefix("-") }
                       .joined()
                ) ?? Data()
            ) {
                return .ed25519(username: username, privateKey: key)
            }
        }
        if let pw = password, !pw.isEmpty {
            return .passwordBased(username: username, password: pw)
        }
        throw ConnectionError.authenticationFailed
    }
}

extension MoshConnection: @unchecked Sendable {}
