import SwiftUI

@MainActor
public final class JsonTreeRenderer: OutputRenderer {
    public let id          = "data.json"
    public let displayName = "JSON Tree"
    public let badgeLabel  = "JSON"
    public let priority    = RendererPriority.data

    public func canRender(command: String, output: String) -> Bool {
        if command.lowercased().hasPrefix("jq") { return true }
        let t = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("{") || t.hasPrefix("[") else { return false }
        return (try? JSONSerialization.jsonObject(with: Data(t.utf8))) != nil
    }

    public func parse(command: String, output: String) -> (any RendererData)? {
        let t = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = t.data(using: .utf8), let raw = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return JsonTreeData(root: JsonNode(from: raw))
    }

    public func view(for data: any RendererData) -> AnyView {
        guard let data = data as? JsonTreeData else { return AnyView(EmptyView()) }
        return AnyView(JsonTreeView(data: data))
    }
}

public indirect enum JsonNode: Sendable {
    case object([(key: String, value: JsonNode)])
    case array([JsonNode])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    init(from value: Any) {
        switch value {
        case let dict as [String: Any]: self = .object(dict.sorted { $0.key < $1.key }.map { ($0.key, JsonNode(from: $0.value)) })
        case let arr as [Any]:          self = .array(arr.map { JsonNode(from: $0) })
        case let str as String:         self = .string(str)
        case let num as NSNumber:       self = (num === kCFBooleanTrue || num === kCFBooleanFalse) ? .bool(num.boolValue) : .number(num.doubleValue)
        default:                        self = .null
        }
    }
    var countBadge: String? { if case .object(let p) = self { return "{\(p.count)}" }; if case .array(let a) = self { return "[\(a.count)]" }; return nil }
}
public struct JsonTreeData: RendererData { public let root: JsonNode }

private struct JsonTreeView: View {
    let data: JsonTreeData
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "curlybraces").font(.system(size: 11, weight: .semibold)).foregroundColor(Color(hex: "#00D4AA"))
                Text("JSON").font(.custom("JetBrains Mono", size: 11.5).weight(.semibold)).foregroundColor(Color(hex: "#D8E4F0"))
                Spacer()
                if let b = data.root.countBadge { Text(b).font(.custom("JetBrains Mono", size: 9)).foregroundColor(Color(hex: "#3A4A58")) }
            }.padding(.horizontal, 12).padding(.vertical, 9)
            Divider().overlay(Color(hex: "#141418"))
            ScrollView { VStack(alignment: .leading, spacing: 0) { JsonNodeView(node: data.root, key: nil, depth: 0, autoExpand: true) }.padding(12) }.frame(maxHeight: 400)
        }
        .background(Color(hex: "#111115")).clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#1E1E26"), lineWidth: 1))
    }
}

private struct JsonNodeView: View {
    let node: JsonNode; let key: String?; let depth: Int; let autoExpand: Bool
    @State private var isExpanded: Bool
    init(node: JsonNode, key: String?, depth: Int, autoExpand: Bool) {
        self.node = node; self.key = key; self.depth = depth; self.autoExpand = autoExpand
        _isExpanded = State(initialValue: autoExpand && depth < 2)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch node {
            case .object(let pairs):
                collapsibleRow(badge: "{\(pairs.count)}", badgeColor: Color(hex: "#A78BFA")) { ForEach(Array(pairs.enumerated()), id: \.offset) { _, p in JsonNodeView(node: p.value, key: p.key, depth: depth+1, autoExpand: false).padding(.leading, 16) } }
            case .array(let items):
                collapsibleRow(badge: "[\(items.count)]", badgeColor: Color(hex: "#4A9EFF")) { ForEach(Array(items.enumerated()), id: \.offset) { i, item in JsonNodeView(node: item, key: "\(i)", depth: depth+1, autoExpand: false).padding(.leading, 16) } }
            case .string(let s): leafRow(value: "\"\(s)\"", valueColor: Color(hex: "#3DFF8F"))
            case .number(let n): leafRow(value: n.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", n) : String(n), valueColor: Color(hex: "#4A9EFF"))
            case .bool(let b):   leafRow(value: b ? "true" : "false", valueColor: Color(hex: "#FFD060"))
            case .null:          leafRow(value: "null", valueColor: Color(hex: "#FF4D6A"))
            }
        }
    }
    @ViewBuilder private func collapsibleRow(badge: String, badgeColor: Color, @ViewBuilder children: () -> some View) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } } label: {
            HStack(spacing: 4) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundColor(Color(hex: "#3A4A58")).frame(width: 10)
                if let k = key { Text(k).font(.custom("JetBrains Mono", size: 10)).foregroundColor(Color(hex: "#3A4A58")); Text(":").font(.custom("JetBrains Mono", size: 10)).foregroundColor(Color(hex: "#1E1E26")) }
                Text(badge).font(.custom("JetBrains Mono", size: 9).weight(.bold)).foregroundColor(badgeColor).padding(.horizontal, 4).padding(.vertical, 1).background(badgeColor.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 3))
                Spacer()
            }.padding(.vertical, 3)
        }.buttonStyle(.plain)
        if isExpanded { children() }
    }
    @ViewBuilder private func leafRow(value: String, valueColor: Color) -> some View {
        HStack(spacing: 4) {
            Rectangle().fill(Color.clear).frame(width: 14)
            if let k = key { Text(k).font(.custom("JetBrains Mono", size: 10)).foregroundColor(Color(hex: "#3A4A58")); Text(":").font(.custom("JetBrains Mono", size: 10)).foregroundColor(Color(hex: "#1E1E26")) }
            Text(value).font(.custom("JetBrains Mono", size: 10)).foregroundColor(valueColor).lineLimit(3).truncationMode(.tail)
            Spacer()
        }.padding(.vertical, 3)
    }
}
