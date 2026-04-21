import Foundation
import SwiftUI

// MARK: - SessionManager
//
// Manages all open terminal sessions (tabs).
// One SessionManager lives for the lifetime of the app.

@MainActor
public final class SessionManager: ObservableObject {
    public static let shared = SessionManager()

    @Published public var sessions: [Session] = []
    @Published public var activeSessionID: UUID? = nil

    private init() {}

    // MARK: - Active Session

    public var activeSession: Session? {
        guard let id = activeSessionID else { return sessions.first }
        return sessions.first { $0.id == id }
    }

    // MARK: - Open / Close

    public func openSession(for connection: Connection) async throws {
        let info = ConnectionInfo(
            hostname:  connection.hostname,
            port:      connection.port,
            username:  connection.username,
            transport: connection.transportProtocol
        )

        let transport: any TerminalConnection
        switch connection.transportProtocol {
        case .ssh:
            let ssh = SSHConnection(connectionInfo: info)
            // Copy the connection's UUID as the Keychain key so credentials resolve
            transfer(keychainFrom: connection, to: ssh)
            transport = ssh
        case .mosh:
            // Mosh not yet integrated — fall back to SSH
            let ssh = SSHConnection(connectionInfo: info)
            transfer(keychainFrom: connection, to: ssh)
            transport = ssh
        }

        let session = Session(connection: transport)
        sessions.append(session)
        activeSessionID = session.id

        // connect() must complete before start() so the AsyncStream continuations
        // are initialized before NMSSH begins firing delegate callbacks.
        do {
            try await transport.connect()
        } catch {
            sessions.removeAll { $0.id == session.id }
            if activeSessionID == session.id {
                activeSessionID = sessions.last?.id
            }
            throw error
        }

        session.start()
    }

    public func closeSession(_ session: Session) {
        session.stop()
        if let ssh = session.connection as? SSHConnection {
            KeychainHelper.deleteCredentials(connectionID: ssh.id.uuidString)
        }
        sessions.removeAll { $0.id == session.id }
        if activeSessionID == session.id {
            activeSessionID = sessions.last?.id
        }
    }

    public func activate(_ session: Session) {
        activeSessionID = session.id
    }

    // MARK: - Helpers

    private func transfer(keychainFrom connection: Connection, to ssh: SSHConnection) {
        let srcID = connection.id.uuidString
        let dstID = ssh.id.uuidString
        if let pw = KeychainHelper.loadPassword(connectionID: srcID) {
            KeychainHelper.savePassword(pw, connectionID: dstID)
        }
        if let key = KeychainHelper.loadPrivateKey(connectionID: srcID) {
            KeychainHelper.savePrivateKey(key, connectionID: dstID)
        }
    }
}

// Rethrow so callers can handle connection errors
extension SessionManager {
    @discardableResult
    public func openSessionThrowing(for connection: Connection) async -> (any Error)? {
        do {
            try await openSession(for: connection)
            return nil
        } catch {
            return error
        }
    }
}
