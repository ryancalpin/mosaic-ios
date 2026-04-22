import Foundation
import Testing
@testable import Mosaic

@Suite("TUI Mode")
@MainActor
struct TUIModeTests {

    @Test func tuiModeDefaultsFalse() async {
        let session = Session(connection: MockTUIConnection())
        #expect(!session.isTUIMode)
    }

    @Test func detectEnterAlternateScreen() async {
        let session = Session(connection: MockTUIConnection())
        session.simulateTUIDetection(entering: true)
        #expect(session.isTUIMode)
    }

    @Test func detectExitAlternateScreen() async {
        let session = Session(connection: MockTUIConnection())
        session.simulateTUIDetection(entering: true)
        session.simulateTUIDetection(entering: false)
        #expect(!session.isTUIMode)
    }
}

// Minimal mock so Session can be instantiated in tests
@MainActor
final class MockTUIConnection: TerminalConnection {
    let id = UUID()

    var connectionInfo: ConnectionInfo {
        ConnectionInfo(hostname: "test", port: 22, username: "user",
                       transport: .ssh, credentialID: UUID())
    }

    var state: ConnectionState = .disconnected

    var stateStream: AsyncStream<ConnectionState> {
        AsyncStream { _ in }
    }

    var outputStream: AsyncStream<Data> {
        AsyncStream { _ in }
    }

    func connect() async throws {}
    func disconnect() async {}
    func send(_ input: String) async throws {}
    func sendData(_ data: Data) async throws {}
    func resize(cols: Int, rows: Int) async throws {}
}
