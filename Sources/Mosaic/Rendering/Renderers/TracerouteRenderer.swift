import SwiftUI

@MainActor
public final class TracerouteRenderer: OutputRenderer {
    public let id          = "network.traceroute"
    public let displayName = "Traceroute"
    public let badgeLabel  = "TRACEROUTE"
    public let priority    = RendererPriority.network

    public func canRender(command: String, output: String) -> Bool {
        let cmd = command.lowercased()
        return cmd.hasPrefix("traceroute") || cmd.hasPrefix("tracert") || cmd.hasPrefix("mtr")
    }

    public func parse(command: String, output: String) -> (any RendererData)? {
        let lines = output.components(separatedBy: "\n")
        guard let headerLine = lines.first(where: { $0.lowercased().contains("traceroute to") || $0.lowercased().contains("traceroute ") }) else {
            return nil
        }

        let destination: String
        if let range = headerLine.range(of: #"traceroute to ([^\s,]+)"#, options: [.regularExpression, .caseInsensitive]),
           let hostRange = headerLine.range(of: #"([^\s,]+)"#, options: .regularExpression, range: headerLine.index(range.lowerBound, offsetBy: 14)..<headerLine.endIndex) {
            destination = String(headerLine[hostRange])
        } else {
            destination = command.components(separatedBy: " ").last ?? "unknown"
        }

        let hopRegex = try? NSRegularExpression(pattern: #"^\s*(\d+)\s+(.*)"#)
        let msRegex  = try? NSRegularExpression(pattern: #"([\d.]+)\s*ms"#)

        var hops: [TracerouteHop] = []
        for line in lines {
            let ns = line as NSString
            guard let match = hopRegex?.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
                  match.numberOfRanges >= 3,
                  let numRange  = Range(match.range(at: 1), in: line),
                  let restRange = Range(match.range(at: 2), in: line) else { continue }

            guard let hopNum = Int(line[numRange]) else { continue }
            let rest = String(line[restRange])

            if rest.trimmingCharacters(in: .whitespaces).hasPrefix("* * *") || rest.trimmingCharacters(in: .whitespaces) == "*" {
                hops.append(TracerouteHop(number: hopNum, host: "*", ip: nil, times: [], isTimeout: true))
                continue
            }

            // Extract host/ip
            let parts = rest.trimmingCharacters(in: .whitespaces).components(separatedBy: " ")
            let host = parts.first ?? "*"
            var ip: String? = nil
            if parts.count > 1 {
                let second = parts[1]
                if second.hasPrefix("(") && second.hasSuffix(")") {
                    ip = String(second.dropFirst().dropLast())
                }
            }

            var times: [Double] = []
            let nsRest = rest as NSString
            let msMatches = msRegex?.matches(in: rest, range: NSRange(location: 0, length: nsRest.length)) ?? []
            for m in msMatches {
                if m.numberOfRanges >= 2, let r = Range(m.range(at: 1), in: rest), let ms = Double(rest[r]) {
                    times.append(ms)
                }
            }

            hops.append(TracerouteHop(number: hopNum, host: host, ip: ip, times: times, isTimeout: false))
        }

        guard !hops.isEmpty else { return nil }
        return TracerouteData(destination: destination, hops: hops)
    }

    public func view(for data: any RendererData) -> AnyView {
        guard let data = data as? TracerouteData else { return AnyView(EmptyView()) }
        return AnyView(TracerouteView(data: data))
    }
}

public struct TracerouteData: RendererData {
    public let destination: String
    public let hops: [TracerouteHop]
}

public struct TracerouteHop: Identifiable, Sendable {
    public let id = UUID()
    public let number: Int
    public let host: String
    public let ip: String?
    public let times: [Double]
    public let isTimeout: Bool

    public var avgMs: Double? {
        guard !times.isEmpty else { return nil }
        return times.reduce(0, +) / Double(times.count)
    }

    public var latencyColor: Color {
        guard let ms = avgMs else { return Color(hex: "#3A4A58") }
        if ms < 20  { return Color(hex: "#3DFF8F") }
        if ms < 100 { return Color(hex: "#FFD060") }
        return Color(hex: "#FF4D6A")
    }
}

struct TracerouteView: View {
    let data: TracerouteData

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("TRACEROUTE")
                    .font(.custom("JetBrains Mono", size: 8).weight(.bold))
                    .foregroundColor(Color(hex: "#3A4A58"))
                    .kerning(0.4)
                Spacer()
                Text(data.destination)
                    .font(.custom("JetBrains Mono", size: 10).weight(.semibold))
                    .foregroundColor(Color(hex: "#00D4AA"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().overlay(Color(hex: "#1E1E26"))

            ForEach(data.hops) { hop in
                HopRowView(hop: hop)
                if hop.id != data.hops.last?.id {
                    Divider().overlay(Color(hex: "#141418"))
                }
            }
        }
        .background(Color(hex: "#111115"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#1E1E26"), lineWidth: 1))
    }
}

struct HopRowView: View {
    let hop: TracerouteHop

    var body: some View {
        HStack(spacing: 10) {
            Text(String(format: "%2d", hop.number))
                .font(.custom("JetBrains Mono", size: 10))
                .foregroundColor(Color(hex: "#3A4A58"))
                .frame(width: 20, alignment: .trailing)

            if hop.isTimeout {
                Text("* * *")
                    .font(.custom("JetBrains Mono", size: 10))
                    .foregroundColor(Color(hex: "#3A4A58"))
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(hop.host)
                        .font(.custom("JetBrains Mono", size: 10).weight(.medium))
                        .foregroundColor(Color(hex: "#D8E4F0"))
                    if let ip = hop.ip {
                        Text(ip)
                            .font(.custom("JetBrains Mono", size: 9))
                            .foregroundColor(Color(hex: "#3A4A58"))
                    }
                }
            }

            Spacer()

            if let ms = hop.avgMs {
                Text(String(format: "%.1f ms", ms))
                    .font(.custom("JetBrains Mono", size: 10).weight(.semibold))
                    .foregroundColor(hop.latencyColor)
            } else if !hop.isTimeout {
                Text("—")
                    .font(.custom("JetBrains Mono", size: 10))
                    .foregroundColor(Color(hex: "#3A4A58"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
