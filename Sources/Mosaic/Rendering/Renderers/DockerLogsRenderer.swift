import SwiftUI

@MainActor
public final class DockerLogsRenderer: OutputRenderer {
    public let id          = "docker.logs"
    public let displayName = "Docker Logs"
    public let badgeLabel  = "DOCKER LOGS"
    public let priority    = RendererPriority.docker

    public func canRender(command: String, output: String) -> Bool {
        let cmd = command.lowercased()
        return cmd.hasPrefix("docker logs") || cmd.hasPrefix("docker container logs")
    }

    public func parse(command: String, output: String) -> (any RendererData)? {
        let rawLines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard rawLines.count >= 2 else { return nil }

        let containerName = extractContainerName(from: command)

        // Detect timestamp format: ISO8601 "2024-01-01T12:00:00.000000000Z text"
        let tsRegex = try? NSRegularExpression(
            pattern: #"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z)\s+(.*)"#
        )
        let ansiRegex = try? NSRegularExpression(pattern: #"\x1B\[[0-9;]*m"#)

        func stripANSI(_ s: String) -> String {
            let ns = s as NSString
            return ansiRegex?.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: ns.length), withTemplate: "") ?? s
        }

        var entries: [DockerLogEntry] = []
        for line in rawLines {
            let clean = stripANSI(line)
            let ns = clean as NSString
            let level = detectLevel(clean)
            if let m = tsRegex?.firstMatch(in: clean, range: NSRange(location: 0, length: ns.length)),
               m.numberOfRanges >= 3,
               let tsR   = Range(m.range(at: 1), in: clean),
               let textR = Range(m.range(at: 2), in: clean) {
                let ts   = String(clean[tsR])
                let text = String(clean[textR])
                entries.append(DockerLogEntry(timestamp: shortTimestamp(ts), message: text, level: level))
            } else {
                entries.append(DockerLogEntry(timestamp: nil, message: clean, level: level))
            }
        }

        guard !entries.isEmpty else { return nil }
        return DockerLogsData(containerName: containerName, entries: entries)
    }

    private func extractContainerName(from command: String) -> String {
        let parts = command.components(separatedBy: " ").filter { !$0.isEmpty }
        // "docker logs [flags...] <name>"
        return parts.last ?? "container"
    }

    private func detectLevel(_ line: String) -> LogLevel {
        let lower = line.lowercased()
        if lower.contains("error") || lower.contains("fatal") || lower.contains("panic") { return .error }
        if lower.contains("warn")                                                          { return .warn }
        if lower.contains("debug") || lower.contains("trace")                             { return .debug }
        return .info
    }

    private func shortTimestamp(_ iso: String) -> String {
        // "2024-01-15T12:34:56.000Z" → "12:34:56"
        let parts = iso.components(separatedBy: "T")
        guard parts.count == 2 else { return iso }
        return String(parts[1].prefix(8))
    }

    public func view(for data: any RendererData) -> AnyView {
        guard let data = data as? DockerLogsData else { return AnyView(EmptyView()) }
        return AnyView(DockerLogsView(data: data))
    }
}

public enum LogLevel: Sendable {
    case info, warn, error, debug

    public var color: Color {
        switch self {
        case .info:  return Color(hex: "#D8E4F0")
        case .warn:  return Color(hex: "#FFD060")
        case .error: return Color(hex: "#FF4D6A")
        case .debug: return Color(hex: "#3A4A58")
        }
    }
    public var badge: String {
        switch self {
        case .info:  return "INFO"
        case .warn:  return "WARN"
        case .error: return "ERR"
        case .debug: return "DBG"
        }
    }
}

public struct DockerLogsData: RendererData {
    public let containerName: String
    public let entries: [DockerLogEntry]
}

public struct DockerLogEntry: Identifiable, Sendable {
    public let id        = UUID()
    public let timestamp: String?
    public let message:   String
    public let level:     LogLevel
}

struct DockerLogsView: View {
    let data: DockerLogsData
    @State private var filterLevel: LogLevel? = nil

    private var displayed: [DockerLogEntry] {
        guard let f = filterLevel else { return data.entries }
        return data.entries.filter { $0.level == f }
    }

    private var errorCount: Int  { data.entries.filter { $0.level == .error }.count }
    private var warnCount:  Int  { data.entries.filter { $0.level == .warn  }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#4A9EFF"))
                Text(data.containerName)
                    .font(.custom("JetBrains Mono", size: 10).weight(.semibold))
                    .foregroundColor(Color(hex: "#D8E4F0"))
                Spacer()
                if errorCount > 0 {
                    Button { filterLevel = filterLevel == .error ? nil : .error } label: {
                        Text("\(errorCount) ERR")
                            .font(.custom("JetBrains Mono", size: 8).weight(.bold))
                            .foregroundColor(Color(hex: "#FF4D6A"))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(filterLevel == .error ? Color(hex: "#FF4D6A").opacity(0.15) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
                if warnCount > 0 {
                    Button { filterLevel = filterLevel == .warn ? nil : .warn } label: {
                        Text("\(warnCount) WARN")
                            .font(.custom("JetBrains Mono", size: 8).weight(.bold))
                            .foregroundColor(Color(hex: "#FFD060"))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(filterLevel == .warn ? Color(hex: "#FFD060").opacity(0.15) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
                Text("\(data.entries.count)")
                    .font(.custom("JetBrains Mono", size: 9))
                    .foregroundColor(Color(hex: "#3A4A58"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().overlay(Color(hex: "#1E1E26"))

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(displayed) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            if let ts = entry.timestamp {
                                Text(ts)
                                    .font(.custom("JetBrains Mono", size: 8))
                                    .foregroundColor(Color(hex: "#3A4A58"))
                                    .frame(width: 52, alignment: .leading)
                            }
                            Text(entry.level.badge)
                                .font(.custom("JetBrains Mono", size: 7).weight(.bold))
                                .foregroundColor(entry.level.color)
                                .frame(width: 26, alignment: .leading)
                            Text(entry.message)
                                .font(.custom("JetBrains Mono", size: 10))
                                .foregroundColor(entry.level.color)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(3)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        if entry.id != displayed.last?.id {
                            Divider().overlay(Color(hex: "#141418"))
                        }
                    }
                }
            }
            .frame(maxHeight: 360)
        }
        .background(Color(hex: "#111115"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#1E1E26"), lineWidth: 1))
    }
}
