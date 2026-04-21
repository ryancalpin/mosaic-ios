import Foundation
import NMSSH

// MARK: - SSHConnection
//
// TerminalConnection implementation backed by NMSSH (libssh2).
// Credentials are loaded from Keychain — never stored in this object.

public final class SSHConnection: NSObject, TerminalConnection {
    public let id            = UUID()
    public let connectionInfo: ConnectionInfo

    // MARK: - State

    private(set) public var state: ConnectionState = .disconnected {
        didSet { stateContinuation?.yield(state) }
    }

    private var stateContinuation:  AsyncStream<ConnectionState>.Continuation?
    private var outputContinuation: AsyncStream<Data>.Continuation?

    public lazy var stateStream: AsyncStream<ConnectionState> = {
        AsyncStream { continuation in
            self.stateContinuation = continuation
        }
    }()

    public lazy var outputStream: AsyncStream<Data> = {
        AsyncStream { continuation in
            self.outputContinuation = continuation
        }
    }()

    // MARK: - NMSSH internals

    private var nmSession: NMSSHSession?
    private var nmChannel: NMSSHChannel?
    private var readTask: Task<Void, Never>?

    // MARK: - Init

    public init(connectionInfo: ConnectionInfo) {
        self.connectionInfo = connectionInfo
    }

    // MARK: - TerminalConnection

    public func connect() async throws {
        state = .connecting

        let info = connectionInfo
        let session = NMSSHSession(
            toHost: info.hostname,
            port:   Int32(info.port),
            withUsername: info.username
        )

        guard session.connect() else {
            state = .error("Could not connect to \(info.hostname):\(info.port)")
            throw ConnectionError.hostUnreachable
        }

        // Authenticate
        let connID = id.uuidString
        if let key = KeychainHelper.loadPrivateKey(connectionID: connID) {
            // Key-based auth
            let passphrase = KeychainHelper.loadPassword(connectionID: connID) ?? ""
            session.authenticateBy(
                inMemoryPublicKey: nil,
                privateKey: key,
                andPassword: passphrase.isEmpty ? nil : passphrase
            )
        } else if let password = KeychainHelper.loadPassword(connectionID: connID) {
            session.authenticate(byPassword: password)
        } else {
            session.disconnect()
            state = .error("No credentials found in Keychain")
            throw ConnectionError.authenticationFailed
        }

        guard session.isAuthorized else {
            session.disconnect()
            state = .disconnected
            throw ConnectionError.authenticationFailed
        }

        // Open interactive shell channel
        guard let channel = session.channel else {
            session.disconnect()
            throw ConnectionError.unknown("Could not create channel")
        }

        channel.delegate = self
        channel.requestPty = true
        channel.ptyTerminalType = NMSSHChannelPtyTerminal.xterm

        var shellError: NSError?
        guard channel.startShell(&shellError) else {
            let msg = shellError?.localizedDescription ?? "Could not start shell"
            session.disconnect()
            throw ConnectionError.unknown(msg)
        }

        nmSession = session
        nmChannel = channel
        state = .connected

        // Start reading output
        startReading()
    }

    public func disconnect() async {
        readTask?.cancel()
        nmChannel?.closeShell()
        nmSession?.disconnect()
        nmChannel  = nil
        nmSession  = nil
        state = .disconnected
        stateContinuation?.finish()
        outputContinuation?.finish()
    }

    public func send(_ input: String) async throws {
        guard state == .connected, let channel = nmChannel else {
            throw ConnectionError.unknown("Not connected")
        }
        var error: NSError?
        channel.write(input, error: &error, timeout: 5)
        if let error {
            throw ConnectionError.unknown(error.localizedDescription)
        }
    }

    public func sendData(_ data: Data) async throws {
        guard let str = String(data: data, encoding: .utf8) else { return }
        try await send(str)
    }

    public func resize(cols: Int, rows: Int) async throws {
        nmChannel?.requestSizeWidth(UInt32(cols), height: UInt32(rows))
    }

    // MARK: - Read Loop

    private func startReading() {
        readTask = Task {
            while !Task.isCancelled {
                // NMSSH delivers output via delegate (NMSSHChannelDelegate)
                // so we just yield here to keep the task alive
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }
}

// MARK: - NMSSHChannelDelegate

extension SSHConnection: NMSSHChannelDelegate {
    public func channel(_ channel: NMSSHChannel, didReadData message: String) {
        guard let data = message.data(using: .utf8) else { return }
        outputContinuation?.yield(data)
    }

    public func channel(_ channel: NMSSHChannel, didReadError error: String) {
        guard let data = error.data(using: .utf8) else { return }
        outputContinuation?.yield(data)
    }

    public func channelShellDidClose(_ channel: NMSSHChannel) {
        state = .disconnected
        outputContinuation?.finish()
        stateContinuation?.finish()
    }
}
