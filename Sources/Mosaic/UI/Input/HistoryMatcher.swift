import SwiftData
import Foundation

@MainActor
final class HistoryMatcher {
    private let context: ModelContext

    init(context: ModelContext) { self.context = context }

    func ghostSuffix(for input: String) -> String? {
        guard !input.isEmpty else { return nil }
        let descriptor = FetchDescriptor<CommandHistory>(sortBy: [SortDescriptor(\CommandHistory.timestamp, order: .reverse)])
        guard let all = try? context.fetch(descriptor) else { return nil }
        var seen = Set<String>()
        let unique = all.filter { seen.insert($0.command).inserted }
        guard let match = unique.first(where: { $0.command.hasPrefix(input) && $0.command != input }) else { return nil }
        return String(match.command.dropFirst(input.count))
    }

    func historyMatches(for input: String, limit: Int = 3) -> [String] {
        guard !input.isEmpty else { return [] }
        let descriptor = FetchDescriptor<CommandHistory>(sortBy: [SortDescriptor(\CommandHistory.timestamp, order: .reverse)])
        guard let all = try? context.fetch(descriptor) else { return [] }
        var seen = Set<String>()
        return all.filter { seen.insert($0.command).inserted }
            .filter { $0.command.hasPrefix(input) && $0.command != input }
            .prefix(limit).map(\.command)
    }

    func save(command: String, hostname: String) {
        let dedupeDescriptor = FetchDescriptor<CommandHistory>(predicate: #Predicate { $0.command == command })
        if let existing = try? context.fetch(dedupeDescriptor) { existing.forEach { context.delete($0) } }
        context.insert(CommandHistory(command: command, sessionHostname: hostname))
        let allDesc = FetchDescriptor<CommandHistory>(sortBy: [SortDescriptor(\CommandHistory.timestamp, order: .forward)])
        if let all = try? context.fetch(allDesc), all.count > 10_000 { all.prefix(all.count - 10_000).forEach { context.delete($0) } }
        try? context.save()
    }
}
