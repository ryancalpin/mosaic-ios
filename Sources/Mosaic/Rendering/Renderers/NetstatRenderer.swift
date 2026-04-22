import SwiftUI

@MainActor
public final class NetstatRenderer: OutputRenderer {
    public let id          = "network.netstat"
    public let displayName = "Network Connections"
    public let badgeLabel  = "NETSTAT"
    public let priority    = RendererPriority.network

    public func canRender(command: String, output: String) -> Bool {
        let cmd = command.lowercased()
        let isNetstatCmd = cmd.hasPrefix("netstat") || cmd.hasPrefix("ss ")
            || cmd == "ss" || cmd.hasPrefix("ss -")
        let looksLikeOutput = output.contains("LISTEN") || output.contains("ESTABLISHED")
        return isNetstatCmd || (looksLikeOutput && output.contains("Proto"))
    }

    public func parse(command: String, output: String) -> (any RendererData)? {
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }

        // Detect ss vs netstat format
        let isSS = output.contains("Netid") || command.lowercased().hasPrefix("ss")

        var connections: [NetstatConnection] = []

        if isSS {
            connections = parseSSOutput(lines: lines)
        } else {
            connections = parseNetstatOutput(lines: lines)
        }

        guard !connections.isEmpty else { return nil }

        let listening    = connections.filter { $0.state == "LISTEN" }
        let established  = connections.filter { $0.state == "ESTABLISHED" }
        let other        = connections.filter { $0.state != "LISTEN" && $0.state != "ESTABLISHED" }

        return NetstatData(listening: listening, established: established, other: other)
    }

    private func parseNetstatOutput(lines: [String]) -> [NetstatConnection] {
        guard let headerIdx = lines.firstIndex(where: { $0.contains("Proto") && $0.contains("Local Address") }) else {
            return []
        }
        var results: [NetstatConnection] = []
        for line in lines[(headerIdx + 1)...] {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 5 else { continue }
            let proto = parts[0]
            let local = parts[3]
            let foreign = parts[4]
            let state = parts.count >= 6 ? parts[5] : "—"
            results.append(NetstatConnection(proto: proto, local: local, foreign: foreign, state: state))
        }
        return results
    }

    private func parseSSOutput(lines: [String]) -> [NetstatConnection] {
        guard let headerIdx = lines.firstIndex(where: { $0.contains("Netid") }) else {
            return []
        }
        var results: [NetstatConnection] = []
        for line in lines[(headerIdx + 1)...] {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 5 else { continue }
            let proto   = parts[0]
            let state   = parts[1]
            let local   = parts[4]
            let foreign = parts.count >= 6 ? parts[5] : "*"
            results.append(NetstatConnection(proto: proto, local: local, foreign: foreign, state: state))
        }
        return results
    }

    public func view(for data: any RendererData) -> AnyView {
        guard let data = data as? NetstatData else { return AnyView(EmptyView()) }
        return AnyView(NetstatView(data: data))
    }
}

public struct NetstatData: RendererData {
    public let listening:   [NetstatConnection]
    public let established: [NetstatConnection]
    public let other:       [NetstatConnection]
}

public struct NetstatConnection: Identifiable, Sendable {
    public let id      = UUID()
    public let proto:   String
    public let local:   String
    public let foreign: String
    public let state:   String
}

struct NetstatView: View {
    let data: NetstatData
    @State private var tab: NetstatTab = .listening

    enum NetstatTab: String, CaseIterable {
        case listening   = "LISTEN"
        case established = "ESTAB"
        case other       = "OTHER"
    }

    var displayed: [NetstatConnection] {
        switch tab {
        case .listening:   return data.listening
        case .established: return data.established
        case .other:       return data.other
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                ForEach(NetstatTab.allCases, id: \.self) { t in
                    Button {
                        tab = t
                    } label: {
                        let count: Int = {
                            switch t {
                            case .listening:   return data.listening.count
                            case .established: return data.established.count
                            case .other:       return data.other.count
                            }
                        }()
                        VStack(spacing: 3) {
                            HStack(spacing: 4) {
                                Text(t.rawValue)
                                    .font(.custom("JetBrains Mono", size: 8).weight(.bold))
                                    .kerning(0.4)
                                Text("\(count)")
                                    .font(.custom("JetBrains Mono", size: 8).weight(.bold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(tab == t ? Color(hex: "#00D4AA").opacity(0.15) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                            .foregroundColor(tab == t ? Color(hex: "#00D4AA") : Color(hex: "#3A4A58"))
                            Rectangle()
                                .fill(tab == t ? Color(hex: "#00D4AA") : Color.clear)
                                .frame(height: 2)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 12)

            Divider().overlay(Color(hex: "#1E1E26"))

            if displayed.isEmpty {
                Text("No connections")
                    .font(.custom("JetBrains Mono", size: 10))
                    .foregroundColor(Color(hex: "#3A4A58"))
                    .padding(16)
            } else {
                VStack(spacing: 0) {
                    ForEach(displayed) { conn in
                        HStack(spacing: 8) {
                            Text(conn.proto.uppercased())
                                .font(.custom("JetBrains Mono", size: 8).weight(.bold))
                                .foregroundColor(conn.proto.lowercased().contains("tcp") ? Color(hex: "#4A9EFF") : Color(hex: "#A78BFA"))
                                .frame(width: 30, alignment: .leading)
                            Text(conn.local)
                                .font(.custom("JetBrains Mono", size: 9).weight(.medium))
                                .foregroundColor(Color(hex: "#D8E4F0"))
                                .lineLimit(1)
                            Spacer()
                            if conn.foreign != "*" && conn.foreign != "0.0.0.0:*" {
                                Text(conn.foreign)
                                    .font(.custom("JetBrains Mono", size: 9))
                                    .foregroundColor(Color(hex: "#3A4A58"))
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        if conn.id != displayed.last?.id {
                            Divider().overlay(Color(hex: "#141418"))
                        }
                    }
                }
            }
        }
        .background(Color(hex: "#111115"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#1E1E26"), lineWidth: 1))
    }
}
