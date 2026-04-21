import Foundation

// MARK: - OutputBlock
//
// One OutputBlock = one command + its output.
// Ephemeral per-session — held in Session.blocks array, not persisted.
// Phase 2 will reintroduce persistence once session history UX is defined.

@MainActor
public final class OutputBlock: ObservableObject, Identifiable {
    public let id        = UUID()
    public let command:  String
    public let timestamp = Date()

    @Published public var rawOutput:   String = ""
    @Published public var isStreaming: Bool   = false

    // Set once in Session.finalizeBlock — never mutated after that
    public var rendererID:         String?        = nil
    public var rendererBadgeLabel: String?        = nil

    // Cached renderer result — avoids re-parsing output on every SwiftUI render
    public var cachedRendererResult: RendererResult? = nil

    public init(command: String) {
        self.command = command
    }

    public var isNativelyRendered: Bool { rendererID != nil }

    public var displayCommand: String {
        command.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
