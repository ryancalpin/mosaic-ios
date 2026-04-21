import Foundation
import SwiftData

// MARK: - Session
//
// Manages one active terminal session — one tab in the tab bar.
// Owns a TerminalConnection (SSH or Mosh), accumulates OutputBlocks,
// tracks current directory and git branch for the breadcrumb.

@MainActor
public final class Session: ObservableObject, Identifiable {
    public let id = UUID()
    public let connection: any TerminalConnection

    @Published public var blocks: [OutputBlock] = []
    @Published public var currentDirectory: String = "~"
    @Published public var currentBranch: String? = nil
    @Published public var aheadCount: Int = 0

    // The command currently being typed / not yet submitted
    @Published public var pendingCommand: String = ""

    private var outputBuffer: String = ""
    private var activeBlock: OutputBlock? = nil
    private var outputTask: Task<Void, Never>? = nil

    // Shell prompt detector — matches common bash/zsh prompts ending with $ or #
    private static let promptPattern = try? NSRegularExpression(
        pattern: #"(?:^|\n)[^\n]*[$#]\s*$"#
    )

    public init(connection: any TerminalConnection) {
        self.connection = connection
    }

    // MARK: - Lifecycle

    public func start() {
        outputTask = Task {
            for await data in connection.outputStream {
                await handleOutput(data)
            }
        }
    }

    public func stop() {
        outputTask?.cancel()
        outputTask = nil
        Task { await connection.disconnect() }
    }

    // MARK: - Sending Commands

    public func send(_ command: String) async {
        let tier = SafetyClassifier.shared.classify(command)
        guard tier.isImmediate else { return }

        let block = OutputBlock(command: command)
        block.isStreaming = true
        blocks.append(block)
        activeBlock = block
        outputBuffer = ""

        do {
            try await connection.send(command + "\n")
            // After sending, run bookkeeping commands silently
        } catch {
            block.rawOutput = "[send error: \(error.localizedDescription)]"
            block.isStreaming = false
            activeBlock = nil
        }
    }

    // MARK: - Output Handling

    private func handleOutput(_ data: Data) async {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return }

        outputBuffer += text

        guard let block = activeBlock else { return }

        // Append raw output to current block
        block.rawOutput += text

        // Check if prompt has returned (command complete)
        let clean = outputBuffer.strippingANSI
        if looksLikePromptReturn(clean) {
            finalizeBlock(block)
        }
    }

    private func looksLikePromptReturn(_ text: String) -> Bool {
        guard let re = Self.promptPattern else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return re.firstMatch(in: text, range: range) != nil && text.count > 10
    }

    private func finalizeBlock(_ block: OutputBlock) {
        let raw = block.rawOutput.strippingANSI

        // Pass through renderer registry
        let result = RendererRegistry.shared.process(command: block.command, output: raw)
        switch result {
        case .native(let renderer, let data, _):
            block.rendererID        = renderer.id
            block.rendererBadgeLabel = renderer.badgeLabel
            // Store renderer data as JSON (best-effort)
            block.renderedDataJSON  = nil
        case .raw:
            break
        }

        block.isStreaming = false
        activeBlock = nil
        outputBuffer = ""

        // Parse breadcrumb updates from output
        updateBreadcrumb(from: raw)
    }

    // MARK: - Breadcrumb Updates

    private func updateBreadcrumb(from output: String) {
        // Extract current directory from pwd output if detected
        let lines = output.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
                // Looks like a path from pwd
                if !trimmed.contains(" ") && trimmed.count < 200 {
                    currentDirectory = trimmed
                }
            }
        }
    }

    public func updateBranch(_ branch: String?) {
        currentBranch = branch
    }
}
