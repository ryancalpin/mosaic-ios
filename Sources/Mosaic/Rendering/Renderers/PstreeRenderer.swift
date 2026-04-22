import SwiftUI

@MainActor
public final class PstreeRenderer: OutputRenderer {
    public let id          = "data.pstree"
    public let displayName = "Process Tree"
    public let badgeLabel  = "PSTREE"
    public let priority    = RendererPriority.system

    public func canRender(command: String, output: String) -> Bool {
        let cmd = command.lowercased()
        return cmd.hasPrefix("pstree") || (cmd.hasPrefix("ps") && cmd.contains("forest"))
    }

    public func parse(command: String, output: String) -> (any RendererData)? {
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard lines.count >= 2 else { return nil }

        var roots: [PstreeNode] = []
        var stack: [(node: PstreeNode, depth: Int)] = []

        for line in lines {
            let depth = indentDepth(line)
            let name  = parseName(line)
            guard !name.isEmpty else { continue }

            let node = PstreeNode(name: name, depth: depth)

            while !stack.isEmpty && stack.last!.depth >= depth {
                stack.removeLast()
            }

            if stack.isEmpty {
                roots.append(node)
            } else {
                stack.last!.node.children.append(node)
            }
            stack.append((node, depth))
        }

        guard !roots.isEmpty else { return nil }
        return PstreeData(roots: roots)
    }

    private func indentDepth(_ line: String) -> Int {
        var depth = 0
        for c in line {
            if c == " " || c == "\t" || c == "|" || c == "`" || c == "-" || c == "\\" { depth += 1 }
            else { break }
        }
        return depth / 2
    }

    private func parseName(_ line: String) -> String {
        // Strip tree-drawing chars: |, -, \, `, +, spaces, ─, │, ├, └
        let stripped = line.drop(while: { " \t|`-\\+─│├└".contains($0) })
        return String(stripped).trimmingCharacters(in: .whitespaces)
    }

    public func view(for data: any RendererData) -> AnyView {
        guard let data = data as? PstreeData else { return AnyView(EmptyView()) }
        return AnyView(PstreeView(data: data))
    }
}

public struct PstreeData: RendererData {
    public let roots: [PstreeNode]
}

public final class PstreeNode: Identifiable, @unchecked Sendable {
    public let id       = UUID()
    public let name:     String
    public let depth:    Int
    public var children: [PstreeNode] = []

    public init(name: String, depth: Int) {
        self.name = name
        self.depth = depth
    }
}

struct PstreeView: View {
    let data: PstreeData

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("PROCESS TREE")
                    .font(.custom("JetBrains Mono", size: 8).weight(.bold))
                    .foregroundColor(Color(hex: "#3A4A58"))
                    .kerning(0.4)
                Spacer()
                Text("\(data.roots.count) root\(data.roots.count == 1 ? "" : "s")")
                    .font(.custom("JetBrains Mono", size: 9))
                    .foregroundColor(Color(hex: "#3A4A58"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().overlay(Color(hex: "#1E1E26"))

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(data.roots) { root in
                        PstreeNodeView(node: root, isLast: root.id == data.roots.last?.id)
                    }
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

struct PstreeNodeView: View {
    let node:   PstreeNode
    let isLast: Bool
    @State private var collapsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if !node.children.isEmpty { collapsed.toggle() }
            } label: {
                HStack(spacing: 6) {
                    if node.depth > 0 {
                        Color.clear.frame(width: CGFloat(node.depth) * 16)
                        Text(isLast ? "└─" : "├─")
                            .font(.custom("JetBrains Mono", size: 9))
                            .foregroundColor(Color(hex: "#1E1E26"))
                    }

                    Image(systemName: node.children.isEmpty ? "circle.fill" : (collapsed ? "chevron.right.circle.fill" : "chevron.down.circle.fill"))
                        .font(.system(size: node.children.isEmpty ? 5 : 9))
                        .foregroundColor(node.depth == 0 ? Color(hex: "#00D4AA") : (node.children.isEmpty ? Color(hex: "#3A4A58") : Color(hex: "#4A9EFF")))

                    Text(node.name)
                        .font(.custom("JetBrains Mono", size: 10).weight(node.depth == 0 ? .semibold : .regular))
                        .foregroundColor(node.depth == 0 ? Color(hex: "#D8E4F0") : Color(hex: "#8A9AA8"))
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            if !collapsed {
                ForEach(Array(node.children.enumerated()), id: \.element.id) { idx, child in
                    PstreeNodeView(node: child, isLast: idx == node.children.count - 1)
                }
            }
        }
    }
}
