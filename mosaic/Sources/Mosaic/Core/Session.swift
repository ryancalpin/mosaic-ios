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
    @Published public var connectionState: ConnectionState = .disconnected

    // Owned strongly — TerminalViewBridge.Coordinator. Held here so
    // it survives tab switches when SwiftUI may tear down the view.
    public var terminalCoordinator: TerminalFeeder? = nil

    // Per-command pending entry: each send() pushes one; handleOutput pops when sentinel found.
    // Using a queue prevents rapid commands from cross-contaminating output blocks.
    private struct PendingEntry {
        let block: OutputBlock
        var buffer: String = ""
        var cleanBuffer: String = ""  // incrementally built ANSI-stripped output
    }
    private var pendingQueue: [PendingEntry] = []
    private var outputTask: Task<Void, Never>? = nil
    // Cancels the head entry after 60 s — prevents permanent deadlock when the user runs
    // interactive sub-processes (ssh, python, node) that consume sentinel lines internally.
    private var headTimeoutTask: Task<Void, Never>? = nil

    private static let doneMarker   = "__MOSAIC_DONE__"
    private static let pwdMarker    = "__MOSAIC_PWD__"
    private static let branchMarker = "__MOSAIC_BRANCH__"
    private static let aheadMarker  = "__MOSAIC_AHEAD__"

    public init(connection: any TerminalConnection) {
        self.connection = connection
    }

    // MARK: - Lifecycle

    public func start() {
        outputTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await data in connection.outputStream {
                self.handleOutput(data)
            }
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            for await state in connection.stateStream {
                self.connectionState = state
            }
        }
    }

    public func stop() async {
        headTimeoutTask?.cancel()
        headTimeoutTask = nil
        await connection.disconnect()  // finishes outputStream continuation
        await outputTask?.value        // wait for the for-await loop to fully drain buffered items
        outputTask = nil
        for entry in pendingQueue {
            entry.block.rawOutput += "\n[session closed]"
            finalizeBlock(entry.block)  // strips ANSI+sentinels, sets cachedRendererResult and isStreaming=false
        }
        pendingQueue.removeAll()
    }

    // MARK: - Head Timeout

    private func armHeadTimeout() {
        headTimeoutTask?.cancel()
        guard !pendingQueue.isEmpty else { headTimeoutTask = nil; return }
        let block = pendingQueue[0].block
        headTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard let self, !Task.isCancelled,
                  let idx = self.pendingQueue.firstIndex(where: { $0.block === block }) else { return }
            let entry = self.pendingQueue.remove(at: idx)
            self.finalizeBlock(entry.block)
            self.armHeadTimeout()
        }
    }

    // MARK: - Sending Commands

    public func send(_ command: String) async {
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let block = OutputBlock(command: command)
        block.isStreaming = true
        blocks.append(block)
        let wasEmpty = pendingQueue.isEmpty
        pendingQueue.append(PendingEntry(block: block))
        if wasEmpty { armHeadTimeout() }

        // Append sentinels using explicit concatenation — not a multiline literal,
        // which would strip leading whitespace from the user's command and could
        // cause here-documents in the command to consume the sentinel lines.
        let fullCmd = command + "\n"
            + "true\n"
            + "echo \"__MOSAIC_DONE__\"\n"
            + "echo \"__MOSAIC_PWD__$(pwd)\"\n"
            + "git branch --show-current 2>/dev/null | sed 's/^/__MOSAIC_BRANCH__/' || true\n"
            + "echo \"__MOSAIC_AHEAD__$(git rev-list --count @{u}..HEAD 2>/dev/null || echo 0)\"\n"

        do {
            try await connection.send(fullCmd)
        } catch {
            block.rawOutput = "[send error: \(error.localizedDescription)]"
            block.isStreaming = false
            pendingCommand = command  // restore input so user can retry
            if let idx = pendingQueue.firstIndex(where: { $0.block === block }) {
                let wasHead = (idx == 0)
                pendingQueue.remove(at: idx)
                if wasHead { armHeadTimeout() }
            }
        }
    }

    // MARK: - Output Handling

    @MainActor
    private func handleOutput(_ data: Data) {
        terminalCoordinator?.feed(data: data)

        guard let text = String(data: data, encoding: .utf8)
                      ?? String(data: data, encoding: .isoLatin1)
        else { return }

        guard !pendingQueue.isEmpty else { return }

        pendingQueue[0].buffer += text

        // Incrementally update cleanBuffer: re-strip only the new text plus a 64-char
        // overlap from the raw buffer tail to handle ANSI sequences split across packets.
        // This is O(packet_size) per call vs O(total_buffer_size) for a full re-strip.
        let kOverlap = 64
        let ns = pendingQueue[0].buffer as NSString
        let textNSLen = (text as NSString).length
        let prevLen = ns.length - textNSLen
        if prevLen > kOverlap {
            let rawTail = ns.substring(from: ns.length - textNSLen - kOverlap)
            let cleanTail = rawTail.strippingANSI
            // Determine how many clean chars the overlap region (kOverlap raw chars) produced
            // so we remove exactly that many — not a fixed 64, which would over-delete when
            // the overlap contains ANSI sequences that strip to fewer clean chars.
            let rawOverlapOnly = ns.substring(with: NSRange(location: ns.length - textNSLen - kOverlap,
                                                            length: kOverlap))
            // Use NSString.length (UTF-16 units) consistently with the NSMutableString deletion
            // below so that multi-byte grapheme clusters don't cause under-deletion.
            let cleanOverlapLen = (rawOverlapOnly.strippingANSI as NSString).length
            let cleanNS = NSMutableString(string: pendingQueue[0].cleanBuffer)
            let removeLen = min(cleanOverlapLen, cleanNS.length)
            if removeLen > 0 {
                cleanNS.deleteCharacters(in: NSRange(location: cleanNS.length - removeLen, length: removeLen))
            }
            cleanNS.append(cleanTail)
            pendingQueue[0].cleanBuffer = cleanNS as String
        } else {
            pendingQueue[0].cleanBuffer = pendingQueue[0].buffer.strippingANSI
        }
        let clean = pendingQueue[0].cleanBuffer

        // Filter sentinel lines and the PTY command echo from the live display
        let allMarkers = [Self.doneMarker, Self.pwdMarker, Self.branchMarker, Self.aheadMarker]
        // Compare only the first line of the command echo — multi-line commands would have
        // embedded newlines that can never match a single displayLines.first.
        let cmdEchoFirstLine = pendingQueue[0].block.command
            .components(separatedBy: "\n").first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var displayLines = clean.components(separatedBy: "\n")
        // Strip the first line if it's the PTY echo of the command.
        // Guard against empty cmdEchoFirstLine to avoid stripping blank output lines.
        if !cmdEchoFirstLine.isEmpty,
           displayLines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == cmdEchoFirstLine {
            displayLines.removeFirst()
        }
        pendingQueue[0].block.rawOutput = displayLines
            .filter { line in
                let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return !allMarkers.contains(where: { t.hasPrefix($0) })
            }
            .joined(separator: "\n")

        // Sentinel detection: scan only the recent tail of clean output so this
        // check doesn't also degrade to O(total_buffer_size) on every packet.
        // 2048 units covers all four sentinel lines plus generous post-sentinel output.
        let cleanNS = clean as NSString
        let sentinelTail = cleanNS.substring(from: max(0, cleanNS.length - 2048))
        let hasDone = sentinelTail.components(separatedBy: CharacterSet.newlines)
            .contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == Self.doneMarker }
        if hasDone {
            let entry = pendingQueue.removeFirst()
            extractSentinels(from: clean)
            finalizeBlock(entry.block)
            armHeadTimeout()
        }
    }

    // MARK: - Sentinels

    private func extractSentinels(from text: String) {
        var sawBranch = false
        var sawAhead  = false
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
                sawBranch = true
            } else if t.hasPrefix(Self.aheadMarker) {
                let countStr = String(t.dropFirst(Self.aheadMarker.count))
                    .trimmingCharacters(in: .whitespaces)
                aheadCount = Int(countStr) ?? 0
                sawAhead = true
            }
        }
        // Clear stale values when markers are absent (non-git dir, detached HEAD, no upstream)
        if !sawBranch { currentBranch = nil }
        if !sawAhead  { aheadCount = 0 }
    }

    // MARK: - Finalization

    private func finalizeBlock(_ block: OutputBlock) {
        let allMarkers = [Self.doneMarker, Self.pwdMarker, Self.branchMarker, Self.aheadMarker]

        let raw = block.rawOutput
            .strippingANSI
            .components(separatedBy: "\n")
            .filter { line in
                let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
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
