import SwiftUI

@MainActor
public final class CatRenderer: OutputRenderer {
    public let id          = "file.cat"
    public let displayName = "File View"
    public let badgeLabel  = "FILE"
    public let priority    = RendererPriority.filesystem

    public func canRender(command: String, output: String) -> Bool {
        let cmd = command.lowercased().trimmingCharacters(in: .whitespaces)
        guard cmd.hasPrefix("cat ") else { return false }
        let filename = cmd.components(separatedBy: " ").dropFirst().joined(separator: " ")
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        return SyntaxHighlighter.supportedExtensions.contains(ext) || !ext.isEmpty
    }

    public func parse(command: String, output: String) -> (any RendererData)? {
        let lines = output.components(separatedBy: "\n")
        guard !lines.isEmpty && lines.count <= 500 else { return nil }

        let parts    = command.components(separatedBy: " ").dropFirst()
        let filename = parts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        let ext      = URL(fileURLWithPath: filename).pathExtension.lowercased()
        let lang     = SyntaxHighlighter.language(for: ext)

        return CatData(filename: filename, rawLines: lines, language: lang)
    }

    public func view(for data: any RendererData) -> AnyView {
        guard let data = data as? CatData else { return AnyView(EmptyView()) }
        return AnyView(CatView(data: data))
    }
}

public struct CatData: RendererData {
    public let filename: String
    public let rawLines: [String]
    public let language: SyntaxLanguage
}

public enum SyntaxLanguage: String, Sendable {
    case swift, python, javascript, typescript, go, rust, bash, json, yaml, toml, markdown, generic
}

public enum SyntaxHighlighter {
    public static let supportedExtensions: Set<String> = [
        "swift", "py", "js", "ts", "tsx", "jsx", "go", "rs",
        "sh", "bash", "zsh", "json", "yaml", "yml", "toml", "md"
    ]

    public static func language(for ext: String) -> SyntaxLanguage {
        switch ext {
        case "swift":            return .swift
        case "py":               return .python
        case "js", "jsx":        return .javascript
        case "ts", "tsx":        return .typescript
        case "go":               return .go
        case "rs":               return .rust
        case "sh", "bash", "zsh": return .bash
        case "json":             return .json
        case "yaml", "yml":      return .yaml
        case "toml":             return .toml
        case "md":               return .markdown
        default:                 return .generic
        }
    }

    public static func tokens(line: String, language: SyntaxLanguage) -> [SyntaxToken] {
        switch language {
        case .swift:      return tokenize(line, keywords: swiftKeywords, commentPrefix: "//")
        case .python:     return tokenize(line, keywords: pythonKeywords, commentPrefix: "#")
        case .javascript, .typescript: return tokenize(line, keywords: jsKeywords, commentPrefix: "//")
        case .go:         return tokenize(line, keywords: goKeywords, commentPrefix: "//")
        case .rust:       return tokenize(line, keywords: rustKeywords, commentPrefix: "//")
        case .bash:       return tokenize(line, keywords: bashKeywords, commentPrefix: "#")
        case .json:       return tokenizeJSON(line)
        case .yaml:       return tokenizeYAML(line)
        default:          return [SyntaxToken(text: line, kind: .plain)]
        }
    }

    private static let swiftKeywords: Set<String> = [
        "func","var","let","class","struct","enum","protocol","extension","import","return",
        "if","else","guard","for","in","while","switch","case","break","continue","where",
        "throws","async","await","try","public","private","internal","static","final","override",
        "init","deinit","self","super","true","false","nil","some","any","@MainActor","@State",
        "@Binding","@ObservableObject","@Published","@Environment","@EnvironmentObject","actor",
        "nonisolated","isolated","consuming","borrowing","defer","lazy","weak","unowned","mutating"
    ]
    private static let pythonKeywords: Set<String> = [
        "def","class","return","if","elif","else","for","in","while","import","from","as",
        "try","except","finally","with","pass","break","continue","and","or","not","is",
        "lambda","yield","async","await","True","False","None","global","nonlocal","raise"
    ]
    private static let jsKeywords: Set<String> = [
        "function","const","let","var","return","if","else","for","of","in","while","class",
        "import","export","default","from","async","await","try","catch","finally","throw",
        "new","this","typeof","instanceof","true","false","null","undefined","switch","case",
        "break","continue","extends","super","static","get","set","=>","interface","type","enum"
    ]
    private static let goKeywords: Set<String> = [
        "func","var","const","type","struct","interface","package","import","return","if","else",
        "for","range","map","chan","go","defer","select","case","break","continue","switch",
        "fallthrough","goto","make","new","nil","true","false","error"
    ]
    private static let rustKeywords: Set<String> = [
        "fn","let","mut","const","struct","enum","impl","trait","pub","use","mod","return",
        "if","else","for","in","while","loop","match","break","continue","where","async","await",
        "self","Self","true","false","None","Some","Ok","Err","Box","Vec","String","&str"
    ]
    private static let bashKeywords: Set<String> = [
        "if","then","else","elif","fi","for","in","do","done","while","until","case","esac",
        "function","return","echo","exit","export","local","source","set","unset","readonly","shift"
    ]

    private static func tokenize(_ line: String, keywords: Set<String>, commentPrefix: String) -> [SyntaxToken] {
        let trimmed = line.trimmingCharacters(in: .init(charactersIn: " \t"))

        // Full-line comment
        if trimmed.hasPrefix(commentPrefix) {
            return [SyntaxToken(text: line, kind: .comment)]
        }

        // Inline comment split
        var codePart = line
        var commentPart: String? = nil
        if let range = findCommentStart(in: line, prefix: commentPrefix) {
            codePart    = String(line[..<range.lowerBound])
            commentPart = String(line[range.lowerBound...])
        }

        var tokens: [SyntaxToken] = []
        let wordRegex = try? NSRegularExpression(pattern: #"\b([A-Za-z_]\w*)\b|("(?:[^"\\]|\\.)*")|('(?:[^'\\]|\\.)*')|(\d+\.?\d*)"#)
        var lastEnd = codePart.startIndex
        let ns = codePart as NSString
        let matches = wordRegex?.matches(in: codePart, range: NSRange(location: 0, length: ns.length)) ?? []

        for m in matches {
            guard let r = Range(m.range, in: codePart) else { continue }
            if r.lowerBound > lastEnd {
                tokens.append(SyntaxToken(text: String(codePart[lastEnd..<r.lowerBound]), kind: .plain))
            }
            let word = String(codePart[r])
            if m.range(at: 2).location != NSNotFound || m.range(at: 3).location != NSNotFound {
                tokens.append(SyntaxToken(text: word, kind: .string))
            } else if m.range(at: 4).location != NSNotFound {
                tokens.append(SyntaxToken(text: word, kind: .number))
            } else if keywords.contains(word) {
                tokens.append(SyntaxToken(text: word, kind: .keyword))
            } else {
                tokens.append(SyntaxToken(text: word, kind: .plain))
            }
            lastEnd = r.upperBound
        }
        if lastEnd < codePart.endIndex {
            tokens.append(SyntaxToken(text: String(codePart[lastEnd...]), kind: .plain))
        }
        if let c = commentPart {
            tokens.append(SyntaxToken(text: c, kind: .comment))
        }
        return tokens.isEmpty ? [SyntaxToken(text: line, kind: .plain)] : tokens
    }

    private static func findCommentStart(in line: String, prefix: String) -> Range<String.Index>? {
        var inString = false
        var prevChar: Character = " "
        var idx = line.startIndex
        while idx < line.endIndex {
            let c = line[idx]
            if c == "\"" && prevChar != "\\" { inString.toggle() }
            if !inString && line[idx...].hasPrefix(prefix) { return idx..<line.endIndex }
            prevChar = c
            idx = line.index(after: idx)
        }
        return nil
    }

    private static func tokenizeJSON(_ line: String) -> [SyntaxToken] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var tokens: [SyntaxToken] = []
        // JSON key (leading "key":)
        if let colonRange = trimmed.range(of: #"^"[^"]*"\s*:"#, options: .regularExpression) {
            let keyEnd = colonRange.upperBound
            let leading = String(line.prefix(line.count - trimmed.count))
            tokens.append(SyntaxToken(text: leading + String(trimmed[..<keyEnd]), kind: .keyword))
            let rest = String(trimmed[keyEnd...])
            tokens.append(contentsOf: tokenizeJSONValue(rest))
        } else {
            tokens.append(contentsOf: tokenizeJSONValue(line))
        }
        return tokens.isEmpty ? [SyntaxToken(text: line, kind: .plain)] : tokens
    }

    private static func tokenizeJSONValue(_ s: String) -> [SyntaxToken] {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("\"") { return [SyntaxToken(text: s, kind: .string)] }
        if t == "true" || t == "false" || t == "null" { return [SyntaxToken(text: s, kind: .keyword)] }
        if Double(t.trimmingCharacters(in: CharacterSet(charactersIn: ",]}"))) != nil {
            return [SyntaxToken(text: s, kind: .number)]
        }
        return [SyntaxToken(text: s, kind: .plain)]
    }

    private static func tokenizeYAML(_ line: String) -> [SyntaxToken] {
        if line.trimmingCharacters(in: .whitespaces).hasPrefix("#") {
            return [SyntaxToken(text: line, kind: .comment)]
        }
        if let colonIdx = line.firstIndex(of: ":") {
            let key   = String(line[...colonIdx])
            let value = String(line[line.index(after: colonIdx)...])
            return [SyntaxToken(text: key, kind: .keyword), SyntaxToken(text: value, kind: .string)]
        }
        return [SyntaxToken(text: line, kind: .plain)]
    }
}

public struct SyntaxToken: Sendable {
    public enum Kind: Sendable { case plain, keyword, string, number, comment }
    public let text: String
    public let kind: Kind

    public var color: Color {
        switch kind {
        case .plain:   return Color(hex: "#D8E4F0")
        case .keyword: return Color(hex: "#4A9EFF")
        case .string:  return Color(hex: "#3DFF8F")
        case .number:  return Color(hex: "#FFD060")
        case .comment: return Color(hex: "#3A4A58")
        }
    }
}

private struct SyntaxLineView: View {
    let tokens: [SyntaxToken]

    private var attributed: AttributedString {
        var result = AttributedString()
        for token in tokens {
            var part = AttributedString(token.text)
            part.swiftUI.foregroundColor = token.color
            result.append(part)
        }
        return result
    }

    var body: some View {
        Text(attributed)
            .font(.custom("JetBrains Mono", size: 10))
    }
}

struct CatView: View {
    let data: CatData

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: fileIcon(data.filename))
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#00D4AA"))
                Text(data.filename)
                    .font(.custom("JetBrains Mono", size: 10).weight(.semibold))
                    .foregroundColor(Color(hex: "#D8E4F0"))
                Spacer()
                Text(data.language.rawValue.uppercased())
                    .font(.custom("JetBrains Mono", size: 8).weight(.bold))
                    .foregroundColor(Color(hex: "#3A4A58"))
                    .kerning(0.4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().overlay(Color(hex: "#1E1E26"))

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(data.rawLines.enumerated()), id: \.offset) { idx, line in
                        HStack(alignment: .top, spacing: 0) {
                            Text(String(format: "%4d", idx + 1))
                                .font(.custom("JetBrains Mono", size: 10))
                                .foregroundColor(Color(hex: "#1E2830"))
                                .frame(width: 36, alignment: .trailing)
                                .padding(.trailing, 12)

                            if data.language == .generic {
                                Text(line.isEmpty ? " " : line)
                                    .font(.custom("JetBrains Mono", size: 10))
                                    .foregroundColor(Color(hex: "#D8E4F0"))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                let tokens = SyntaxHighlighter.tokens(line: line, language: data.language)
                                SyntaxLineView(tokens: tokens)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.vertical, 1)
                        .padding(.horizontal, 8)
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 420)
        }
        .background(Color(hex: "#111115"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#1E1E26"), lineWidth: 1))
    }

    private func fileIcon(_ name: String) -> String {
        let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
        switch ext {
        case "swift":            return "swift"
        case "py":               return "doc.text"
        case "js", "ts", "jsx", "tsx": return "doc.text"
        case "json":             return "curlybraces"
        case "yaml", "yml":      return "doc.text"
        case "md":               return "doc.richtext"
        case "sh", "bash", "zsh": return "terminal"
        default:                 return "doc"
        }
    }
}
