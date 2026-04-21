import SwiftUI

@MainActor
public final class GitDiffRenderer: OutputRenderer {
    public let id          = "git.diff"
    public let displayName = "Git Diff"
    public let badgeLabel  = "GIT DIFF"
    public let priority    = RendererPriority.git

    public func canRender(command: String, output: String) -> Bool {
        command.lowercased().hasPrefix("git diff") || output.hasPrefix("diff --git")
    }

    public func parse(command: String, output: String) -> (any RendererData)? {
        let fileChunks = output.components(separatedBy: "\ndiff --git ").enumerated().map { idx, chunk in
            idx == 0 && chunk.hasPrefix("diff --git ") ? String(chunk.dropFirst("diff --git ".count)) : chunk
        }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !fileChunks.isEmpty else { return nil }
        var files: [DiffFile] = []
        for chunk in fileChunks {
            let chunkLines = chunk.components(separatedBy: "\n")
            guard !chunkLines.isEmpty else { continue }
            let pathParts = chunkLines[0].components(separatedBy: " b/")
            let oldPath = pathParts.first.map { $0.hasPrefix("a/") ? String($0.dropFirst(2)) : $0 } ?? chunkLines[0]
            let newPath = pathParts.count > 1 ? pathParts[1] : oldPath
            var hunks: [DiffHunk] = []; var currentHeader = ""; var currentLines: [DiffLine] = []
            for line in chunkLines[1...] {
                if line.hasPrefix("@@") { if !currentLines.isEmpty || !currentHeader.isEmpty { hunks.append(DiffHunk(header: currentHeader, lines: currentLines)) }; currentHeader = line; currentLines = [] }
                else if line.hasPrefix("+") && !line.hasPrefix("+++") { currentLines.append(DiffLine(type: .added,   content: String(line.dropFirst()))) }
                else if line.hasPrefix("-") && !line.hasPrefix("---") { currentLines.append(DiffLine(type: .removed, content: String(line.dropFirst()))) }
                else if line.hasPrefix(" ")                            { currentLines.append(DiffLine(type: .context, content: String(line.dropFirst()))) }
            }
            if !currentLines.isEmpty || !currentHeader.isEmpty { hunks.append(DiffHunk(header: currentHeader, lines: currentLines)) }
            if !hunks.isEmpty { files.append(DiffFile(oldPath: oldPath, newPath: newPath, hunks: hunks)) }
        }
        guard !files.isEmpty else { return nil }
        return GitDiffData(files: files)
    }

    public func view(for data: any RendererData) -> AnyView {
        guard let data = data as? GitDiffData else { return AnyView(EmptyView()) }
        return AnyView(GitDiffView(data: data))
    }
}

public struct GitDiffData: RendererData { public let files: [DiffFile] }
public struct DiffFile: Identifiable, Sendable {
    public let id = UUID(); public let oldPath: String; public let newPath: String; public let hunks: [DiffHunk]
    public var addedCount: Int   { hunks.flatMap(\.lines).filter { $0.type == .added   }.count }
    public var removedCount: Int { hunks.flatMap(\.lines).filter { $0.type == .removed }.count }
    public var displayName: String { newPath == oldPath ? newPath : "\(oldPath) → \(newPath)" }
}
public struct DiffHunk: Identifiable, Sendable { public let id = UUID(); public let header: String; public let lines: [DiffLine] }
public struct DiffLine: Identifiable, Sendable { public let id = UUID(); public let type: DiffLineType; public let content: String }
public enum DiffLineType: Sendable { case added, removed, context }

private struct GitDiffView: View {
    let data: GitDiffData
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.left.arrow.right").font(.system(size: 11, weight: .semibold)).foregroundColor(Color(hex: "#00D4AA"))
                Text("Git Diff").font(.custom("JetBrains Mono", size: 11.5).weight(.semibold)).foregroundColor(Color(hex: "#D8E4F0"))
                Spacer()
                Text("\(data.files.count) file\(data.files.count == 1 ? "" : "s")").font(.custom("JetBrains Mono", size: 9)).foregroundColor(Color(hex: "#3A4A58"))
            }.padding(.horizontal, 12).padding(.vertical, 9)
            Divider().overlay(Color(hex: "#141418"))
            ForEach(data.files) { file in DiffFileView(file: file); Divider().overlay(Color(hex: "#141418")) }
        }
        .background(Color(hex: "#111115")).clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#1E1E26"), lineWidth: 1))
    }
}
private struct DiffFileView: View {
    let file: DiffFile; @State private var isExpanded = true
    var body: some View {
        VStack(spacing: 0) {
            Button { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundColor(Color(hex: "#3A4A58"))
                    Text(file.displayName).font(.custom("JetBrains Mono", size: 10.5)).foregroundColor(Color(hex: "#D8E4F0")).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    if file.addedCount   > 0 { Text("+\(file.addedCount)").font(.custom("JetBrains Mono", size: 8.5).weight(.bold)).foregroundColor(Color(hex: "#3DFF8F")).padding(.horizontal, 5).padding(.vertical, 2).background(Color(hex: "#3DFF8F").opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 3)) }
                    if file.removedCount > 0 { Text("-\(file.removedCount)").font(.custom("JetBrains Mono", size: 8.5).weight(.bold)).foregroundColor(Color(hex: "#FF4D6A")).padding(.horizontal, 5).padding(.vertical, 2).background(Color(hex: "#FF4D6A").opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 3)) }
                }.padding(.horizontal, 12).padding(.vertical, 8)
            }.buttonStyle(.plain)
            if isExpanded { ForEach(file.hunks) { hunk in DiffHunkView(hunk: hunk) } }
        }
    }
}
private struct DiffHunkView: View {
    let hunk: DiffHunk
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(hunk.header).font(.custom("JetBrains Mono", size: 9)).foregroundColor(Color(hex: "#3A4A58")).padding(.horizontal, 12).padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading).background(Color(hex: "#17171C"))
            ForEach(hunk.lines) { line in DiffLineView(line: line) }
        }
    }
}
private struct DiffLineView: View {
    let line: DiffLine
    private var prefix: String { line.type == .added ? "+" : line.type == .removed ? "-" : " " }
    private var textColor: Color { line.type == .added ? Color(hex: "#3DFF8F") : line.type == .removed ? Color(hex: "#FF4D6A") : Color(hex: "#D8E4F0").opacity(0.6) }
    private var bgColor: Color   { line.type == .added ? Color(hex: "#3DFF8F").opacity(0.06) : line.type == .removed ? Color(hex: "#FF4D6A").opacity(0.06) : .clear }
    var body: some View {
        HStack(spacing: 6) {
            Text(prefix).font(.custom("JetBrains Mono", size: 10)).foregroundColor(textColor).frame(width: 10)
            Text(line.content).font(.custom("JetBrains Mono", size: 10)).foregroundColor(textColor).lineLimit(3).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.horizontal, 12).padding(.vertical, 2).background(bgColor)
    }
}
