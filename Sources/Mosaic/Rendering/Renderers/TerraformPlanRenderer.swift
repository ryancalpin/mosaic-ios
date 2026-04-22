import SwiftUI

@MainActor
public final class TerraformPlanRenderer: OutputRenderer {
    public let id          = "infra.terraform"
    public let displayName = "Terraform Plan"
    public let badgeLabel  = "TERRAFORM"
    public let priority    = RendererPriority.system

    public func canRender(command: String, output: String) -> Bool {
        let cmd = command.lowercased()
        let isTF = cmd.hasPrefix("terraform") || cmd.hasPrefix("tofu")
        let looksLikePlan = output.contains("Plan:") || output.contains("No changes") ||
            output.contains("will be created") || output.contains("will be destroyed")
        return isTF && looksLikePlan
    }

    public func parse(command: String, output: String) -> (any RendererData)? {
        let lines = output.components(separatedBy: "\n")

        var resources: [TFResource] = []
        // Matches: "  # aws_instance.web will be created" etc.
        let resourceRegex = try? NSRegularExpression(
            pattern: #"#\s+(\S+)\s+will be (created|destroyed|updated in-place|replaced)"#
        )
        // ANSI escape stripper
        let ansiRegex = try? NSRegularExpression(pattern: #"\x1B\[[0-9;]*m"#)

        func stripANSI(_ s: String) -> String {
            let ns = s as NSString
            return ansiRegex?.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: ns.length), withTemplate: "") ?? s
        }

        for line in lines {
            let clean = stripANSI(line)
            let ns = clean as NSString
            guard let m = resourceRegex?.firstMatch(in: clean, range: NSRange(location: 0, length: ns.length)),
                  m.numberOfRanges >= 3,
                  let nameR   = Range(m.range(at: 1), in: clean),
                  let actionR = Range(m.range(at: 2), in: clean) else { continue }

            let name   = String(clean[nameR])
            let action = String(clean[actionR])
            let kind: TFChangeKind
            switch action {
            case "created":           kind = .create
            case "destroyed":         kind = .destroy
            case "updated in-place":  kind = .update
            default:                  kind = .replace
            }
            resources.append(TFResource(name: name, kind: kind))
        }

        // Summary line: "Plan: 3 to add, 1 to change, 2 to destroy."
        var summary: TFSummary? = nil
        if let summaryLine = lines.first(where: { stripANSI($0).contains("Plan:") || stripANSI($0).contains("No changes") }) {
            let clean = stripANSI(summaryLine)
            if clean.contains("No changes") {
                summary = TFSummary(toAdd: 0, toChange: 0, toDestroy: 0)
            } else {
                let numRx = try? NSRegularExpression(pattern: #"(\d+) to add.*?(\d+) to change.*?(\d+) to destroy"#)
                let ns = clean as NSString
                if let m = numRx?.firstMatch(in: clean, range: NSRange(location: 0, length: ns.length)),
                   m.numberOfRanges >= 4,
                   let r1 = Range(m.range(at: 1), in: clean),
                   let r2 = Range(m.range(at: 2), in: clean),
                   let r3 = Range(m.range(at: 3), in: clean) {
                    summary = TFSummary(
                        toAdd:     Int(clean[r1]) ?? 0,
                        toChange:  Int(clean[r2]) ?? 0,
                        toDestroy: Int(clean[r3]) ?? 0
                    )
                }
            }
        }

        guard !resources.isEmpty || summary != nil else { return nil }
        return TFPlanData(resources: resources, summary: summary)
    }

    public func view(for data: any RendererData) -> AnyView {
        guard let data = data as? TFPlanData else { return AnyView(EmptyView()) }
        return AnyView(TerraformPlanView(data: data))
    }
}

public enum TFChangeKind: Sendable {
    case create, update, destroy, replace

    public var symbol: String {
        switch self {
        case .create:  return "+"
        case .update:  return "~"
        case .destroy: return "-"
        case .replace: return "±"
        }
    }

    public var color: Color {
        switch self {
        case .create:  return Color(hex: "#3DFF8F")
        case .update:  return Color(hex: "#FFD060")
        case .destroy: return Color(hex: "#FF4D6A")
        case .replace: return Color(hex: "#FFB020")
        }
    }
}

public struct TFResource: Identifiable, Sendable {
    public let id   = UUID()
    public let name: String
    public let kind: TFChangeKind
}

public struct TFSummary: Sendable {
    public let toAdd:     Int
    public let toChange:  Int
    public let toDestroy: Int
    public var noChanges: Bool { toAdd == 0 && toChange == 0 && toDestroy == 0 }
}

public struct TFPlanData: RendererData {
    public let resources: [TFResource]
    public let summary:   TFSummary?
}

struct TerraformPlanView: View {
    let data: TFPlanData

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("TERRAFORM PLAN")
                    .font(.custom("JetBrains Mono", size: 8).weight(.bold))
                    .foregroundColor(Color(hex: "#3A4A58"))
                    .kerning(0.4)
                Spacer()
                if let s = data.summary {
                    if s.noChanges {
                        Text("No changes")
                            .font(.custom("JetBrains Mono", size: 9))
                            .foregroundColor(Color(hex: "#3DFF8F"))
                    } else {
                        HStack(spacing: 8) {
                            if s.toAdd > 0 {
                                Label("+\(s.toAdd)", systemImage: "plus")
                                    .font(.custom("JetBrains Mono", size: 9))
                                    .foregroundColor(Color(hex: "#3DFF8F"))
                            }
                            if s.toChange > 0 {
                                Label("~\(s.toChange)", systemImage: "arrow.triangle.2.circlepath")
                                    .font(.custom("JetBrains Mono", size: 9))
                                    .foregroundColor(Color(hex: "#FFD060"))
                            }
                            if s.toDestroy > 0 {
                                Label("-\(s.toDestroy)", systemImage: "minus")
                                    .font(.custom("JetBrains Mono", size: 9))
                                    .foregroundColor(Color(hex: "#FF4D6A"))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if !data.resources.isEmpty {
                Divider().overlay(Color(hex: "#1E1E26"))

                VStack(spacing: 0) {
                    ForEach(data.resources) { res in
                        HStack(spacing: 10) {
                            Text(res.kind.symbol)
                                .font(.custom("JetBrains Mono", size: 12).weight(.bold))
                                .foregroundColor(res.kind.color)
                                .frame(width: 16, alignment: .center)

                            let parts = res.name.components(separatedBy: ".")
                            VStack(alignment: .leading, spacing: 2) {
                                if parts.count >= 2 {
                                    Text(parts.dropLast().joined(separator: "."))
                                        .font(.custom("JetBrains Mono", size: 8))
                                        .foregroundColor(Color(hex: "#3A4A58"))
                                    Text(parts.last ?? res.name)
                                        .font(.custom("JetBrains Mono", size: 10).weight(.medium))
                                        .foregroundColor(Color(hex: "#D8E4F0"))
                                } else {
                                    Text(res.name)
                                        .font(.custom("JetBrains Mono", size: 10).weight(.medium))
                                        .foregroundColor(Color(hex: "#D8E4F0"))
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        if res.id != data.resources.last?.id {
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
