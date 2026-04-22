import SwiftUI

@MainActor
public final class WhoisRenderer: OutputRenderer {
    public let id          = "network.whois"
    public let displayName = "WHOIS"
    public let badgeLabel  = "WHOIS"
    public let priority    = RendererPriority.network

    public func canRender(command: String, output: String) -> Bool {
        command.lowercased().hasPrefix("whois")
    }

    public func parse(command: String, output: String) -> (any RendererData)? {
        let lines = output.components(separatedBy: "\n")
        guard lines.count > 5 else { return nil }

        let target = command.components(separatedBy: " ").dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespaces)

        var fields: [WhoisField] = []
        let interestingKeys: [String: String] = [
            "domain name":        "Domain",
            "registrar":          "Registrar",
            "creation date":      "Created",
            "updated date":       "Updated",
            "registry expiry date": "Expires",
            "expiry date":        "Expires",
            "registrant":         "Registrant",
            "registrant organization": "Org",
            "name server":        "Name Server",
            "dnssec":             "DNSSEC",
            "org":                "Org",
            "netname":            "Net Name",
            "country":            "Country",
            "address":            "Address",
            "admin-c":            "Admin",
            "tech-c":             "Tech",
        ]

        var seen = Set<String>()
        for line in lines {
            guard line.contains(":") else { continue }
            let parts = line.components(separatedBy: ":").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 2 else { continue }
            let rawKey = parts[0].lowercased()
            let value  = parts[1...].joined(separator: ":").trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { continue }

            for (pattern, label) in interestingKeys {
                if rawKey == pattern {
                    let dedupeKey = label + value
                    guard !seen.contains(dedupeKey) else { break }
                    seen.insert(dedupeKey)
                    fields.append(WhoisField(label: label, value: value))
                    break
                }
            }
        }

        guard !fields.isEmpty else { return nil }
        return WhoisData(target: target.isEmpty ? "unknown" : target, fields: fields)
    }

    public func view(for data: any RendererData) -> AnyView {
        guard let data = data as? WhoisData else { return AnyView(EmptyView()) }
        return AnyView(WhoisView(data: data))
    }
}

public struct WhoisData: RendererData {
    public let target: String
    public let fields: [WhoisField]
}

public struct WhoisField: Identifiable, Sendable {
    public let id = UUID()
    public let label: String
    public let value: String
}

struct WhoisView: View {
    let data: WhoisData

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("WHOIS")
                    .font(.custom("JetBrains Mono", size: 8).weight(.bold))
                    .foregroundColor(Color(hex: "#3A4A58"))
                    .kerning(0.4)
                Spacer()
                Text(data.target)
                    .font(.custom("JetBrains Mono", size: 10).weight(.semibold))
                    .foregroundColor(Color(hex: "#4A9EFF"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().overlay(Color(hex: "#1E1E26"))

            VStack(alignment: .leading, spacing: 0) {
                ForEach(data.fields) { field in
                    HStack(alignment: .top, spacing: 12) {
                        Text(field.label)
                            .font(.custom("JetBrains Mono", size: 9))
                            .foregroundColor(Color(hex: "#3A4A58"))
                            .frame(width: 80, alignment: .trailing)
                        Text(field.value)
                            .font(.custom("JetBrains Mono", size: 10))
                            .foregroundColor(Color(hex: "#D8E4F0"))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                }
            }
            .padding(.vertical, 4)
        }
        .background(Color(hex: "#111115"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#1E1E26"), lineWidth: 1))
    }
}
