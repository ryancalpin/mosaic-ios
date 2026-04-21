import Foundation
import NMSSH

// MARK: - SSHConnection
//
// TerminalConnection implementation backed by NMSSH (libssh2).
// Credentials are loaded from Keychain — never stored in this object.
//
// Thread safety: NMSSH delegate callbacks fire on libssh2's internal thread.
// All continuation access is protected by continuationLock.

public final class SSHConnection: NSObject, TerminalConnection {
    public let id            = UUID()
    public let connectionInfo: ConnectionInfo

    // MARK: - State

    private(set) public var state: ConnectionState = .disconnected {
        didSet { yieldState(state) }
    }

    private let continuationLock = NSLock()
    private var _stateContinuation:  AsyncStream<ConnectionState>.Continuation?
    private var _outputContinuation: AsyncStream<Data>.Continuation?

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

    public lazy var stateStream: AsyncStream<ConnectionState> = {
        AsyncStream { [weak self] continuation in
            self?.continuationLock.lock()
            self?._stateContinuation = continuation
            self?.continuationLock.unlock()
        }
    }()

    public lazy var outputStream: AsyncStream<Data> = {
        AsyncStream { [weak self] continuation in
            self?.continuationLock.lock()
            self?._outputContinuation = continuation
            self?.continuationLock.unlock()
        }
    }()

    // MARK: - NMSSH internals

    private var nmSession: NMSSHSession?
    private var nmChannel: NMSSHChannel?

    // MARK: - Init

    public init(connectionInfo: ConnectionInfo) {
        self.connectionInfo = connectionInfo
        super.init()
        // Eagerly initialize streams so continuations are set before connect() fires bytes
        _ = stateStream
        _ = outputStream
    }

    // MARK: - TerminalConnection

    public func connect() async throws {
        state = .connecting

        let info = connectionInfo
        let session = NMSSHSession(
            toHost:       info.hostname,
            port:         Int32(info.port),
            withUsername: info.username
        )

        guard session.connect() else {
            state = .error("Could not connect to \(info.hostname):\(info.port)")
            throw ConnectionError.hostUnreachable
        }

        // Authenticate
        let connID = id.uuidString
        if let key = KeychainHelper.loadPrivateKey(connectionID: connID) {
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

        guard let channel = session.channel else {
            session.disconnect()
            throw ConnectionError.unknown("Could not create channel")
        }

        channel.delegate = self
        channel.requestPty = true
        channel.ptyTerminalType = NMSSHChannelPtyTerminalXterm

        var shellError: NSError?
        guard channel.startShell(&shellError) else {
            let msg = shellError?.localizedDescription ?? "Could not start shell"
            session.disconnect()
            throw ConnectionError.unknown(msg)
        }

        nmSession = session
        nmChannel = channel
        state = .connected
    }

    public func disconnect() async {
        nmChannel?.closeShell()
        nmSession?.disconnect()
        nmChannel = nil
        nmSession = nil
        state = .disconnected

        continuationLock.lock()
        let sc = _stateContinuation
        let oc = _outputContinuation
        _stateContinuation  = nil
        _outputContinuation = nil
        continuationLock.unlock()

        sc?.finish()
        oc?.finish()
    }

    public func send(_ input: String) async throws {
        guard state == .connected, let channel = nmChannel else {
            throw ConnectionError.unknown("Not connected")
        }
        var error: NSError?
        guard channel.write(input, error: &error) else {
            let msg = error?.localizedDescription ?? "Write failed"
            throw ConnectionError.unknown(msg)
        }
    }

    public func sendData(_ data: Data) async throws {
        guard let str = String(data: data, encoding: .utf8) else { return }
        try await send(str)
    }

    public func resize(cols: Int, rows: Int) async throws {
        nmChannel?.requestSizeWidth(UInt(cols), height: UInt(rows))
    }
}

// MARK: - NMSSHChannelDelegate
// These fire on NMSSH's libssh2 thread — use continuationLock for all access.

extension SSHConnection: NMSSHChannelDelegate {
    public func channel(_ channel: NMSSHChannel, didReadRawData data: Data) {
        yieldOutput(data)
    }

    public func channel(_ channel: NMSSHChannel, didReadData message: String) {
        guard let data = message.data(using: .utf8) else { return }
        yieldOutput(data)
    }

    public func channelShellDidClose(_ channel: NMSSHChannel) {
        continuationLock.lock()
        let sc = _stateContinuation
        let oc = _outputContinuation
        _stateContinuation  = nil
        _outputContinuation = nil
        continuationLock.unlock()

        oc?.finish()
        sc?.yield(.disconnected)
        sc?.finish()
    }
}
