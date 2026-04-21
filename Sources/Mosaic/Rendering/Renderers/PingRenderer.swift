import SwiftUI
import Charts

@MainActor
public final class PingRenderer: OutputRenderer {
    public let id          = "network.ping"
    public let displayName = "Ping"
    public let badgeLabel  = "PING"
    public let priority    = RendererPriority.network

    public func canRender(command: String, output: String) -> Bool {
        command.lowercased().hasPrefix("ping")
    }

    public func parse(command: String, output: String) -> (any RendererData)? {
        let lines = output.components(separatedBy: "\n")
        guard let firstLine = lines.first(where: { $0.lowercased().hasPrefix("ping") }) else { return nil }
        let pingTokens = firstLine.components(separatedBy: " ")
        let host = pingTokens.count > 1 ? pingTokens[1] : "unknown"
        var packets: [PingPacket] = []
        let timeRegex = try? NSRegularExpression(pattern: #"icmp_seq=(\d+).*?time=([\d.]+)\s*ms"#)
        let timeoutRegex = try? NSRegularExpression(pattern: #"icmp_seq=(\d+).*[Tt]imeout"#)
        for line in lines {
            let ns = line as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let m = timeRegex?.firstMatch(in: line, range: range),
               m.numberOfRanges >= 3,
               let seqRange = Range(m.range(at: 1), in: line),
               let msRange  = Range(m.range(at: 2), in: line),
               let seq = Int(line[seqRange]),
               let ms  = Double(line[msRange]) {
                packets.append(PingPacket(seq: seq, ms: ms, isTimeout: false))
            } else if let m = timeoutRegex?.firstMatch(in: line, range: range),
                      m.numberOfRanges >= 2,
                      let seqRange = Range(m.range(at: 1), in: line),
                      let seq = Int(line[seqRange]) {
                packets.append(PingPacket(seq: seq, ms: nil, isTimeout: true))
            }
        }
        guard !packets.isEmpty else { return nil }
        var minMs: Double? = nil
        var avgMs: Double? = nil
        var maxMs: Double? = nil
        if let summaryLine = lines.first(where: { $0.contains("min/avg/max") }) {
            let summaryRegex = try? NSRegularExpression(pattern: #"=\s*([\d.]+)/([\d.]+)/([\d.]+)"#)
            let ns2 = summaryLine as NSString
            if let m = summaryRegex?.firstMatch(in: summaryLine, range: NSRange(location: 0, length: ns2.length)),
               m.numberOfRanges >= 4,
               let r1 = Range(m.range(at: 1), in: summaryLine),
               let r2 = Range(m.range(at: 2), in: summaryLine),
               let r3 = Range(m.range(at: 3), in: summaryLine) {
                minMs = Double(summaryLine[r1])
                avgMs = Double(summaryLine[r2])
                maxMs = Double(summaryLine[r3])
            }
        }
        return PingData(host: host, packets: packets, minMs: minMs, avgMs: avgMs, maxMs: maxMs)
    }

    public func view(for data: any RendererData) -> AnyView {
        guard let data = data as? PingData else { return AnyView(EmptyView()) }
        return AnyView(PingView(data: data))
    }
}

public struct PingData: RendererData {
    public let host: String
    public let packets: [PingPacket]
    public let minMs: Double?
    public let avgMs: Double?
    public let maxMs: Double?
}

public struct PingPacket: Identifiable, Sendable {
    public let id = UUID()
    public let seq: Int
    public let ms: Double?
    public let isTimeout: Bool
}

private struct PingView: View {
    let data: PingData
    private var successPackets: [PingPacket] { data.packets.filter { !$0.isTimeout } }
    private var lossPercent: Int {
        guard !data.packets.isEmpty else { return 0 }
        return Int(Double(data.packets.filter { $0.isTimeout }.count) / Double(data.packets.count) * 100)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "network").font(.system(size: 11, weight: .semibold)).foregroundColor(Color(hex: "#00D4AA"))
                Text(data.host).font(.custom("JetBrains Mono", size: 11.5).weight(.semibold)).foregroundColor(Color(hex: "#D8E4F0"))
                Spacer()
                Text("\(data.packets.count) packets").font(.custom("JetBrains Mono", size: 9)).foregroundColor(Color(hex: "#3A4A58"))
                if lossPercent > 0 {
                    Text("\(lossPercent)% loss").font(.custom("JetBrains Mono", size: 9).weight(.bold)).foregroundColor(Color(hex: "#FF4D6A"))
                        .padding(.horizontal, 6).padding(.vertical, 2).background(Color(hex: "#FF4D6A").opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }.padding(.horizontal, 12).padding(.vertical, 9)
            Divider().overlay(Color(hex: "#141418"))
            if !successPackets.isEmpty {
                Chart(successPackets, id: \.seq) {
                    LineMark(x: .value("Seq", $0.seq), y: .value("ms", $0.ms ?? 0)).foregroundStyle(Color(hex: "#00D4AA"))
                    AreaMark(x: .value("Seq", $0.seq), y: .value("ms", $0.ms ?? 0))
                        .foregroundStyle(LinearGradient(colors: [Color(hex: "#00D4AA").opacity(0.25), .clear], startPoint: .top, endPoint: .bottom))
                }
                .frame(height: 60).chartXAxis(.hidden).chartYAxis(.hidden).padding(.horizontal, 12).padding(.vertical, 8)
                Divider().overlay(Color(hex: "#141418"))
            }
            HStack(spacing: 0) {
                statCell(label: "MIN", value: data.minMs.map { String(format: "%.1f ms", $0) } ?? "—")
                Rectangle().fill(Color(hex: "#1E1E26")).frame(width: 1, height: 28)
                statCell(label: "AVG", value: data.avgMs.map { String(format: "%.1f ms", $0) } ?? "—")
                Rectangle().fill(Color(hex: "#1E1E26")).frame(width: 1, height: 28)
                statCell(label: "MAX", value: data.maxMs.map { String(format: "%.1f ms", $0) } ?? "—")
            }.padding(.vertical, 9)
        }
        .background(Color(hex: "#111115")).clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#1E1E26"), lineWidth: 1))
    }
    private func statCell(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.custom("JetBrains Mono", size: 8).weight(.bold)).foregroundColor(Color(hex: "#3A4A58"))
            Text(value).font(.custom("JetBrains Mono", size: 11).weight(.semibold)).foregroundColor(Color(hex: "#D8E4F0"))
        }.frame(maxWidth: .infinity)
    }
}
