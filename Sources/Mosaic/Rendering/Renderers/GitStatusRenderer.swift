import SwiftUI

// MARK: - GitStatusRenderer

@MainActor
public final class GitStatusRenderer: OutputRenderer {
    public let id           = "git.status"
    public let displayName  = "Git Status"
    public let badgeLabel   = "GIT STATUS"
    public let priority     = RendererPriority.git

    public func canRender(command: String, output: String) -> Bool {
        let cmd = command.lowercased()
        let triggersOnCommand = cmd.hasPrefix("git status")
        let triggersOnOutput  = (output.contains("On branch") || output.contains("HEAD detached"))
            && (output.contains("Changes") || output.contains("nothing to commit")
                || output.contains("Untracked files"))
        return triggersOnCommand || triggersOnOutput
    }

    public func parse(command: String, output: String) -> (any RendererData)? {
        var branch    = ""
        var ahead     = 0
        var behind    = 0
        var modified:  [String] = []
        var untracked: [String] = []
        var deleted:   [String] = []
        var staged:    [String] = []

        var inStagedSection   = false
        var inUntrackedSection = false

        // Diverged-branch counts span one or two lines depending on terminal width.
        // Search the full output once so wrapping doesn't cause silent zero values.
        if output.contains("diverged"),
           let r = output.range(of: #"have (\d+) and (\d+) different"#, options: .regularExpression) {
            let nums = String(output[r])
                .components(separatedBy: CharacterSet.decimalDigits.inverted)
                .filter { !$0.isEmpty }
            ahead  = Int(nums.first ?? "") ?? 0
            behind = Int(nums.dropFirst().first ?? "") ?? 0
        }

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("On branch ") {
                branch = String(trimmed.dropFirst("On branch ".count))
            } else if trimmed.hasPrefix("HEAD detached at ") {
                branch = String(trimmed.dropFirst("HEAD detached at ".count))
            } else if trimmed.contains("Changes to be committed") {
                inStagedSection   = true
                inUntrackedSection = false
            } else if trimmed.contains("Changes not staged") {
                inStagedSection   = false
                inUntrackedSection = false
            } else if trimmed.contains("Untracked files") {
                inStagedSection   = false
                inUntrackedSection = true
            } else if trimmed.contains("diverged") {
                // diverged counts already extracted above; skip per-line parsing
            } else if trimmed.contains("ahead") {
                // "Your branch is ahead of 'origin/main' by 2 commits."
                let parts = trimmed.components(separatedBy: " ")
                if let idx = parts.firstIndex(of: "by"), idx + 1 < parts.count {
                    ahead = Int(parts[idx + 1]) ?? 0
                }
            } else if trimmed.contains("behind") {
                let parts = trimmed.components(separatedBy: " ")
                if let idx = parts.firstIndex(of: "by"), idx + 1 < parts.count {
                    behind = Int(parts[idx + 1]) ?? 0
                }
            } else if trimmed.hasPrefix("modified:") {
                let file = trimmed.replacingOccurrences(of: "modified:", with: "").trimmingCharacters(in: .whitespaces)
                if inStagedSection { staged.append(file) } else { modified.append(file) }
            } else if trimmed.hasPrefix("deleted:") {
                let file = trimmed.replacingOccurrences(of: "deleted:", with: "").trimmingCharacters(in: .whitespaces)
                if inStagedSection { staged.append(file) } else { deleted.append(file) }
            } else if trimmed.hasPrefix("new file:") {
                let file = trimmed.replacingOccurrences(of: "new file:", with: "").trimmingCharacters(in: .whitespaces)
                staged.append(file)
            } else if inUntrackedSection &&
                      !trimmed.isEmpty &&
                      !trimmed.hasPrefix("#") &&
                      !trimmed.hasPrefix("(") &&
                      trimmed.count > 2 {
                // Untracked file heuristic — only active inside the "Untracked files" section
                // so git advisory lines (e.g. `use "git restore"…`) outside that section are ignored.
                if line.hasPrefix("\t") || (line.hasPrefix("  ") && !trimmed.hasPrefix("-")) {
                    untracked.append(trimmed)
                }
            }
        }

        guard !branch.isEmpty else { return nil }

        return GitStatusData(
            branch:    branch,
            ahead:     ahead,
            behind:    behind,
            modified:  modified,
            untracked: untracked,
            deleted:   deleted,
            staged:    staged
        )
    }

    public func view(for data: any RendererData) -> AnyView {
        guard let data = data as? GitStatusData else { return AnyView(EmptyView()) }
        return AnyView(GitStatusView(data: data))
    }
}

// MARK: - GitStatusData

public struct GitStatusData: RendererData {
    public let branch:    String
    public let ahead:     Int
    public let behind:    Int
    public let modified:  [String]
    public let untracked: [String]
    public let deleted:   [String]
    public let staged:    [String]
}

// MARK: - GitStatusView

struct GitStatusView: View {
    let data: GitStatusData

    var rows: [(status: String, file: String, color: Color)] {
        data.staged.map    { ("S", $0, Color(hex: "#3DFF8F")) } +
        data.modified.map  { ("M", $0, Color(hex: "#FFD060")) } +
        data.untracked.map { ("?", $0, Color(hex: "#4A9EFF")) } +
        data.deleted.map   { ("D", $0, Color(hex: "#FF4D6A")) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Branch header
            HStack(spacing: 8) {
                Text("🌿")
                Text(data.branch)
                    .font(.custom("JetBrains Mono", size: 11.5).weight(.semibold))
                    .foregroundColor(Color(hex: "#D8E4F0"))
                if data.ahead > 0 {
                    Text("↑\(data.ahead)")
                        .font(.custom("JetBrains Mono", size: 9).weight(.bold))
                        .foregroundColor(Color(hex: "#3DFF8F"))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(hex: "#3DFF8F").opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                if data.behind > 0 {
                    Text("↓\(data.behind)")
                        .font(.custom("JetBrains Mono", size: 9).weight(.bold))
                        .foregroundColor(Color(hex: "#FFB020"))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(hex: "#FFB020").opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 9)

            Divider().overlay(Color(hex: "#141418"))

            // File rows
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 8) {
                    Text(row.status)
                        .font(.custom("JetBrains Mono", size: 8.5).weight(.bold))
                        .foregroundColor(row.color)
                        .frame(width: 14)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(row.color.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                    Text(row.file)
                        .font(.custom("JetBrains Mono", size: 10.5))
                        .foregroundColor(Color(hex: "#D8E4F0"))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 7)

                if index < rows.count - 1 {
                    Divider().overlay(Color(hex: "#141418"))
                }
            }
        }
        .background(Color(hex: "#111115"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#1E1E26"), lineWidth: 1))
    }
}
