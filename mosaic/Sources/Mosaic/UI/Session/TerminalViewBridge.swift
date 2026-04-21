import SwiftUI
import SwiftTerm

// MARK: - TerminalViewBridge
//
// UIViewRepresentable wrapper around SwiftTerm's TerminalView.
//
// Architecture:
//   SSH bytes → feed(data:) → TerminalView.feed(byteArray:) → VT100 processing
//   ANSI responses (e.g. DA1, cursor reports) → send(source:data:) → connection.sendData
//
// The TerminalView is sized to match its parent via GeometryReader so the server
// receives correct cols/rows. It is hidden via opacity/allowsHitTesting, not zero-sized.

@MainActor
struct TerminalViewBridge: UIViewRepresentable {
    @ObservedObject var session: Session
    let size: CGSize     // real pixel dimensions from GeometryReader in SessionView

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> TerminalView {
        let tv = TerminalView(frame: CGRect(origin: .zero, size: size))
        tv.terminalDelegate = context.coordinator
        tv.backgroundColor       = UIColor(Color.mosaicBg)
        tv.nativeBackgroundColor = UIColor(Color.mosaicBg)

        context.coordinator.terminalView = tv
        context.coordinator.session      = session
        session.terminalCoordinator      = context.coordinator

        // Tell server about real terminal dimensions immediately
        Task {
            let cols = max(1, Int(size.width  / 8))   // ~8pt per char monospace
            let rows = max(1, Int(size.height / 16))  // ~16pt per line
            try? await session.connection.resize(cols: cols, rows: rows)
        }
        return tv
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {
        context.coordinator.terminalView = uiView
        context.coordinator.session      = session
        session.terminalCoordinator      = context.coordinator

        // Re-report dimensions if the frame changed (rotation, split view)
        let newFrame = CGRect(origin: .zero, size: size)
        if uiView.frame != newFrame {
            uiView.frame = newFrame
            Task {
                let cols = max(1, Int(size.width  / 8))
                let rows = max(1, Int(size.height / 16))
                try? await session.connection.resize(cols: cols, rows: rows)
            }
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, TerminalViewDelegate, TerminalFeeder {
        weak var terminalView: TerminalView?
        weak var session: Session?

        // MARK: - TerminalFeeder

        func feed(data: Data) {
            terminalView?.feed(byteArray: [UInt8](data))
        }

        // MARK: - TerminalViewDelegate

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            Task { @MainActor [weak self] in
                guard let session = self?.session else { return }
                try? await session.connection.resize(cols: newCols, rows: newRows)
            }
        }

        func setTerminalTitle(source: TerminalView, title: String) {}

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        // Route ANSI responses (DA1, cursor reports, device status) back to the server.
        // Without this, interactive programs (vim, htop, less) hang waiting for responses.
        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            let d = Data(data)
            Task { @MainActor [weak self] in
                guard let session = self?.session else { return }
                try? await session.connection.sendData(d)
            }
        }

        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}

        func scrolled(source: TerminalView, position: Double) {}

        func clipboardCopy(source: TerminalView, content: Data) {}

        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}
