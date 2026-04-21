import Foundation

// MARK: - RendererRegistry
//
// Singleton. Receives raw terminal output + the command that produced it.
// Tries each registered renderer in priority order.
// Returns a RendererResult — either .native(...) or .raw(text).
//
// Usage:
//   let result = RendererRegistry.shared.process(command: "docker ps", output: rawText)

@MainActor
public final class RendererRegistry: ObservableObject {
    public static let shared = RendererRegistry()

    private var renderers: [any OutputRenderer] = []
    private var aliasMap: [String: String] = [:]  // e.g. ["dps": "docker ps"]

    private init() {
        registerBuiltins()
    }

    // MARK: - Registration

    public func register(_ renderer: any OutputRenderer) {
        renderers.append(renderer)
        renderers.sort { $0.priority > $1.priority }
    }

    public func unregister(id: String) {
        renderers.removeAll { $0.id == id }
    }

    public func renderer(id: String) -> (any OutputRenderer)? {
        renderers.first { $0.id == id }
    }

    // Matches: alias name='value'  OR  name='value'  (single or double quotes)
    private static let aliasRegex = try? NSRegularExpression(
        pattern: #"(?:alias\s+)?(\w+)=(?:'([^']*)'|"([^"]*)")"#
    )

    /// Call this after connecting to a server — parse `alias` output to build the alias map.
    public func updateAliases(from aliasOutput: String) {
        aliasMap.removeAll()
        let regex = Self.aliasRegex
        for line in aliasOutput.components(separatedBy: "\n") {
            let ns = line as NSString
            guard let match = regex?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  match.numberOfRanges >= 3 else { continue }
            guard let nameRange = Range(match.range(at: 1), in: line) else { continue }
            let alias = String(line[nameRange])
            // Group 2 = single-quoted value, group 3 = double-quoted value
            let valueRange = (2...3).compactMap { Range(match.range(at: $0), in: line) }.first
            guard let vr = valueRange else { continue }
            let command = String(line[vr])
            guard !alias.isEmpty, !command.isEmpty else { continue }
            aliasMap[alias] = command
            _ = ns  // suppress unused warning
        }
    }

    // MARK: - Processing

    public func process(command: String, output: String) -> RendererResult {
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .raw(output)
        }

        // Resolve alias before matching
        let resolvedCommand = resolveAlias(command)

        // Try each renderer in priority order
        for renderer in renderers {
            guard renderer.canRender(command: resolvedCommand, output: output) else { continue }
            guard let data = renderer.parse(command: resolvedCommand, output: output) else { continue }
            // Successful parse
            return .native(renderer: renderer, data: data, raw: output)
        }

        // No renderer matched — fall through to raw
        return .raw(output)
    }

    // MARK: - Private

    private func resolveAlias(_ command: String) -> String {
        let firstToken = command.components(separatedBy: " ").first ?? command
        if let resolved = aliasMap[firstToken] {
            let remainder = command.dropFirst(firstToken.count)
            return resolved + remainder
        }
        return command
    }

    private func registerBuiltins() {
        // Phase 1
        register(DockerPsRenderer())
        register(GitStatusRenderer())
        register(FileListRenderer())
        // Phase 2
        register(PingRenderer())
        register(DiskUsageRenderer())
        register(HttpResponseRenderer())
        register(ProcessTableRenderer())
        register(NpmInstallRenderer())
        register(JsonTreeRenderer())
        register(GitDiffRenderer())
        register(CronRenderer())
    }
}
