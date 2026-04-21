import Foundation
import SwiftData

// MARK: - Connection

@Model
public final class Connection {
    public var id: UUID          = UUID()
    public var name: String      = ""
    public var hostname: String  = ""
    public var port: Int         = 22
    public var username: String  = ""
    public var transport: String = "SSH"   // TransportProtocol.rawValue
    public var createdAt: Date   = Date()
    public var lastConnectedAt: Date?
    public var colorHex: String  = "#00D4AA"  // tab indicator color (user-picked)
    public var sortOrder: Int    = 0

    // NOTE: Credentials (password / private key) are stored in Keychain.
    // Use id.uuidString as the Keychain account key.
    // NEVER store credentials in SwiftData.

    public init(
        name: String,
        hostname: String,
        port: Int = 22,
        username: String,
        transport: TransportProtocol = .ssh,
        colorHex: String = "#00D4AA"
    ) {
        self.id              = UUID()
        self.name            = name
        self.hostname        = hostname
        self.port            = port
        self.username        = username
        self.transport       = transport.rawValue
        self.createdAt       = Date()
        self.lastConnectedAt = nil
        self.colorHex        = colorHex
        self.sortOrder       = 0
    }

    public var transportProtocol: TransportProtocol {
        TransportProtocol(rawValue: transport) ?? .ssh
    }

    public var connectionInfo: ConnectionInfo {
        ConnectionInfo(
            hostname:     hostname,
            port:         port,
            username:     username,
            transport:    transportProtocol,
            credentialID: id
        )
    }
}
