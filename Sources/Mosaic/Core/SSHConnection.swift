import Foundation
import Citadel
import NIOCore
import Crypto

// MARK: - SSHConnection
//
// TerminalConnection implementation backed by Citadel (swift-nio-ssh).
// Credentials are loaded from Keychain — never stored in this object.
//
// Design: `connect()` starts an async task that runs `client.withTTY()`
// for the lifetime of the session.  A CheckedContinuation bridges the
// closure-based TTY API back to connect()'s async return, resuming once
// the TTY channel is established and handing back a `TTYStdinWriter`.

@MainActor
public final class SSHConnection: TerminalConnection {
    public let id            = UUID()
    public let connectionInfo: ConnectionInfo

    @MainActor private(set) public var state: ConnectionState = .disconnected {
        didSet { yieldState(state) }
    }

    private let continuationLock = NSLock()
    private var _stateContinuation:  AsyncStream<ConnectionState>.Continuation?
    private var _outputContinuation: AsyncStream<Data>.Continuation?

    private var sshClient:   SSHClient?
    private var ttyWriter:   TTYStdinWriter?
    private var sessionTask: Task<Void, Never>?

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

        let authMethod: SSHAuthenticationMethod = try buildAuthMethod(
            username:   info.username,
            password:   password,
            privateKey: privateKey
        )

        // Bridge the closure-based withTTY to our async connect() return.
        // The continuation resumes with the TTYStdinWriter once the shell is open.
        let writer: TTYStdinWriter = try await withCheckedThrowingContinuation { cont in
            self.sessionTask = Task { @MainActor [weak self] in
                guard let self else {
                    cont.resume(throwing: ConnectionError.unknown("Connection deallocated"))
                    return
                }

                // Ensures the continuation is resumed exactly once.
                var didResume = false

                do {
                    let client = try await SSHClient.connect(
                        host: info.hostname,
                        port: info.port,
                        authenticationMethod: authMethod,
                        hostKeyValidator: .acceptAnything(),  // TODO: persist & verify in Phase 2
                        reconnect: .never
                    )
                    self.sshClient = client

                    try await client.withTTY { [weak self] inbound, outbound in
                        guard let self else { return }

                        if !didResume {
                            didResume = true
                            cont.resume(returning: outbound)
                        }
                        self.ttyWriter = outbound

                        for try await chunk in inbound {
                            if case .stdout(let buffer) = chunk {
                                self.yieldOutput(Data(buffer.readableBytesView))
                            }
                        }

                        self.state = .disconnected
                        self.finishStreams()
                    }
                } catch {
                    if !didResume {
                        didResume = true
                        cont.resume(throwing: Self.humanReadable(error, port: info.port))
                    }
                    self.state = .disconnected
                    self.finishStreams()
                }
            }
        }

        ttyWriter = writer
        state     = .connected
    }

    @MainActor
    public func disconnect() async {
        let client = sshClient
        sshClient  = nil
        ttyWriter  = nil
        state      = .disconnected
        finishStreams()

        sessionTask?.cancel()
        sessionTask = nil

        try? await client?.close()
    }

    @MainActor
    public func send(_ input: String) async throws {
        guard state == .connected, let writer = ttyWriter else {
            throw ConnectionError.unknown("Not connected")
        }
        var buffer = ByteBuffer()
        buffer.writeString(input)
        try await writer.write(buffer)
    }

    @MainActor
    public func sendData(_ data: Data) async throws {
        guard state == .connected, let writer = ttyWriter else {
            throw ConnectionError.unknown("Not connected")
        }
        var buffer = ByteBuffer()
        buffer.writeBytes(data)
        try await writer.write(buffer)
    }

    @MainActor
    public func resize(cols: Int, rows: Int) async throws {
        try? await ttyWriter?.changeSize(cols: cols, rows: rows, pixelWidth: 0, pixelHeight: 0)
    }

    // MARK: - Error translation

    private static func humanReadable(_ error: Error, port: Int) -> Error {
        let raw = error.localizedDescription
        // NIOConnectionError error 1 = EPERM (connection blocked/refused at OS level)
        // NIOConnectionError error 61 = ECONNREFUSED
        // NIOConnectionError error 60 = ETIMEDOUT
        if raw.contains("NIOConnectionError") || raw.contains("NIOPosix") {
            if raw.contains("error 61") {
                return ConnectionError.unknown("Connection refused on port \(port). Make sure SSH is running on the server.")
            } else if raw.contains("error 60") || raw.contains("error 110") {
                return ConnectionError.unknown("Connection timed out. Check that the hostname is correct and the server is reachable.")
            } else if raw.contains("error 1") || raw.contains("error 8") || raw.contains("error 13") {
                return ConnectionError.unknown("Could not reach the server on port \(port). Check that:\n• Your phone and server are on the same network (or use a public IP)\n• SSH is enabled on the server\n• Port \(port) is not blocked by a firewall")
            }
        }
        if raw.contains("NIOSSHError") || raw.contains("protocolViolation") {
            return ConnectionError.unknown("SSH handshake failed. The server may not be running SSH on port \(port).")
        }
        return error
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
            if let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: Data(base64Encoded: pem.components(separatedBy: "\n").filter { !$0.hasPrefix("-") }.joined() ) ?? Data()) {
                return .ed25519(username: username, privateKey: key)
            }
        }
        if let pw = password, !pw.isEmpty {
            return .passwordBased(username: username, password: pw)
        }
        throw ConnectionError.authenticationFailed
    }
}

extension SSHConnection: @unchecked Sendable {}
