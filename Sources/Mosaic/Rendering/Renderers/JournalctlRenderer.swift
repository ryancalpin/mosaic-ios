import SwiftUI

@MainActor
public final class JournalctlRenderer: OutputRenderer {
    public let id          = "infra.journalctl"
    public let displayName = "Journal Logs"
    public let badgeLabel  = "JOURNAL"
    public let priority    = RendererPriority.system

    public func canRender(command: String, output: String) -> Bool {
        let cmd = command.lowercased()
        return cmd.hasPrefix("journalctl")
    }

    public func parse(command: String, output: String) -> (any RendererData)? {
        let rawLines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard rawLines.count >= 2 else { return nil }

        // Two common journalctl formats:
        // 1. Short: "Jan 15 12:34:56 hostname svcname[pid]: message"
        // 2. JSON output (--output=json): each line is JSON
        let ansiRegex = try? NSRegularExpression(pattern: #"\x1B\[[0-9;]*m"#)
        func stripANSI(_ s: String) -> String {
            let ns = s as NSString
            return ansiRegex?.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: ns.length), withTemplate: "") ?? s
        }

        // Short format regex: "Mon DD HH:MM:SS hostname svc[pid]: msg"
        let shortRegex = try? NSRegularExpression(
            pattern: #"^([A-Z][a-z]{2}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})\s+(\S+)\s+(\S+?)(?:\[(\d+)\])?:\s+(.*)$"#
        )

        var entries: [JournalEntry] = []
        var unit = ""

        for line in rawLines {
            let clean = stripANSI(line)
            if clean.hasPrefix("--") { continue } // separator lines

            let ns = clean as NSString
            if let m = shortRegex?.firstMatch(in: clean, range: NSRange(location: 0, length: ns.length)),
               m.numberOfRanges >= 6,
               let tsR      = Range(m.range(at: 1), in: clean),
               let svcR     = Range(m.range(at: 3), in: clean),
               let msgR     = Range(m.range(at: 5), in: clean) {

                let ts  = String(clean[tsR])
                let svc = String(clean[svcR])
                let pid = m.numberOfRanges >= 5 ? Range(m.range(at: 4), in: clean).map { String(clean[$0]) } : nil
                let msg = String(clean[msgR])

                if unit.isEmpty { unit = svc }
                let level = detectLevel(msg)
                entries.append(JournalEntry(timestamp: ts, service: svc, pid: pid, message: msg, level: level))
            } else if !clean.isEmpty {
                // Non-matching line — treat as continuation
                entries.append(JournalEntry(timestamp: nil, service: "", pid: nil, message: clean, level: .info))
            }
        }

        guard !entries.isEmpty else { return nil }
        return JournalData(unit: unit.isEmpty ? "journal" : unit, entries: entries)
    }

    private func detectLevel(_ msg: String) -> LogLevel {
        let lower = msg.lowercased()
        if lower.contains("error") || lower.contains("fail") || lower.contains("fatal") { return .error }
        if lower.contains("warn") || lower.contains("deprecated")                        { return .warn }
        if lower.contains("debug") || lower.contains("trace")                            { return .debug }
        return .info
    }

    public func view(for data: any RendererData) -> AnyView {
        guard let data = data as? JournalData else { return AnyView(EmptyView()) }
        return AnyView(JournalView(data: data))
    }
}

public struct JournalData: RendererData {
    public let unit:    String
    public let entries: [JournalEntry]
}

public struct JournalEntry: Identifiable, Sendable {
    public let id        = UUID()
    public let timestamp: String?
    public let service:   String
    public let pid:       String?
    public let message:   String
    public let level:     LogLevel
}

struct JournalView: View {
    let data: JournalData
    @State private var filterLevel: LogLevel? = nil

    private var displayed: [JournalEntry] {
        guard let f = filterLevel else { return data.entries }
        return data.entries.filter { $0.level == f }
    }
    private var errorCount: Int { data.entries.filter { $0.level == .error }.count }
    private var warnCount:  Int { data.entries.filter { $0.level == .warn  }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#3A4A58"))
                Text(data.unit)
                    .font(.custom("JetBrains Mono", size: 10).weight(.semibold))
                    .foregroundColor(Color(hex: "#D8E4F0"))
                Spacer()
                if errorCount > 0 {
                    Button { filterLevel = filterLevel == .error ? nil : .error } label: {
                        Text("\(errorCount) ERR")
                            .font(.custom("JetBrains Mono", size: 8).weight(.bold))
                            .foregroundColor(Color(hex: "#FF4D6A"))
                    }
                    .buttonStyle(.plain)
                }
                if warnCount > 0 {
                    Button { filterLevel = filterLevel == .warn ? nil : .warn } label: {
                        Text("\(warnCount) WARN")
                            .font(.custom("JetBrains Mono", size: 8).weight(.bold))
                            .foregroundColor(Color(hex: "#FFD060"))
                    }
                    .buttonStyle(.plain)
                }
                Text("JOURNAL")
                    .font(.custom("JetBrains Mono", size: 8).weight(.bold))
                    .foregroundColor(Color(hex: "#3A4A58"))
                    .kerning(0.4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().overlay(Color(hex: "#1E1E26"))

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(displayed) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Rectangle()
                                .fill(entry.level.color.opacity(0.5))
                                .frame(width: 2)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    if let ts = entry.timestamp {
                                        Text(ts)
                                            .font(.custom("JetBrains Mono", size: 8))
                                            .foregroundColor(Color(hex: "#3A4A58"))
                                    }
                                    if !entry.service.isEmpty {
                                        Text(entry.service)
                                            .font(.custom("JetBrains Mono", size: 8).weight(.bold))
                                            .foregroundColor(Color(hex: "#4A9EFF"))
                                        if let pid = entry.pid {
                                            Text("[\(pid)]")
                                                .font(.custom("JetBrains Mono", size: 8))
                                                .foregroundColor(Color(hex: "#3A4A58"))
                                        }
                                    }
                                }
                                Text(entry.message)
                                    .font(.custom("JetBrains Mono", size: 10))
                                    .foregroundColor(entry.level.color)
                                    .lineLimit(4)
                            }
                            .padding(.vertical, 5)

                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        if entry.id != displayed.last?.id {
                            Divider().overlay(Color(hex: "#141418"))
                        }
                    }
                }
            }
            .frame(maxHeight: 380)
        }
        .background(Color(hex: "#111115"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#1E1E26"), lineWidth: 1))
    }
}
