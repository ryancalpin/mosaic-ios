import SwiftUI

// MARK: - CustomRendererData

public struct CustomRendererData: RendererData, @unchecked Sendable {
    public let fields: [(label: String, value: String)]
    public let layout: RendererLayout
}

// MARK: - CustomRendererAdapter

@MainActor
public final class CustomRendererAdapter: OutputRenderer {
    private let model: CustomRenderer
    private var cachedRegex: NSRegularExpression?

    public init(model: CustomRenderer) {
        self.model = model
    }

    public var id: String { "custom.\(model.id.uuidString)" }
    public var displayName: String { model.name }
    public var badgeLabel: String { model.name.uppercased() }
    public var priority: Int { 1000 }

    public func canRender(command: String, output: String) -> Bool {
        guard !model.commandPattern.isEmpty else { return false }
        if cachedRegex == nil {
            cachedRegex = try? NSRegularExpression(pattern: model.commandPattern, options: [.caseInsensitive])
        }
        guard let regex = cachedRegex else { return false }
        let range = NSRange(command.startIndex..., in: command)
        return regex.firstMatch(in: command, range: range) != nil
    }

    public func parse(command: String, output: String) -> (any RendererData)? {
        let rules = model.extractionRules
        guard !rules.isEmpty else { return nil }

        var fields: [(label: String, value: String)] = []
        for rule in rules {
            guard !rule.pattern.isEmpty,
                  let regex = try? NSRegularExpression(pattern: rule.pattern),
                  let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
                  match.numberOfRanges > rule.captureGroup,
                  let captureRange = Range(match.range(at: rule.captureGroup), in: output)
            else { continue }
            let value = String(output[captureRange])
            fields.append((label: rule.label, value: value))
        }

        guard !fields.isEmpty else { return nil }
        return CustomRendererData(fields: fields, layout: model.rendererLayout)
    }

    public func view(for data: any RendererData) -> AnyView {
        guard let d = data as? CustomRendererData else { return AnyView(EmptyView()) }
        switch d.layout {
        case .keyValue: return AnyView(KeyValueLayoutView(fields: d.fields))
        case .badgeRow: return AnyView(BadgeRowLayoutView(fields: d.fields))
        case .table:    return AnyView(TableLayoutView(fields: d.fields))
        }
    }
}

// MARK: - KeyValueLayoutView

struct KeyValueLayoutView: View {
    let fields: [(label: String, value: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                HStack(alignment: .top, spacing: 8) {
                    Text(field.label.uppercased())
                        .font(.custom("JetBrains Mono", size: 9).weight(.bold))
                        .foregroundStyle(Color.mosaicTextSec)
                        .frame(minWidth: 90, alignment: .leading)
                    Text(field.value)
                        .font(.custom("JetBrains Mono", size: 11))
                        .foregroundStyle(Color.mosaicTextPri)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.mosaicSurface1)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.mosaicBorder, lineWidth: 0.5))
    }
}

// MARK: - BadgeRowLayoutView

struct BadgeRowLayoutView: View {
    let fields: [(label: String, value: String)]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], spacing: 8) {
            ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                VStack(spacing: 2) {
                    Text(field.label)
                        .font(.custom("JetBrains Mono", size: 7).weight(.bold))
                        .foregroundStyle(Color.mosaicAccent.opacity(0.7))
                    Text(field.value)
                        .font(.custom("JetBrains Mono", size: 9))
                        .foregroundStyle(Color.mosaicAccent)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.mosaicSurface2)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(10)
    }
}

// MARK: - TableLayoutView

struct TableLayoutView: View {
    let fields: [(label: String, value: String)]

    var body: some View {
        VStack(spacing: 0) {
            // Header row
            HStack {
                ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                    Text(field.label.uppercased())
                        .font(.custom("JetBrains Mono", size: 9).weight(.bold))
                        .foregroundStyle(Color.mosaicTextSec)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.mosaicSurface2)

            Divider().background(Color.mosaicBorder)

            // Data row
            HStack {
                ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                    Text(field.value)
                        .font(.custom("JetBrains Mono", size: 11))
                        .foregroundStyle(Color.mosaicTextPri)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.mosaicSurface1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.mosaicBorder, lineWidth: 0.5))
    }
}
