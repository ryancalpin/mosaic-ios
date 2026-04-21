import Foundation

extension String {
    private static let ansiRegex = try! NSRegularExpression(
        pattern: #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"#
    )

    /// Strip ANSI/VT100 escape sequences, returning plain text.
    var strippingANSI: String {
        let range = NSRange(startIndex..., in: self)
        return String.ansiRegex.stringByReplacingMatches(in: self, range: range, withTemplate: "")
    }

    /// Trim leading/trailing whitespace and ANSI codes, leaving clean output text.
    var cleanedTerminalOutput: String {
        strippingANSI.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
