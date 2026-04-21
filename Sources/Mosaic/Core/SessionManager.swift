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
            hostname:     connection.hostname,
            port:         connection.port,
            username:     connection.username,
            transport:    connection.transportProtocol,
            credentialID: connection.id
        )

        let transport: any TerminalConnection
        switch connection.transportProtocol {
        case .ssh:
            transport = SSHConnection(connectionInfo: info)
        case .mosh:
            // Mosh not yet integrated — fall back to SSH
            transport = SSHConnection(connectionInfo: info)
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
        // Remove from UI immediately; disconnect runs async so the tab closes instantly
        sessions.removeAll { $0.id == session.id }
        if activeSessionID == session.id {
            activeSessionID = sessions.last?.id
        }
        Task { await session.stop() }
    }

    public func activate(_ session: Session) {
        activeSessionID = session.id
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
