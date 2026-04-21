import SwiftUI

// MARK: - FileListRenderer

@MainActor
public final class FileListRenderer: OutputRenderer {
    public let id           = "filesystem.ls"
    public let displayName  = "File List"
    public let badgeLabel   = "FILE LIST"
    public let priority     = RendererPriority.filesystem

    private static let dirPattern  = try? NSRegularExpression(pattern: #"^d"#)
    private static let filePattern = try? NSRegularExpression(pattern: #"^[-]"#)

    public func canRender(command: String, output: String) -> Bool {
        let cmd = command.lowercased()
        // Match only `ls` and `ls <flags/path>` — not lsblk, lsof, lscpu, etc.
        let triggersOnCommand = cmd == "ls" || cmd.hasPrefix("ls ") || cmd.hasPrefix("ls\t")
        // Heuristic fallback: first non-total line looks like a unix permissions string
        let firstDataLine = output.components(separatedBy: "\n")
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.hasPrefix("total") }
        let triggersOnOutput = firstDataLine.map {
            $0.hasPrefix("-") || $0.hasPrefix("d") || $0.hasPrefix("l")
        } ?? false
        return triggersOnCommand || triggersOnOutput
    }

    public func parse(command: String, output: String) -> (any RendererData)? {
        let lines = output.components(separatedBy: "\n")
            .filter { !$0.isEmpty && !$0.hasPrefix("total") }

        var entries: [FileEntry] = []

        for line in lines {
            let parts = line.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: true)
            guard parts.count >= 9 else {
                // Short format (ls without -la) — just names
                let name = line.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    let isDir  = name.hasSuffix("/")
                    let isLink = name.hasSuffix("@")
                    entries.append(FileEntry(
                        name:        name.trimmingCharacters(in: CharacterSet(charactersIn: "/@")),
                        type:        isDir ? .directory : isLink ? .symlink : .file,
                        permissions: nil,
                        size:        nil,
                        modified:    nil
                    ))
                }
                continue
            }

            let permissions = String(parts[0])
            let size        = String(parts[4])
            let month       = String(parts[5])
            let day         = String(parts[6])
            let timeOrYear  = String(parts[7])
            let name        = parts[8...].joined(separator: " ")
            let modified    = "\(month) \(day) \(timeOrYear)"

            let type: FileEntry.FileType
            if permissions.hasPrefix("d")      { type = .directory }
            else if permissions.hasPrefix("l") { type = .symlink   }
            else                               { type = .file      }

            // Skip hidden files (. and ..) but keep user's dotfiles
            if name == "." || name == ".." { continue }

            entries.append(FileEntry(
                name:        name,
                type:        type,
                permissions: permissions,
                size:        size == "0" ? nil : size,
                modified:    modified
            ))
        }

        guard !entries.isEmpty else { return nil }

        // Sort: directories first, then alphabetical
        let sorted = entries.sorted {
            if $0.type == .directory && $1.type != .directory { return true }
            if $0.type != .directory && $1.type == .directory { return false }
            return $0.name.lowercased() < $1.name.lowercased()
        }

        return FileListData(entries: sorted)
    }

    public func view(for data: any RendererData) -> AnyView {
        guard let data = data as? FileListData else { return AnyView(EmptyView()) }
        return AnyView(FileListView(data: data))
    }
}

// MARK: - Data Models

public struct FileListData: RendererData {
    public let entries: [FileEntry]
}

public struct FileEntry: Identifiable, Sendable {
    public let id   = UUID()
    public let name: String
    public let type: FileType
    public let permissions: String?
    public let size: String?
    public let modified: String?

    public enum FileType: Sendable {
        case file, directory, symlink, executable
    }

    public var icon: String {
        switch type {
        case .directory:  return "📁"
        case .symlink:    return "🔗"
        case .executable: return "⚙️"
        case .file:
            let ext = (name as NSString).pathExtension.lowercased()
            switch ext {
            case "md", "txt":                         return "📄"
            case "py", "js", "ts", "swift", "rs":    return "📝"
            case "json", "yaml", "yml", "toml":       return "🗂"
            case "sh", "bash", "zsh":                 return "⚙️"
            case "jpg", "jpeg", "png", "gif", "webp": return "🖼"
            case "zip", "tar", "gz":                  return "📦"
            case "pdf":                               return "📕"
            default:                                  return "📄"
            }
        }
    }

    public var nameColor: Color {
        switch type {
        case .directory:  return Color(hex: "#5AB4FF")
        case .symlink:    return Color(hex: "#A78BFA")
        case .executable: return Color(hex: "#3DFF8F")
        case .file:       return Color(hex: "#D8E4F0")
        }
    }
}

// MARK: - View

struct FileListView: View {
    let data: FileListData

    var body: some View {
        VStack(spacing: 0) {
            // Column header
            HStack {
                Text("NAME")
                Spacer()
                Text("SIZE")
                    .frame(width: 44, alignment: .trailing)
                Text("MODIFIED")
                    .frame(width: 60, alignment: .trailing)
            }
            .font(.custom("JetBrains Mono", size: 7.5).weight(.bold))
            .foregroundColor(Color(hex: "#3A4A58"))
            .padding(.horizontal, 12)
            .frame(height: 22)
            .background(Color(hex: "#1E2830").opacity(0.5))

            Divider().overlay(Color(hex: "#141418"))

            ForEach(Array(data.entries.enumerated()), id: \.element.id) { index, entry in
                HStack(spacing: 6) {
                    Text(entry.icon)
                        .font(.system(size: 11))
                    Text(entry.name)
                        .font(.custom("JetBrains Mono", size: 10.5))
                        .foregroundColor(entry.nameColor)
                        .lineLimit(1)
                    Spacer()
                    if let size = entry.size {
                        Text(size)
                            .font(.custom("JetBrains Mono", size: 9))
                            .foregroundColor(Color(hex: "#3A4A58"))
                            .frame(width: 44, alignment: .trailing)
                    }
                    if let mod = entry.modified {
                        Text(mod)
                            .font(.custom("JetBrains Mono", size: 8.5))
                            .foregroundColor(Color(hex: "#1E2830"))
                            .frame(width: 60, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 28)

                if index < data.entries.count - 1 {
                    Divider().overlay(Color(hex: "#141418"))
                }
            }
        }
        .background(Color(hex: "#111115"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#1E1E26"), lineWidth: 1))
    }
}
