import SwiftUI

@MainActor
public final class DuRenderer: OutputRenderer {
    public let id          = "file.du"
    public let displayName = "Disk Usage"
    public let badgeLabel  = "DU"
    public let priority    = RendererPriority.filesystem

    public func canRender(command: String, output: String) -> Bool {
        let cmd = command.lowercased()
        return cmd.hasPrefix("du ")
    }

    public func parse(command: String, output: String) -> (any RendererData)? {
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard lines.count >= 2 else { return nil }

        var entries: [DuEntry] = []
        for line in lines {
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let sizeStr = parts[0].trimmingCharacters(in: .whitespaces)
            let path    = parts[1].trimmingCharacters(in: .whitespaces)
            guard let bytes = parseSize(sizeStr) else { continue }
            let name = path == "." ? "." : (path.split(separator: "/").last.map(String.init) ?? path)
            entries.append(DuEntry(path: path, name: name, bytes: bytes, displaySize: sizeStr))
        }

        guard !entries.isEmpty else { return nil }

        // Sort descending, keep top 30
        entries.sort { $0.bytes > $1.bytes }
        let top = Array(entries.prefix(30))
        let maxBytes = top.first?.bytes ?? 1

        return DuData(entries: top, maxBytes: maxBytes)
    }

    private func parseSize(_ s: String) -> Int64? {
        // du output can be: "1.2G", "512M", "1024K", "2048" (blocks), etc.
        let lower = s.lowercased()
        let numPart = lower.prefix(while: { $0.isNumber || $0 == "." })
        guard let value = Double(numPart) else { return nil }
        if lower.hasSuffix("g") || lower.hasSuffix("gb") { return Int64(value * 1_000_000_000) }
        if lower.hasSuffix("m") || lower.hasSuffix("mb") { return Int64(value * 1_000_000) }
        if lower.hasSuffix("k") || lower.hasSuffix("kb") { return Int64(value * 1_000) }
        // Plain number = 512-byte blocks (BSD/macOS du default)
        return Int64(value * 512)
    }

    public func view(for data: any RendererData) -> AnyView {
        guard let data = data as? DuData else { return AnyView(EmptyView()) }
        return AnyView(DuView(data: data))
    }
}

public struct DuData: RendererData {
    public let entries:  [DuEntry]
    public let maxBytes: Int64
}

public struct DuEntry: Identifiable, Sendable {
    public let id          = UUID()
    public let path:        String
    public let name:        String
    public let bytes:       Int64
    public let displaySize: String
}

struct DuView: View {
    let data: DuData

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("DISK USAGE")
                    .font(.custom("JetBrains Mono", size: 8).weight(.bold))
                    .foregroundColor(Color(hex: "#3A4A58"))
                    .kerning(0.4)
                Spacer()
                Text("\(data.entries.count) items")
                    .font(.custom("JetBrains Mono", size: 9))
                    .foregroundColor(Color(hex: "#3A4A58"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().overlay(Color(hex: "#1E1E26"))

            VStack(spacing: 0) {
                ForEach(data.entries) { entry in
                    DuRowView(entry: entry, maxBytes: data.maxBytes)
                    if entry.id != data.entries.last?.id {
                        Divider().overlay(Color(hex: "#141418"))
                    }
                }
            }
        }
        .background(Color(hex: "#111115"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#1E1E26"), lineWidth: 1))
    }
}

struct DuRowView: View {
    let entry:    DuEntry
    let maxBytes: Int64

    private var fraction: Double {
        guard maxBytes > 0 else { return 0 }
        return min(1.0, Double(entry.bytes) / Double(maxBytes))
    }

    private var barColor: Color {
        if fraction > 0.75 { return Color(hex: "#FF4D6A") }
        if fraction > 0.4  { return Color(hex: "#FFD060") }
        return Color(hex: "#00D4AA")
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "#4A9EFF").opacity(0.7))
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(entry.name)
                        .font(.custom("JetBrains Mono", size: 10).weight(.medium))
                        .foregroundColor(Color(hex: "#D8E4F0"))
                        .lineLimit(1)
                    Spacer()
                    Text(entry.displaySize)
                        .font(.custom("JetBrains Mono", size: 9).weight(.bold))
                        .foregroundColor(barColor)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: "#1E1E26"))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(barColor)
                            .frame(width: geo.size.width * fraction, height: 4)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
