import Foundation
import SwiftData

// MARK: - OutputBlock
//
// One OutputBlock = one command + its output.
// The session view renders a scrollable list of these.
// Each block stores both raw output and (if applicable) the renderer ID + parsed data.

@Model
public final class OutputBlock {
    public var id: UUID
    public var command: String
    public var rawOutput: String
    public var timestamp: Date

    // Renderer info — nil means raw terminal display
    public var rendererID: String?         // e.g. "docker.ps"
    public var rendererBadgeLabel: String? // e.g. "CONTAINERS"
    public var renderedDataJSON: Data?     // JSON-encoded RendererData

    // UI state — not persisted across launches (ephemeral)
    @Transient public var showingRaw: Bool = false
    @Transient public var isStreaming: Bool = false  // true while output is still arriving

    public init(command: String) {
        self.id        = UUID()
        self.command   = command
        self.rawOutput = ""
        self.timestamp = Date()
    }

    public var isNativelyRendered: Bool {
        rendererID != nil
    }

    public var displayCommand: String {
        command.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
