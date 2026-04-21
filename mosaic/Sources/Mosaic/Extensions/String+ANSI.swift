import Foundation

extension String {
    /// Strip ANSI/VT100 escape sequences, returning plain text.
    var strippingANSI: String {
        guard let regex = try? NSRegularExpression(
            pattern: #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"#
        ) else { return self }
        let range = NSRange(startIndex..., in: self)
        return regex.stringByReplacingMatches(in: self, range: range, withTemplate: "")
    }

    /// Trim leading/trailing whitespace and ANSI codes, leaving clean output text.
    var cleanedTerminalOutput: String {
        strippingANSI.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
