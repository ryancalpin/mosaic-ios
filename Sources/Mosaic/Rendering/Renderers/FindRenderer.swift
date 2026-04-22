import SwiftUI

@MainActor
public final class FindRenderer: OutputRenderer {
    public let id          = "file.find"
    public let displayName = "Find Tree"
    public let badgeLabel  = "FIND"
    public let priority    = RendererPriority.filesystem

    public func canRender(command: String, output: String) -> Bool {
        command.lowercased().hasPrefix("find ")
    }

    public func parse(command: String, output: String) -> (any RendererData)? {
        let rawLines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard rawLines.count >= 2 else { return nil }

        // Build tree from paths
        let root = FindNode(name: ".", isDirectory: true, depth: 0)
        for path in rawLines {
            let clean = path.hasPrefix("./") ? String(path.dropFirst(2)) : path
            guard !clean.isEmpty && clean != "." else { continue }
            let parts = clean.components(separatedBy: "/")
            insert(parts: parts, into: root, depth: 0)
        }

        return FindData(root: root, totalCount: rawLines.count)
    }

    private func insert(parts: [String], into node: FindNode, depth: Int) {
        guard !parts.isEmpty else { return }
        let name = parts[0]
        let remaining = Array(parts.dropFirst())
        if let existing = node.children.first(where: { $0.name == name }) {
            if !remaining.isEmpty { insert(parts: remaining, into: existing, depth: depth + 1) }
        } else {
            let child = FindNode(name: name, isDirectory: !remaining.isEmpty, depth: depth + 1)
            node.children.append(child)
            if !remaining.isEmpty { insert(parts: remaining, into: child, depth: depth + 1) }
        }
    }

    public func view(for data: any RendererData) -> AnyView {
        guard let data = data as? FindData else { return AnyView(EmptyView()) }
        return AnyView(FindView(data: data))
    }
}

public struct FindData: RendererData {
    public let root:       FindNode
    public let totalCount: Int
}

public final class FindNode: Identifiable, @unchecked Sendable {
    public let id         = UUID()
    public let name:       String
    public let isDirectory: Bool
    public let depth:      Int
    public var children:   [FindNode] = []

    public init(name: String, isDirectory: Bool, depth: Int) {
        self.name = name
        self.isDirectory = isDirectory
        self.depth = depth
    }
}

struct FindView: View {
    let data: FindData

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("FIND")
                    .font(.custom("JetBrains Mono", size: 8).weight(.bold))
                    .foregroundColor(Color(hex: "#3A4A58"))
                    .kerning(0.4)
                Spacer()
                Text("\(data.totalCount) results")
                    .font(.custom("JetBrains Mono", size: 9))
                    .foregroundColor(Color(hex: "#3A4A58"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().overlay(Color(hex: "#1E1E26"))

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    FindNodeView(node: data.root, isLast: true)
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 360)
        }
        .background(Color(hex: "#111115"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#1E1E26"), lineWidth: 1))
    }
}

struct FindNodeView: View {
    let node:   FindNode
    let isLast: Bool
    @State private var collapsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if node.isDirectory && !node.children.isEmpty { collapsed.toggle() }
            } label: {
                HStack(spacing: 4) {
                    // Indent
                    if node.depth > 0 {
                        Color.clear.frame(width: CGFloat(node.depth) * 16)
                    }

                    // Tree branch glyph
                    if node.depth > 0 {
                        Text(isLast ? "└─" : "├─")
                            .font(.custom("JetBrains Mono", size: 9))
                            .foregroundColor(Color(hex: "#1E1E26"))
                    }

                    // Icon
                    if node.isDirectory {
                        Image(systemName: collapsed ? "folder" : "folder.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#4A9EFF"))
                    } else {
                        Image(systemName: fileIcon(node.name))
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#3A4A58"))
                    }

                    Text(node.name)
                        .font(.custom("JetBrains Mono", size: 10))
                        .foregroundColor(node.isDirectory ? Color(hex: "#D8E4F0") : Color(hex: "#8A9AA8"))
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            if !collapsed {
                ForEach(Array(node.children.enumerated()), id: \.element.id) { idx, child in
                    FindNodeView(node: child, isLast: idx == node.children.count - 1)
                }
            }
        }
    }

    private func fileIcon(_ name: String) -> String {
        let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
        switch ext {
        case "swift":        return "swift"
        case "json":         return "curlybraces"
        case "md":           return "doc.richtext"
        case "sh", "bash":   return "terminal"
        case "png", "jpg", "jpeg", "gif", "svg": return "photo"
        case "pdf":          return "doc.fill"
        default:             return "doc"
        }
    }
}
