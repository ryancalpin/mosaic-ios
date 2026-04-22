import SwiftUI

@MainActor
public final class RedisMonitorRenderer: OutputRenderer {
    public let id          = "data.redis"
    public let displayName = "Redis Monitor"
    public let badgeLabel  = "REDIS"
    public let priority    = RendererPriority.data

    public func canRender(command: String, output: String) -> Bool {
        let cmd = command.lowercased()
        let isRedis = cmd.hasPrefix("redis-cli") || cmd.hasPrefix("redis cli")
        let looksLikeMonitor = output.contains("OK") && output.range(of: #"\d+\.\d+\s+"GET|SET|DEL|HGET|ZADD"#, options: .regularExpression) != nil
        let looksLikeInfo = output.contains("# Server") || output.contains("redis_version")
        let looksLikeKeys = output.contains("1)") && output.contains("2)")
        return isRedis && (looksLikeMonitor || looksLikeInfo || looksLikeKeys)
    }

    public func parse(command: String, output: String) -> (any RendererData)? {
        if output.contains("# Server") || output.contains("redis_version") {
            return parseInfo(output: output)
        }
        if output.contains("OK") || output.range(of: #"\d+\.\d+"#, options: .regularExpression) != nil {
            return parseMonitor(output: output)
        }
        return nil
    }

    private func parseMonitor(output: String) -> RedisData? {
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        let commandRegex = try? NSRegularExpression(
            pattern: #"^([\d.]+)\s+\[[\d.]+:\d+\]\s+"(\w+)"(?:\s+"([^"]*)")?(?:\s+"([^"]*)")?"#
        )
        var commands: [RedisCommand] = []
        for line in lines {
            let ns = line as NSString
            guard let m = commandRegex?.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
                  m.numberOfRanges >= 3,
                  let tsR  = Range(m.range(at: 1), in: line),
                  let cmdR = Range(m.range(at: 2), in: line) else { continue }
            let ts  = String(line[tsR])
            let cmd = String(line[cmdR])
            let key = m.numberOfRanges >= 4 ? Range(m.range(at: 3), in: line).map { String(line[$0]) } : nil
            let val = m.numberOfRanges >= 5 ? Range(m.range(at: 4), in: line).map { String(line[$0]) } : nil
            commands.append(RedisCommand(timestamp: ts, command: cmd, key: key, value: val))
        }
        guard !commands.isEmpty else { return nil }
        return RedisData(mode: .monitor, commands: commands, infoSections: [])
    }

    private func parseInfo(output: String) -> RedisData? {
        var sections: [RedisInfoSection] = []
        var currentSection = ""
        var currentFields: [RedisInfoField] = []

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                if !currentSection.isEmpty && !currentFields.isEmpty {
                    sections.append(RedisInfoSection(name: currentSection, fields: currentFields))
                }
                currentSection = String(trimmed.dropFirst(2))
                currentFields = []
            } else if trimmed.contains(":") {
                let parts = trimmed.components(separatedBy: ":")
                guard parts.count >= 2 else { continue }
                let key   = parts[0]
                let value = parts[1...].joined(separator: ":")
                currentFields.append(RedisInfoField(key: key, value: value))
            }
        }
        if !currentSection.isEmpty && !currentFields.isEmpty {
            sections.append(RedisInfoSection(name: currentSection, fields: currentFields))
        }
        guard !sections.isEmpty else { return nil }
        return RedisData(mode: .info, commands: [], infoSections: sections)
    }

    public func view(for data: any RendererData) -> AnyView {
        guard let data = data as? RedisData else { return AnyView(EmptyView()) }
        return AnyView(RedisView(data: data))
    }
}

public enum RedisMode: Sendable { case monitor, info }

public struct RedisData: RendererData {
    public let mode:         RedisMode
    public let commands:     [RedisCommand]
    public let infoSections: [RedisInfoSection]
}

public struct RedisCommand: Identifiable, Sendable {
    public let id        = UUID()
    public let timestamp: String
    public let command:   String
    public let key:       String?
    public let value:     String?

    public var commandColor: Color {
        switch command.uppercased() {
        case "SET", "HSET", "ZADD", "LPUSH", "RPUSH": return Color(hex: "#3DFF8F")
        case "GET", "HGET", "ZRANGE", "LRANGE":        return Color(hex: "#4A9EFF")
        case "DEL", "HDEL", "ZREM", "LREM":            return Color(hex: "#FF4D6A")
        case "EXPIRE", "TTL", "PERSIST":               return Color(hex: "#FFD060")
        default:                                        return Color(hex: "#3A4A58")
        }
    }
}

public struct RedisInfoSection: Identifiable, Sendable {
    public let id     = UUID()
    public let name:   String
    public let fields: [RedisInfoField]
}

public struct RedisInfoField: Identifiable, Sendable {
    public let id    = UUID()
    public let key:   String
    public let value: String
}

struct RedisView: View {
    let data: RedisData

    var body: some View {
        switch data.mode {
        case .monitor: RedisMonitorView(commands: data.commands)
        case .info:    RedisInfoView(sections: data.infoSections)
        }
    }
}

struct RedisMonitorView: View {
    let commands: [RedisCommand]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "circle.fill")
                    .font(.system(size: 7))
                    .foregroundColor(Color(hex: "#FF4D6A"))
                Text("REDIS MONITOR")
                    .font(.custom("JetBrains Mono", size: 8).weight(.bold))
                    .foregroundColor(Color(hex: "#3A4A58"))
                    .kerning(0.4)
                Spacer()
                Text("\(commands.count) ops")
                    .font(.custom("JetBrains Mono", size: 9))
                    .foregroundColor(Color(hex: "#3A4A58"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().overlay(Color(hex: "#1E1E26"))

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(commands) { cmd in
                        HStack(spacing: 10) {
                            Text(cmd.timestamp)
                                .font(.custom("JetBrains Mono", size: 8))
                                .foregroundColor(Color(hex: "#3A4A58"))
                                .frame(width: 70, alignment: .leading)
                            Text(cmd.command)
                                .font(.custom("JetBrains Mono", size: 9).weight(.bold))
                                .foregroundColor(cmd.commandColor)
                                .frame(width: 50, alignment: .leading)
                            if let key = cmd.key {
                                Text(key)
                                    .font(.custom("JetBrains Mono", size: 9))
                                    .foregroundColor(Color(hex: "#D8E4F0"))
                                    .lineLimit(1)
                            }
                            if let val = cmd.value {
                                Text(val)
                                    .font(.custom("JetBrains Mono", size: 9))
                                    .foregroundColor(Color(hex: "#3A4A58"))
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        if cmd.id != commands.last?.id {
                            Divider().overlay(Color(hex: "#141418"))
                        }
                    }
                }
            }
            .frame(maxHeight: 320)
        }
        .background(Color(hex: "#111115"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#1E1E26"), lineWidth: 1))
    }
}

struct RedisInfoView: View {
    let sections: [RedisInfoSection]
    @State private var expanded = Set<UUID>()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("REDIS INFO")
                    .font(.custom("JetBrains Mono", size: 8).weight(.bold))
                    .foregroundColor(Color(hex: "#3A4A58"))
                    .kerning(0.4)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().overlay(Color(hex: "#1E1E26"))

            ForEach(sections) { section in
                Button {
                    if expanded.contains(section.id) { expanded.remove(section.id) }
                    else { expanded.insert(section.id) }
                } label: {
                    HStack {
                        Text(section.name)
                            .font(.custom("JetBrains Mono", size: 10).weight(.semibold))
                            .foregroundColor(Color(hex: "#00D4AA"))
                        Spacer()
                        Image(systemName: expanded.contains(section.id) ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9))
                            .foregroundColor(Color(hex: "#3A4A58"))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)

                if expanded.contains(section.id) {
                    ForEach(section.fields) { field in
                        HStack {
                            Text(field.key)
                                .font(.custom("JetBrains Mono", size: 9))
                                .foregroundColor(Color(hex: "#3A4A58"))
                            Spacer()
                            Text(field.value)
                                .font(.custom("JetBrains Mono", size: 9))
                                .foregroundColor(Color(hex: "#D8E4F0"))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                    }
                }

                Divider().overlay(Color(hex: "#1E1E26"))
            }
        }
        .background(Color(hex: "#111115"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#1E1E26"), lineWidth: 1))
    }
}
