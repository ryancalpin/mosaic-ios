import Foundation

// MARK: - Session
//
// Manages one active terminal session — one tab in the tab bar.
// Owns a TerminalConnection (SSH or Mosh), accumulates OutputBlocks,
// tracks current directory and git branch for the breadcrumb.
//
// Data flow:
//   SSH bytes → SwiftTerm (ground truth VT100 processor)
//              → clean text tapped here → RendererRegistry → OutputBlock

@MainActor
public final class Session: ObservableObject, Identifiable {
    public let id = UUID()
    public let connection: any TerminalConnection

    @Published public var blocks: [OutputBlock] = []
    @Published public var currentDirectory: String = "~"
    @Published public var currentBranch: String? = nil
    @Published public var aheadCount: Int = 0
    @Published public var pendingCommand: String = ""

    // SwiftTerm coordinator — set by TerminalViewBridge when the view appears
    public weak var terminalCoordinator: AnyObject? = nil

    private var outputBuffer: String = ""
    private var activeBlock: OutputBlock? = nil
    private var outputTask: Task<Void, Never>? = nil

    // Shell prompt detector — matches common bash/zsh prompts ending with $ or #
    private static let promptPattern = try? NSRegularExpression(
        pattern: #"(?:^|\n)[^\n$#]*[$#]\s*$"#
    )

    public init(connection: any TerminalConnection) {
        self.connection = connection
    }

    // MARK: - Lifecycle

    public func start() {
        outputTask = Task { [weak self] in
            guard let self else { return }
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
        let block = OutputBlock(command: command)
        block.isStreaming = true
        blocks.append(block)
        activeBlock = block
        outputBuffer = ""

        // Run a silent pwd + branch check after every command to keep breadcrumb current
        let fullCmd = command + "; echo \"__MOSAIC_PWD__$(pwd)\"; git branch --show-current 2>/dev/null | sed 's/^/__MOSAIC_BRANCH__/'\n"

        do {
            try await connection.send(fullCmd)
        } catch {
            block.rawOutput = "[send error: \(error.localizedDescription)]"
            block.isStreaming = false
            activeBlock = nil
        }
    }

    // MARK: - Output Handling

    private func handleOutput(_ data: Data) async {
        // 1. Feed raw bytes to SwiftTerm (ground truth VT100 processor)
        feedSwiftTerm(data)

        guard let text = String(data: data, encoding: .utf8)
                      ?? String(data: data, encoding: .isoLatin1)
        else { return }

        outputBuffer += text
        activeBlock?.rawOutput += text

        // 2. Check for our sentinel markers (breadcrumb updates)
        processSentinels()

        // 3. Detect command completion via prompt pattern
        let clean = outputBuffer.strippingANSI
        if looksLikePromptReturn(clean), let block = activeBlock {
            finalizeBlock(block)
        }
    }

    private func feedSwiftTerm(_ data: Data) {
        // TerminalViewBridge.Coordinator conforms to this; we avoid a direct SwiftTerm import
        // in the view layer by routing through the session.
        guard let coordinator = terminalCoordinator as? TerminalFeeder else { return }
        coordinator.feed(data: data)
    }

    private func processSentinels() {
        // Extract __MOSAIC_PWD__ and __MOSAIC_BRANCH__ injected after every command
        let lines = outputBuffer.strippingANSI.components(separatedBy: "\n")
        for line in lines {
            if line.hasPrefix("__MOSAIC_PWD__") {
                let path = String(line.dropFirst("__MOSAIC_PWD__".count))
                    .trimmingCharacters(in: .whitespaces)
                if !path.isEmpty { currentDirectory = path }
            } else if line.hasPrefix("__MOSAIC_BRANCH__") {
                let branch = String(line.dropFirst("__MOSAIC_BRANCH__".count))
                    .trimmingCharacters(in: .whitespaces)
                currentBranch = branch.isEmpty ? nil : branch
            }
        }
    }

    private func looksLikePromptReturn(_ text: String) -> Bool {
        guard let re = Self.promptPattern else { return false }
        let range = NSRange(text.startIndex..., in: text)
        // Must have some output AND end with a prompt line
        return re.firstMatch(in: text, range: range) != nil && text.count > 20
    }

    private func finalizeBlock(_ block: OutputBlock) {
        // Strip our sentinels from the raw output before storing
        let raw = block.rawOutput
            .strippingANSI
            .components(separatedBy: "\n")
            .filter { !$0.hasPrefix("__MOSAIC_PWD__") && !$0.hasPrefix("__MOSAIC_BRANCH__") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Store cleaned raw
        block.rawOutput = raw

        // Pass through renderer registry
        let result = RendererRegistry.shared.process(command: block.command, output: raw)
        if case .native(let renderer, _, _) = result {
            block.rendererID         = renderer.id
            block.rendererBadgeLabel = renderer.badgeLabel
        }

        block.isStreaming = false
        activeBlock = nil
        outputBuffer = ""
    }
}

// MARK: - TerminalFeeder Protocol

// Thin protocol so Session doesn't have to import SwiftTerm UI types.
public protocol TerminalFeeder: AnyObject {
    func feed(data: Data)
}
