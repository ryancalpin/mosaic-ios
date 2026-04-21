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

    /// Call this after connecting to a server — parse `alias` output to build the alias map.
    public func updateAliases(from aliasOutput: String) {
        aliasMap.removeAll()
        for line in aliasOutput.components(separatedBy: "\n") {
            // Format: alias dps='docker ps'  OR  dps='docker ps'
            let clean = line.replacingOccurrences(of: "^alias\\s+", with: "", options: .regularExpression)
            let parts = clean.components(separatedBy: "=")
            guard parts.count >= 2 else { continue }
            let alias   = parts[0].trimmingCharacters(in: .whitespaces)
            let command = parts[1...].joined(separator: "=")
                .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            aliasMap[alias] = command
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
        register(DockerPsRenderer())
        register(GitStatusRenderer())
        register(FileListRenderer())
        // Phase 2 renderers registered here as they're built:
        // register(PingRenderer())
        // register(DiskUsageRenderer())
        // register(HttpResponseRenderer())
        // register(NpmInstallRenderer())
        // register(JsonTreeRenderer())
        // register(CronRenderer())
        // register(ProcessTableRenderer())
        // register(GitDiffRenderer())
        // register(GitLogRenderer())
    }
}
