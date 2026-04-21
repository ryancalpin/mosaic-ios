import Foundation

// MARK: - Session
//
// Manages one active terminal session — one tab in the tab bar.
//
// Command boundary detection uses a sentinel strategy:
// Every command is wrapped as: <cmd>; echo "__MOSAIC_DONE__"; echo "__MOSAIC_PWD__$(pwd)"; ...
// When __MOSAIC_DONE__ appears in output we know the command finished — no prompt regex needed.
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

    private var outputBuffer: String = ""
    private var activeBlock: OutputBlock? = nil
    private var outputTask: Task<Void, Never>? = nil

    private static let doneMarker   = "__MOSAIC_DONE__"
    private static let pwdMarker    = "__MOSAIC_PWD__"
    private static let branchMarker = "__MOSAIC_BRANCH__"

    public init(connection: any TerminalConnection) {
        self.connection = connection
    }

    deinit {
        outputTask?.cancel()
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

        // Append sentinels so we know when the command completes reliably.
        // __MOSAIC_DONE__ is the definitive end-of-command signal.
        let fullCmd = """
            \(command)
            echo "__MOSAIC_DONE__"
            echo "__MOSAIC_PWD__$(pwd)"
            git branch --show-current 2>/dev/null | sed 's/^/__MOSAIC_BRANCH__/'
            """

        do {
            try await connection.send(fullCmd + "\n")
        } catch {
            block.rawOutput = "[send error: \(error.localizedDescription)]"
            block.isStreaming = false
            activeBlock = nil
        }
    }

    // MARK: - Output Handling

    private func handleOutput(_ data: Data) async {
        terminalCoordinator?.feed(data: data)

        guard let text = String(data: data, encoding: .utf8)
                      ?? String(data: data, encoding: .isoLatin1)
        else { return }

        outputBuffer += text
        activeBlock?.rawOutput += text

        let clean = outputBuffer.strippingANSI
        if clean.contains(Self.doneMarker), let block = activeBlock {
            extractSentinels(from: clean)
            finalizeBlock(block)
        }
    }

    // MARK: - Sentinels

    private func extractSentinels(from text: String) {
        for line in text.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
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
        activeBlock = nil
        outputBuffer = ""
    }
}

// MARK: - TerminalFeeder Protocol

public protocol TerminalFeeder: AnyObject {
    func feed(data: Data)
}
