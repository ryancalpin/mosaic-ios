import Foundation

final class TypoCorrector {
    static let shared = TypoCorrector()
    private var map: [String: String] = [:]

    private init() {
        guard let url = Bundle.main.url(forResource: "typos", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        map = dict
    }

    func correct(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        for (typo, fix) in map {
            if trimmed.lowercased() == typo.lowercased() {
                let corrected = input.replacingOccurrences(of: typo, with: fix, options: .caseInsensitive)
                return corrected == input ? nil : corrected
            }
        }
        let words = trimmed.components(separatedBy: " ")
        guard let lastWord = words.last, !lastWord.isEmpty, let fix = map[lastWord.lowercased()] else { return nil }
        var prefix = words.dropLast().joined(separator: " ")
        if !prefix.isEmpty { prefix += " " }
        let corrected = prefix + fix + (input.hasSuffix(" ") ? " " : "")
        return corrected == input ? nil : corrected
    }
}
