import Foundation
import SwiftData

struct BundledCompletion: Decodable {
    let command: String
    let type: String
}

@MainActor
final class CompletionProvider: ObservableObject {
    @Published var items: [CompletionItem] = []
    private var bundled: [BundledCompletion] = []
    private var matcher: HistoryMatcher?

    init(matcher: HistoryMatcher?) {
        self.matcher = matcher
        loadBundled()
    }

    func setup(matcher: HistoryMatcher) {
        self.matcher = matcher
    }

    private func loadBundled() {
        guard let url = Bundle.main.url(forResource: "completions", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([BundledCompletion].self, from: data)
        else { return }
        bundled = decoded
    }

    func update(for input: String) {
        guard !input.isEmpty else { items = []; return }
        let historyItems = (matcher?.historyMatches(for: input, limit: 3) ?? []).map { CompletionItem(text: $0, kind: .history) }
        let remaining = max(0, 5 - historyItems.count)
        let bundledItems = bundled.filter { $0.command.lowercased().hasPrefix(input.lowercased()) }.prefix(remaining).map { CompletionItem(text: $0.command, kind: $0.type == "snippet" ? .snippet : .command) }
        var seen = Set<String>()
        items = (historyItems + Array(bundledItems)).filter { seen.insert($0.text).inserted }
    }
}
