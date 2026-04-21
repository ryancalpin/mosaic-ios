import SwiftUI

@MainActor
public final class CronRenderer: OutputRenderer {
    public let id          = "system.cron"
    public let displayName = "Cron Schedule"
    public let badgeLabel  = "CRON"
    public let priority    = RendererPriority.system

    public func canRender(command: String, output: String) -> Bool { command.lowercased().hasPrefix("crontab") }

    public func parse(command: String, output: String) -> (any RendererData)? {
        let lines = output.components(separatedBy: "\n")
        var entries: [CronEntry] = []
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { continue }
            if t.hasPrefix("#") { entries.append(CronEntry(schedule: "", command: String(t.dropFirst()).trimmingCharacters(in: .whitespaces), humanReadable: "", isComment: true, nextRunApprox: nil)); continue }
            let parts = t.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 6 else { continue }
            let fields = Array(parts[0..<5])
            entries.append(CronEntry(schedule: fields.joined(separator: " "), command: parts[5...].joined(separator: " "), humanReadable: humanReadable(fields: fields), isComment: false, nextRunApprox: nil))
        }
        guard !entries.isEmpty else { return nil }
        return CronData(entries: entries)
    }

    private func humanReadable(fields: [String]) -> String {
        guard fields.count == 5 else { return fields.joined(separator: " ") }
        let (min, hour, dom, mon, dow) = (fields[0], fields[1], fields[2], fields[3], fields[4])
        if min == "*" && hour == "*" && dom == "*" && mon == "*" && dow == "*" { return "Every minute" }
        if min.hasPrefix("*/") && hour == "*" && dom == "*" && mon == "*" && dow == "*" { let n = String(min.dropFirst(2)); return "Every \(n) minute\(n == "1" ? "" : "s")" }
        if hour.hasPrefix("*/") && min == "0" && dom == "*" && mon == "*" && dow == "*" { let n = String(hour.dropFirst(2)); return "Every \(n) hour\(n == "1" ? "" : "s")" }
        if min != "*" && hour != "*" && dom == "*" && mon == "*" && dow == "*" { let h = Int(hour) ?? 0; let m = Int(min) ?? 0; let p = h < 12 ? "AM" : "PM"; let h12 = h == 0 ? 12 : h > 12 ? h-12 : h; return String(format: "Daily at %d:%02d %@", h12, m, p) }
        if dow != "*" && dom == "*" { let days = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]; if let d = Int(dow), d < 7 { let h = Int(hour) ?? 0; let m = Int(min) ?? 0; let p = h < 12 ? "AM" : "PM"; let h12 = h == 0 ? 12 : h > 12 ? h-12 : h; return String(format: "Every %@ at %d:%02d %@", days[d], h12, m, p) } }
        if dom != "*" && dow == "*" { let h = Int(hour) ?? 0; let m = Int(min) ?? 0; let p = h < 12 ? "AM" : "PM"; let h12 = h == 0 ? 12 : h > 12 ? h-12 : h; return String(format: "Monthly on day %@ at %d:%02d %@", dom, h12, m, p) }
        return fields.joined(separator: " ")
    }

    public func view(for data: any RendererData) -> AnyView {
        guard let data = data as? CronData else { return AnyView(EmptyView()) }
        return AnyView(CronView(data: data))
    }
}

public struct CronData: RendererData { public let entries: [CronEntry] }
public struct CronEntry: Identifiable, Sendable { public let id = UUID(); public let schedule: String; public let command: String; public let humanReadable: String; public let isComment: Bool; public let nextRunApprox: String? }

private struct CronView: View {
    let data: CronData
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.2.circlepath").font(.system(size: 11, weight: .semibold)).foregroundColor(Color(hex: "#00D4AA"))
                Text("Cron Schedule").font(.custom("JetBrains Mono", size: 11.5).weight(.semibold)).foregroundColor(Color(hex: "#D8E4F0"))
                Spacer()
                let jobs = data.entries.filter { !$0.isComment }.count
                Text("\(jobs) job\(jobs == 1 ? "" : "s")").font(.custom("JetBrains Mono", size: 9)).foregroundColor(Color(hex: "#3A4A58"))
            }.padding(.horizontal, 12).padding(.vertical, 9)
            Divider().overlay(Color(hex: "#141418"))
            ForEach(Array(data.entries.enumerated()), id: \.element.id) { index, entry in
                if entry.isComment { CronCommentRow(entry: entry) } else { CronJobRow(entry: entry) }
                if index < data.entries.count - 1 { Divider().overlay(Color(hex: "#141418")) }
            }
        }
        .background(Color(hex: "#111115")).clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#1E1E26"), lineWidth: 1))
    }
}
private struct CronJobRow: View {
    let entry: CronEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.humanReadable).font(.custom("JetBrains Mono", size: 10.5).weight(.semibold)).foregroundColor(Color(hex: "#00D4AA"))
            Text(entry.schedule).font(.custom("JetBrains Mono", size: 9)).foregroundColor(Color(hex: "#3A4A58"))
            Text(entry.command).font(.custom("JetBrains Mono", size: 10)).foregroundColor(Color(hex: "#D8E4F0")).lineLimit(2).truncationMode(.tail)
        }.padding(.horizontal, 12).padding(.vertical, 9)
    }
}
private struct CronCommentRow: View {
    let entry: CronEntry
    var body: some View { HStack(spacing: 6) { Text("#").font(.custom("JetBrains Mono", size: 10).weight(.bold)).foregroundColor(Color(hex: "#3A4A58")); Text(entry.command).font(.custom("JetBrains Mono", size: 10)).foregroundColor(Color(hex: "#3A4A58")); Spacer() }.padding(.horizontal, 12).padding(.vertical, 7) }
}
