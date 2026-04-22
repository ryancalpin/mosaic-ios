import SwiftUI

@MainActor
public final class NmapRenderer: OutputRenderer {
    public let id          = "network.nmap"
    public let displayName = "Nmap Scan"
    public let badgeLabel  = "NMAP"
    public let priority    = RendererPriority.network

    public func canRender(command: String, output: String) -> Bool {
        let cmd = command.lowercased()
        return cmd.hasPrefix("nmap") || output.contains("Nmap scan report")
    }

    public func parse(command: String, output: String) -> (any RendererData)? {
        let lines = output.components(separatedBy: "\n")
        guard output.contains("Nmap scan report") else { return nil }

        var hosts: [NmapHost] = []
        var currentHost: String = ""
        var currentPorts: [NmapPort] = []
        var currentLatency: String? = nil

        let portRegex  = try? NSRegularExpression(pattern: #"^(\d+)/(tcp|udp)\s+(open|closed|filtered)\s+(\S+)(?:\s+(.*))?$"#)
        let latRegex   = try? NSRegularExpression(pattern: #"Host is up \(([\d.]+)s latency\)"#)

        func flushHost() {
            guard !currentHost.isEmpty else { return }
            hosts.append(NmapHost(host: currentHost, ports: currentPorts, latency: currentLatency))
            currentPorts = []
            currentLatency = nil
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Nmap scan report for ") {
                flushHost()
                currentHost = String(trimmed.dropFirst("Nmap scan report for ".count))
            } else if let m = latRegex?.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                      m.numberOfRanges >= 2,
                      let r = Range(m.range(at: 1), in: trimmed) {
                currentLatency = String(trimmed[r]) + "s"
            } else {
                let ns = trimmed as NSString
                if let m = portRegex?.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)),
                   m.numberOfRanges >= 5,
                   let portR    = Range(m.range(at: 1), in: trimmed),
                   let protoR   = Range(m.range(at: 2), in: trimmed),
                   let stateR   = Range(m.range(at: 3), in: trimmed),
                   let serviceR = Range(m.range(at: 4), in: trimmed) {
                    let portNum  = Int(trimmed[portR]) ?? 0
                    let proto    = String(trimmed[protoR])
                    let state    = String(trimmed[stateR])
                    let service  = String(trimmed[serviceR])
                    let version  = m.numberOfRanges >= 6 ? Range(m.range(at: 5), in: trimmed).map { String(trimmed[$0]) } : nil
                    currentPorts.append(NmapPort(port: portNum, proto: proto, state: state, service: service, version: version))
                }
            }
        }
        flushHost()

        guard !hosts.isEmpty else { return nil }
        return NmapData(hosts: hosts)
    }

    public func view(for data: any RendererData) -> AnyView {
        guard let data = data as? NmapData else { return AnyView(EmptyView()) }
        return AnyView(NmapView(data: data))
    }
}

public struct NmapData: RendererData {
    public let hosts: [NmapHost]
}

public struct NmapHost: Identifiable, Sendable {
    public let id      = UUID()
    public let host:    String
    public let ports:   [NmapPort]
    public let latency: String?
}

public struct NmapPort: Identifiable, Sendable {
    public let id      = UUID()
    public let port:    Int
    public let proto:   String
    public let state:   String
    public let service: String
    public let version: String?

    public var isOpen: Bool { state == "open" }
}

struct NmapView: View {
    let data: NmapData

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("NMAP SCAN")
                    .font(.custom("JetBrains Mono", size: 8).weight(.bold))
                    .foregroundColor(Color(hex: "#3A4A58"))
                    .kerning(0.4)
                Spacer()
                Text("\(data.hosts.count) host\(data.hosts.count == 1 ? "" : "s")")
                    .font(.custom("JetBrains Mono", size: 9))
                    .foregroundColor(Color(hex: "#3A4A58"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().overlay(Color(hex: "#1E1E26"))

            ForEach(data.hosts) { host in
                NmapHostView(host: host)
                if host.id != data.hosts.last?.id {
                    Divider().overlay(Color(hex: "#1E1E26"))
                }
            }
        }
        .background(Color(hex: "#111115"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#1E1E26"), lineWidth: 1))
    }
}

struct NmapHostView: View {
    let host: NmapHost
    @State private var expanded = true

    var openPorts: [NmapPort] { host.ports.filter { $0.isOpen } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(openPorts.isEmpty ? Color(hex: "#FF4D6A") : Color(hex: "#3DFF8F"))
                        .frame(width: 7, height: 7)
                    Text(host.host)
                        .font(.custom("JetBrains Mono", size: 11).weight(.semibold))
                        .foregroundColor(Color(hex: "#D8E4F0"))
                    Spacer()
                    if let lat = host.latency {
                        Text(lat)
                            .font(.custom("JetBrains Mono", size: 9))
                            .foregroundColor(Color(hex: "#3A4A58"))
                    }
                    Text("\(openPorts.count) open")
                        .font(.custom("JetBrains Mono", size: 9))
                        .foregroundColor(Color(hex: "#00D4AA"))
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Color(hex: "#3A4A58"))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }
            .buttonStyle(.plain)

            if expanded && !host.ports.isEmpty {
                Divider().overlay(Color(hex: "#141418"))
                VStack(spacing: 0) {
                    ForEach(host.ports) { port in
                        HStack(spacing: 10) {
                            Text("\(port.port)/\(port.proto)")
                                .font(.custom("JetBrains Mono", size: 9).weight(.medium))
                                .foregroundColor(port.isOpen ? Color(hex: "#4A9EFF") : Color(hex: "#3A4A58"))
                                .frame(width: 70, alignment: .leading)
                            Circle()
                                .fill(port.isOpen ? Color(hex: "#3DFF8F") : Color(hex: "#3A4A58"))
                                .frame(width: 5, height: 5)
                            Text(port.service)
                                .font(.custom("JetBrains Mono", size: 9))
                                .foregroundColor(Color(hex: "#D8E4F0"))
                            if let ver = port.version {
                                Text(ver)
                                    .font(.custom("JetBrains Mono", size: 9))
                                    .foregroundColor(Color(hex: "#3A4A58"))
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        if port.id != host.ports.last?.id {
                            Divider().overlay(Color(hex: "#141418"))
                        }
                    }
                }
            }
        }
    }
}
