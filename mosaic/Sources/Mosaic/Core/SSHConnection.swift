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

    // Always written on MainActor; read from MainActor (TabBarView).
    // Delegate callbacks dispatch to main before mutating.
    @MainActor private(set) public var state: ConnectionState = .disconnected {
        didSet { yieldState(state) }
    }

    private let continuationLock = NSLock()
    private var _stateContinuation:  AsyncStream<ConnectionState>.Continuation?
    private var _outputContinuation: AsyncStream<Data>.Continuation?

    // Serializes all libssh2 I/O (send/closeShell/disconnect) since libssh2 is not thread-safe.
    // Required when send() and disconnect() can race in concurrent detached tasks.
    private let libssh2Lock = NSLock()

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

    @MainActor
    public func connect() async throws {
        state = .connecting

        let info = connectionInfo
        // Load credentials on MainActor before entering the detached task to avoid
        // calling KeychainHelper from a non-isolated context.
        let credentialID = connectionInfo.credentialID.uuidString
        let privateKey = KeychainHelper.loadPrivateKey(connectionID: credentialID)
        let password   = KeychainHelper.loadPassword(connectionID: credentialID)

        // NMSSH network I/O is blocking — run off the MainActor so we don't block the UI.
        let (session, channel): (NMSSHSession, NMSSHChannel) = try await Task.detached(priority: .userInitiated) {
            let s = NMSSHSession(toHost: info.hostname, port: Int32(info.port), withUsername: info.username)
            guard s.connect() else { throw ConnectionError.hostUnreachable }

            if let key = privateKey {
                let pass = password ?? ""
                s.authenticateBy(inMemoryPublicKey: nil, privateKey: key, andPassword: pass.isEmpty ? nil : pass)
                // Fall back to password if key auth failed and a password is available
                if !s.isAuthorized, let pw = password {
                    s.authenticate(byPassword: pw)
                }
            } else if let pw = password {
                s.authenticate(byPassword: pw)
            } else {
                s.disconnect()
                throw ConnectionError.authenticationFailed
            }

            guard s.isAuthorized else { s.disconnect(); throw ConnectionError.authenticationFailed }
            guard let ch = s.channel else { s.disconnect(); throw ConnectionError.unknown("Could not create channel") }

            ch.requestPty = true
            ch.ptyTerminalType = NMSSHChannelPtyTerminalXterm
            // Delegate set before startShell so the initial MOTD/banner bytes are captured
            ch.delegate = self as NMSSHChannelDelegate
            var shellError: NSError?
            guard ch.startShell(&shellError) else {
                let msg = shellError?.localizedDescription ?? "Could not start shell"
                s.disconnect()
                throw ConnectionError.unknown(msg)
            }
            return (s, ch)
        }.value

        // Back on MainActor — safe to write @MainActor state.
        // Set nmSession/nmChannel before the guard so channelShellDidClose's queued Task sees
        // them as non-nil and doesn't treat the close as a no-op during the race window.
        nmSession = session
        nmChannel = channel
        // Guard: disconnect() may have been called while we were suspended at .value above.
        guard state == .connecting else {
            channel.closeShell()
            session.disconnect()
            return
        }
        // Delegate already set inside detached task; reassign here to satisfy MainActor assignment
        channel.delegate = self
        state = .connected
    }

    @MainActor
    public func disconnect() async {
        let ch   = nmChannel
        let sess = nmSession
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

        // closeShell/disconnect block on libssh2 — run off MainActor to avoid UI freeze.
        // libssh2Lock serializes against any concurrent send() call in a detached task.
        let lock = libssh2Lock
        await Task.detached(priority: .utility) {
            lock.lock()
            defer { lock.unlock() }
            ch?.closeShell()
            sess?.disconnect()
        }.value
    }

    @MainActor
    public func send(_ input: String) async throws {
        guard state == .connected, let channel = nmChannel else {
            throw ConnectionError.unknown("Not connected")
        }
        // channel.write blocks on libssh2 under back-pressure — run off MainActor.
        // libssh2Lock serializes against concurrent closeShell/disconnect calls.
        let ch = channel
        let lock = libssh2Lock
        try await Task.detached(priority: .userInitiated) {
            lock.lock()
            defer { lock.unlock() }
            var error: NSError?
            guard ch.write(input, error: &error) else {
                let msg = error?.localizedDescription ?? "Write failed"
                throw ConnectionError.unknown(msg)
            }
        }.value
    }

    @MainActor
    public func sendData(_ data: Data) async throws {
        guard let str = String(data: data, encoding: .utf8)
                     ?? String(data: data, encoding: .isoLatin1) else { return }
        try await send(str)
    }

    @MainActor
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
        // Update state first so didSet's yieldState fires while the continuation is still live,
        // then clear and finish the continuations.
        Task { @MainActor [weak self] in
            guard let self, self.nmChannel != nil else { return }
            self.nmChannel = nil   // prevent disconnect() from calling closeShell() on an already-closed channel
            self.nmSession = nil
            self.state = .disconnected   // didSet → yieldState → yields to live continuation

            self.continuationLock.lock()
            let sc = self._stateContinuation
            let oc = self._outputContinuation
            self._stateContinuation  = nil
            self._outputContinuation = nil
            self.continuationLock.unlock()

            oc?.finish()
            sc?.finish()
        }
    }
}

// continuationLock protects all shared mutable state; @MainActor guards nmSession/nmChannel
extension SSHConnection: @unchecked Sendable {}
