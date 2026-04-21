import Foundation

// MARK: - Session
//
// Manages one active terminal session — one tab in the tab bar.
//
// Command boundary detection uses a sentinel strategy:
// Every command is wrapped as: <cmd>; echo "__MOSAIC_DONE__"; echo "__MOSAIC_PWD__$(pwd)"; ...
// When __MOSAIC_DONE__ appears on its own line we know the command finished — no prompt regex needed.
//
// Commands are tracked in a FIFO queue so rapid submissions don't mix output across blocks.
//
// Data flow:
//   SSH bytes → SwiftTerm (ground truth VT100 processor)
//             → clean text tapped here → RendererRegistry → OutputBlock

@MainActor
public final class Session: ObservableObject, Identifiable {
    public let id = UUID()
    public let connection: any TerminalConnection

    @Published public var blocks: [OutputBlock] = []
    @Published public var currentDirectory: String = "~"
    @Published public var currentBranch: String? = nil
    @Published public var aheadCount: Int = 0
    @Published public var pendingCommand: String = ""

    // Owned strongly — TerminalViewBridge.Coordinator. Held here so
    // it survives tab switches when SwiftUI may tear down the view.
    public var terminalCoordinator: TerminalFeeder? = nil

    // Per-command pending entry: each send() pushes one; handleOutput pops when sentinel found.
    // Using a queue prevents rapid commands from cross-contaminating output blocks.
    private struct PendingEntry {
        let block: OutputBlock
        var buffer: String = ""
    }
    private var pendingQueue: [PendingEntry] = []
    private var outputTask: Task<Void, Never>? = nil

    private static let doneMarker   = "__MOSAIC_DONE__"
    private static let pwdMarker    = "__MOSAIC_PWD__"
    private static let branchMarker = "__MOSAIC_BRANCH__"

    public init(connection: any TerminalConnection) {
        self.connection = connection
    }

    // MARK: - Lifecycle

    public func start() {
        outputTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await data in connection.outputStream {
                await self.handleOutput(data)
            }
        }
    }

    public func stop() {
        outputTask?.cancel()
        outputTask = nil
        for entry in pendingQueue {
            entry.block.rawOutput += "\n[session closed]"
            entry.block.isStreaming = false
        }
        pendingQueue.removeAll()
        Task { await connection.disconnect() }
    }

    // MARK: - Sending Commands

    public func send(_ command: String) async {
        let block = OutputBlock(command: command)
        block.isStreaming = true
        blocks.append(block)
        pendingQueue.append(PendingEntry(block: block))

        // Append sentinels using explicit concatenation — not a multiline literal,
        // which would strip leading whitespace from the user's command and could
        // cause here-documents in the command to consume the sentinel lines.
        let fullCmd = command + "\n"
            + "echo \"__MOSAIC_DONE__\"\n"
            + "echo \"__MOSAIC_PWD__$(pwd)\"\n"
            + "git branch --show-current 2>/dev/null | sed 's/^/__MOSAIC_BRANCH__/'\n"

        do {
            try await connection.send(fullCmd)
        } catch {
            block.rawOutput = "[send error: \(error.localizedDescription)]"
            block.isStreaming = false
            if let idx = pendingQueue.firstIndex(where: { $0.block === block }) {
                pendingQueue.remove(at: idx)
            }
        }
    }

    // MARK: - Output Handling

    private func handleOutput(_ data: Data) async {
        terminalCoordinator?.feed(data: data)

        guard let text = String(data: data, encoding: .utf8)
                      ?? String(data: data, encoding: .isoLatin1)
        else { return }

        guard !pendingQueue.isEmpty else { return }

        pendingQueue[0].buffer += text
        // Re-strip from the full buffer so escape sequences split across Data chunks are handled correctly
        let clean = pendingQueue[0].buffer.strippingANSI
        pendingQueue[0].block.rawOutput = clean
        let cleanLines = clean.components(separatedBy: CharacterSet.newlines)
        let hasDone = cleanLines.contains { $0.trimmingCharacters(in: .whitespaces) == Self.doneMarker }
        if hasDone {
            let entry = pendingQueue.removeFirst()
            extractSentinels(from: clean)
            finalizeBlock(entry.block)
        }
    }

    // MARK: - Sentinels

    private func extractSentinels(from text: String) {
        for line in text.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.hasPrefix(Self.pwdMarker) {
                let path = String(t.dropFirst(Self.pwdMarker.count))
                    .trimmingCharacters(in: .whitespaces)
                if !path.isEmpty { currentDirectory = path }
            } else if t.hasPrefix(Self.branchMarker) {
                let branch = String(t.dropFirst(Self.branchMarker.count))
                    .trimmingCharacters(in: .whitespaces)
                currentBranch = branch.isEmpty ? nil : branch
            }
        }
    }

    // MARK: - Finalization

    private func finalizeBlock(_ block: OutputBlock) {
        let allMarkers = [Self.doneMarker, Self.pwdMarker, Self.branchMarker]

        let raw = block.rawOutput
            .strippingANSI
            .components(separatedBy: "\n")
            .filter { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                return !allMarkers.contains(where: { t.hasPrefix($0) })
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        block.rawOutput = raw

        let result = RendererRegistry.shared.process(command: block.command, output: raw)
        block.cachedRendererResult = result
        if case .native(let renderer, _, _) = result {
            block.rendererID         = renderer.id
            block.rendererBadgeLabel = renderer.badgeLabel
        }

        block.isStreaming = false
    }
}

// MARK: - TerminalFeeder Protocol

public protocol TerminalFeeder: AnyObject {
    func feed(data: Data)
}
