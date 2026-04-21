import SwiftUI

// MARK: - MosaicCommands

struct MosaicCommands: Commands {
    @ObservedObject private var manager = SessionManager.shared
    @Binding var showConnectionSheet: Bool

    var body: some Commands {
        CommandMenu("Session") {
            Button("New Connection") { showConnectionSheet = true }
                .keyboardShortcut("t", modifiers: .command)

            Button("Close Session") {
                guard let session = manager.activeSession else { return }
                manager.closeSession(session)
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(manager.activeSession == nil)

            Divider()

            Button("Command Palette") { showConnectionSheet = true }
                .keyboardShortcut("k", modifiers: .command)

            Divider()

            Button("Scroll to Top") {
                NotificationCenter.default.post(name: .mosaicScrollToTop, object: nil)
            }
            .keyboardShortcut(.upArrow, modifiers: .command)
            .disabled(manager.activeSession == nil)

            Button("Scroll to Bottom") {
                NotificationCenter.default.post(name: .mosaicScrollToBottom, object: nil)
            }
            .keyboardShortcut(.downArrow, modifiers: .command)
            .disabled(manager.activeSession == nil)

            Divider()

            Button("Send Interrupt (^C)") {
                manager.activeSession?.sendSignal(.interrupt)
            }
            .keyboardShortcut("c", modifiers: .control)
            .disabled(manager.activeSession == nil)

            Divider()

            ForEach(1...9, id: \.self) { index in
                Button("Switch to Session \(index)") {
                    manager.activate(at: index)
                }
                .keyboardShortcut(KeyEquivalent(Character(String(index))), modifiers: .command)
                .disabled(manager.sessions.count < index)
            }
        }
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let mosaicScrollToTop    = Notification.Name("mosaic.scrollToTop")
    static let mosaicScrollToBottom = Notification.Name("mosaic.scrollToBottom")
}
