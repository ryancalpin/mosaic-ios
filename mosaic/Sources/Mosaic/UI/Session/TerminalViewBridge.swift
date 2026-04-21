import SwiftUI
import SwiftTerm

// MARK: - TerminalViewBridge
//
// UIViewRepresentable wrapper around SwiftTerm's TerminalView.
//
// Architecture:
//   Session.connection.outputStream → feed(data:) → TerminalView.feed(byteArray:)
//                                                  → VT100 processing (SwiftTerm)
//                                                  → Session.handleOutput reads clean text
//
// The TerminalView is always present. SessionView hides it (opacity 0) when a
// native renderer is showing — it still processes escape codes in the background.

struct TerminalViewBridge: UIViewRepresentable {
    @ObservedObject var session: Session

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> TerminalView {
        let tv = TerminalView(frame: .zero)
        tv.terminalDelegate = context.coordinator
        tv.backgroundColor = UIColor(Color.mosaicBg)
        tv.nativeBackgroundColor = UIColor(Color.mosaicBg)

        // Register coordinator with session so SSH bytes flow through SwiftTerm
        context.coordinator.terminalView = tv
        session.terminalCoordinator = context.coordinator

        return tv
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {
        // Keep coordinator registered if session changes
        context.coordinator.terminalView = uiView
        session.terminalCoordinator = context.coordinator
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, TerminalViewDelegate, TerminalFeeder {
        weak var terminalView: TerminalView?

        // MARK: - TerminalFeeder

        func feed(data: Data) {
            terminalView?.feed(byteArray: [UInt8](data))
        }

        // MARK: - TerminalViewDelegate

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}

        func setTerminalTitle(source: TerminalView, title: String) {}

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            // SwiftTerm wants to send a response back (e.g. answering an ANSI query).
            // We route it via the session's connection.
            // Session is not stored here to avoid a retain cycle — accessed via the view.
        }

        func scrolled(source: TerminalView, position: Double) {}

        func clipboardCopy(source: TerminalView, content: Data) {}

        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}
