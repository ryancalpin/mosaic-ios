import SwiftUI

@MainActor
public final class GitLogRenderer: OutputRenderer {
    public let id          = "git.log"
    public let displayName = "Git Log"
    public let badgeLabel  = "GIT LOG"
    public let priority    = RendererPriority.git

    public func canRender(command: String, output: String) -> Bool {
        let cmd = command.lowercased()
        guard cmd.hasPrefix("git log") else { return false }
        return output.contains("commit ") && output.contains("Author:")
    }

    public func parse(command: String, output: String) -> (any RendererData)? {
        let lines = output.components(separatedBy: "\n")

        var commits: [GitCommit] = []
        var currentHash    = ""
        var currentAuthor  = ""
        var currentDate    = ""
        var currentMessage = ""
        var inMessage      = false

        func flush() {
            guard !currentHash.isEmpty, !currentMessage.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            commits.append(GitCommit(
                hash:    String(currentHash.prefix(7)),
                author:  currentAuthor,
                date:    currentDate,
                message: currentMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
            currentHash = ""; currentAuthor = ""; currentDate = ""; currentMessage = ""; inMessage = false
        }

        for line in lines {
            if line.hasPrefix("commit ") {
                flush()
                currentHash = String(line.dropFirst("commit ".count)).trimmingCharacters(in: .whitespaces)
                inMessage = false
            } else if line.hasPrefix("Author:") {
                let raw = String(line.dropFirst("Author:".count)).trimmingCharacters(in: .whitespaces)
                // Strip email <...>
                if let lt = raw.firstIndex(of: "<") {
                    currentAuthor = String(raw[..<lt]).trimmingCharacters(in: .whitespaces)
                } else {
                    currentAuthor = raw
                }
            } else if line.hasPrefix("Date:") {
                currentDate = String(line.dropFirst("Date:".count)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("    ") && !currentHash.isEmpty {
                inMessage = true
                if currentMessage.isEmpty {
                    currentMessage = String(line.dropFirst(4))
                }
            } else if line.isEmpty && inMessage {
                // blank line after message — keep going
            }
        }
        flush()

        guard !commits.isEmpty else { return nil }
        return GitLogData(commits: commits)
    }

    public func view(for data: any RendererData) -> AnyView {
        guard let data = data as? GitLogData else { return AnyView(EmptyView()) }
        return AnyView(GitLogView(data: data))
    }
}

public struct GitLogData: RendererData {
    public let commits: [GitCommit]
}

public struct GitCommit: Identifiable, Sendable {
    public let id      = UUID()
    public let hash:    String
    public let author:  String
    public let date:    String
    public let message: String
}

struct GitLogView: View {
    let data: GitLogData
    @State private var expanded = Set<UUID>()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("GIT LOG")
                    .font(.custom("JetBrains Mono", size: 8).weight(.bold))
                    .foregroundColor(Color(hex: "#3A4A58"))
                    .kerning(0.4)
                Spacer()
                Text("\(data.commits.count) commit\(data.commits.count == 1 ? "" : "s")")
                    .font(.custom("JetBrains Mono", size: 9))
                    .foregroundColor(Color(hex: "#3A4A58"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().overlay(Color(hex: "#1E1E26"))

            VStack(spacing: 0) {
                ForEach(Array(data.commits.enumerated()), id: \.element.id) { idx, commit in
                    HStack(alignment: .top, spacing: 10) {
                        // Timeline spine
                        VStack(spacing: 0) {
                            Circle()
                                .fill(Color(hex: "#00D4AA"))
                                .frame(width: 8, height: 8)
                                .padding(.top, 4)
                            if idx < data.commits.count - 1 {
                                Rectangle()
                                    .fill(Color(hex: "#1E1E26"))
                                    .frame(width: 1)
                                    .frame(maxHeight: .infinity)
                            }
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(commit.message)
                                .font(.custom("JetBrains Mono", size: 10).weight(.medium))
                                .foregroundColor(Color(hex: "#D8E4F0"))
                                .lineLimit(2)
                            HStack(spacing: 8) {
                                Text(commit.hash)
                                    .font(.custom("JetBrains Mono", size: 9).weight(.bold))
                                    .foregroundColor(Color(hex: "#A78BFA"))
                                Text(commit.author)
                                    .font(.custom("JetBrains Mono", size: 9))
                                    .foregroundColor(Color(hex: "#3A4A58"))
                                    .lineLimit(1)
                                Spacer()
                                Text(shortDate(commit.date))
                                    .font(.custom("JetBrains Mono", size: 9))
                                    .foregroundColor(Color(hex: "#3A4A58"))
                            }
                        }
                        .padding(.bottom, 12)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, idx == 0 ? 10 : 0)
                }
            }
        }
        .background(Color(hex: "#111115"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#1E1E26"), lineWidth: 1))
    }

    private func shortDate(_ raw: String) -> String {
        // "Mon Jan 20 14:30:00 2025 -0800" → "Jan 20"
        let parts = raw.components(separatedBy: " ").filter { !$0.isEmpty }
        guard parts.count >= 3 else { return raw }
        return "\(parts[1]) \(parts[2])"
    }
}
