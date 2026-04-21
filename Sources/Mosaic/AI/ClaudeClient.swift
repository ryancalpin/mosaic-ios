import Foundation

@MainActor
final class ClaudeClient {
    let apiKey:   String
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    init(apiKey: String) { self.apiKey = apiKey }

    struct TranslationContext {
        let hostname:         String
        let username:         String
        let currentDirectory: String
        let recentCommands:   [String]
        let serverOS:         String
    }

    func translateToCommand(_ userInput: String, context: TranslationContext) async throws -> String {
        let systemPrompt = """
        You are a shell command assistant for a terminal app called Mosaic.
        The user is connected to \(context.hostname) (\(context.serverOS)) as \(context.username).
        Current directory: \(context.currentDirectory)

        Respond with ONLY a shell command — no markdown, no explanation, no backticks.
        The command must be safe to run on a real production server.
        Recent commands for context: \(context.recentCommands.suffix(20).joined(separator: "; "))
        """

        let body: [String: Any] = [
            "model":      "claude-sonnet-4-6",
            "max_tokens": 256,
            "system":     systemPrompt,
            "messages":   [["role": "user", "content": userInput]]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey,             forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01",       forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let json    = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let content = (json?["content"] as? [[String: Any]])?.first
        guard let text = content?["text"] as? String else { throw URLError(.cannotParseResponse) }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
