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

    @Test func detectEnterTUIViaRealData() async {
        let session = Session(connection: MockTUIConnection())
        let enterSeq = Data("\u{1B}[?1049h".utf8)
        session.simulateHandleOutput(data: enterSeq)
        #expect(session.isTUIMode)
    }

    @Test func detectEnterTUISplitAcrossPackets() async {
        let session = Session(connection: MockTUIConnection())
        session.simulateHandleOutput(data: Data("\u{1B}[?".utf8))
        #expect(!session.isTUIMode)  // Not yet — sequence is incomplete
        session.simulateHandleOutput(data: Data("1049h".utf8))
        #expect(session.isTUIMode)   // Now detected after accumulation
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
