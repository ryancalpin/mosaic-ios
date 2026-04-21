import Foundation

// MARK: - TerminalConnection Protocol
//
// Every transport (SSH, Mosh) conforms to this protocol.
// The rendering engine, session manager, and UI never know
// whether bytes are coming from SSH or Mosh. They talk only to this.

public protocol TerminalConnection: AnyObject {
    var id: UUID { get }
    var connectionInfo: ConnectionInfo { get }
    @MainActor var state: ConnectionState { get }
    var stateStream: AsyncStream<ConnectionState> { get }
    var outputStream: AsyncStream<Data> { get }

    @MainActor func connect() async throws
    @MainActor func disconnect() async
    @MainActor func send(_ input: String) async throws
    @MainActor func sendData(_ data: Data) async throws
    @MainActor func resize(cols: Int, rows: Int) async throws
}

// MARK: - ConnectionInfo

public struct ConnectionInfo: Equatable, Sendable {
    public let hostname: String
    public let port: Int
    public let username: String
    public let transport: TransportProtocol

    public init(hostname: String, port: Int = 22, username: String, transport: TransportProtocol) {
        self.hostname = hostname
        self.port = port
        self.username = username
        self.transport = transport
    }
}

// MARK: - TransportProtocol

public enum TransportProtocol: String, Sendable, Codable, CaseIterable {
    case ssh  = "SSH"
    case mosh = "MOSH"

    public var badgeColor: String {
        switch self {
        case .ssh:  return "#4A9EFF"  // blue
        case .mosh: return "#A78BFA"  // purple
        }
    }

    public var defaultPort: Int {
        switch self {
        case .ssh:  return 22
        case .mosh: return 60001  // mosh default UDP port range starts here
        }
    }
}

// MARK: - ConnectionState

public enum ConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case roaming           // Mosh: network changed, reconnecting
    case error(String)

    public var isLive: Bool {
        switch self {
        case .connected, .roaming: return true
        default: return false
        }
    }

    public var displayLabel: String {
        switch self {
        case .disconnected:    return "Disconnected"
        case .connecting:      return "Connecting…"
        case .connected:       return "Connected"
        case .roaming:         return "Roaming…"
        case .error(let msg):  return "Error: \(msg)"
        }
    }
}

// MARK: - ConnectionError

public enum ConnectionError: LocalizedError {
    case authenticationFailed
    case hostUnreachable
    case moshServerNotFound
    case timeout
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .authenticationFailed:  return "Authentication failed. Check credentials."
        case .hostUnreachable:       return "Host unreachable. Check hostname and network."
        case .moshServerNotFound:    return "mosh-server not found on remote. Install it or use SSH."
        case .timeout:               return "Connection timed out."
        case .unknown(let msg):      return msg
        }
    }

    /// Whether to offer SSH fallback in the UI
    public var offerSSHFallback: Bool {
        self == .moshServerNotFound
    }
}
