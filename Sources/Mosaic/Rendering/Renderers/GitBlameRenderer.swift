import SwiftUI

@MainActor
public final class GitBlameRenderer: OutputRenderer {
    public let id          = "git.blame"
    public let displayName = "Git Blame"
    public let badgeLabel  = "GIT BLAME"
    public let priority    = RendererPriority.git

    public func canRender(command: String, output: String) -> Bool {
        guard command.lowercased().hasPrefix("git blame") else { return false }
        // Typical blame lines: "abc1234 (Author Name  2024-01-01 12:00:00 +0000  1) code"
        return output.contains("(") && output.range(of: #"\b\d{4}-\d{2}-\d{2}\b"#, options: .regularExpression) != nil
    }

    public func parse(command: String, output: String) -> (any RendererData)? {
        // Supports both porcelain and default git blame output.
        // Default format: "<hash> (<author> <date> <time> <tz> <line>) <code>"
        let lineRegex = try? NSRegularExpression(
            pattern: #"^([0-9a-f^]+)\s+\((.+?)\s+(\d{4}-\d{2}-\d{2})\s+[\d:]+\s+[+-]\d{4}\s+(\d+)\)\s?(.*)$"#
        )

        let lines = output.components(separatedBy: "\n")
        var blameLines: [BlameLine] = []

        for line in lines {
            let ns = line as NSString
            guard let m = lineRegex?.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
                  m.numberOfRanges >= 6,
                  let hashR   = Range(m.range(at: 1), in: line),
                  let authorR = Range(m.range(at: 2), in: line),
                  let dateR   = Range(m.range(at: 3), in: line),
                  let numR    = Range(m.range(at: 4), in: line),
                  let codeR   = Range(m.range(at: 5), in: line) else { continue }

            let hash   = String(String(line[hashR]).prefix(7))
            let author = String(line[authorR]).trimmingCharacters(in: .whitespaces)
            let date   = String(line[dateR])
            let lineNo = Int(line[numR]) ?? 0
            let code   = String(line[codeR])

            blameLines.append(BlameLine(hash: hash, author: author, date: date, lineNumber: lineNo, code: code))
        }

        guard !blameLines.isEmpty else { return nil }

        // Build unique author palette
        var authorColors: [String: Color] = [:]
        let palette: [Color] = [
            Color(hex: "#00D4AA"), Color(hex: "#4A9EFF"), Color(hex: "#A78BFA"),
            Color(hex: "#FFD060"), Color(hex: "#3DFF8F"), Color(hex: "#FF4D6A"),
            Color(hex: "#FFB020")
        ]
        var paletteIdx = 0
        for line in blameLines {
            if authorColors[line.author] == nil {
                authorColors[line.author] = palette[paletteIdx % palette.count]
                paletteIdx += 1
            }
        }

        let filename = command.components(separatedBy: " ").last ?? ""
        return GitBlameData(filename: filename, lines: blameLines, authorColors: authorColors)
    }

    public func view(for data: any RendererData) -> AnyView {
        guard let data = data as? GitBlameData else { return AnyView(EmptyView()) }
        return AnyView(GitBlameView(data: data))
    }
}

public struct GitBlameData: RendererData {
    public let filename:     String
    public let lines:        [BlameLine]
    public let authorColors: [String: Color]
}

public struct BlameLine: Identifiable, Sendable {
    public let id         = UUID()
    public let hash:       String
    public let author:     String
    public let date:       String
    public let lineNumber: Int
    public let code:       String
}

struct GitBlameView: View {
    let data: GitBlameData

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("GIT BLAME")
                    .font(.custom("JetBrains Mono", size: 8).weight(.bold))
                    .foregroundColor(Color(hex: "#3A4A58"))
                    .kerning(0.4)
                Spacer()
                if !data.filename.isEmpty {
                    Text(data.filename)
                        .font(.custom("JetBrains Mono", size: 9))
                        .foregroundColor(Color(hex: "#D8E4F0"))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().overlay(Color(hex: "#1E1E26"))

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(data.lines) { line in
                        BlameLineView(line: line, color: data.authorColors[line.author] ?? Color(hex: "#3A4A58"))
                    }
                }
            }
            .frame(maxHeight: 400)
        }
        .background(Color(hex: "#111115"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#1E1E26"), lineWidth: 1))
    }
}

struct BlameLineView: View {
    let line:  BlameLine
    let color: Color

    var body: some View {
        HStack(spacing: 0) {
            // Author sidebar strip
            Rectangle()
                .fill(color.opacity(0.6))
                .frame(width: 3)

            // Hash + author
            HStack(spacing: 6) {
                Text(line.hash)
                    .font(.custom("JetBrains Mono", size: 8).weight(.bold))
                    .foregroundColor(color)
                    .frame(width: 44, alignment: .leading)
                Text(String(line.author.prefix(10)))
                    .font(.custom("JetBrains Mono", size: 8))
                    .foregroundColor(Color(hex: "#3A4A58"))
                    .frame(width: 64, alignment: .leading)
                Text(line.date)
                    .font(.custom("JetBrains Mono", size: 8))
                    .foregroundColor(Color(hex: "#1E2830"))
                    .frame(width: 68, alignment: .leading)
            }
            .padding(.horizontal, 8)

            // Line number
            Text(String(format: "%4d", line.lineNumber))
                .font(.custom("JetBrains Mono", size: 9))
                .foregroundColor(Color(hex: "#3A4A58"))
                .frame(width: 32, alignment: .trailing)
                .padding(.trailing, 8)

            // Code
            Text(line.code)
                .font(.custom("JetBrains Mono", size: 10))
                .foregroundColor(Color(hex: "#D8E4F0"))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
        }
        .padding(.vertical, 3)
        .background(Color(hex: "#111115"))
    }
}
