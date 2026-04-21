import Foundation
import SwiftData

public enum RendererLayout: String, CaseIterable, Codable {
    case keyValue = "keyValue"
    case badgeRow = "badgeRow"
    case table    = "table"
}

public struct ExtractionRule: Codable, Identifiable, Sendable {
    public var id: UUID
    public var label: String
    public var pattern: String
    public var captureGroup: Int

    public init(id: UUID = UUID(), label: String = "", pattern: String = "", captureGroup: Int = 1) {
        self.id           = id
        self.label        = label
        self.pattern      = pattern
        self.captureGroup = captureGroup
    }
}

@Model
public final class CustomRenderer {
    public var id:                   UUID
    public var name:                 String
    public var commandPattern:       String
    public var extractionRulesJSON:  String
    public var layout:               String
    public var createdAt:            Date

    public init(name: String, commandPattern: String, layout: RendererLayout = .keyValue) {
        self.id                  = UUID()
        self.name                = name
        self.commandPattern      = commandPattern
        self.extractionRulesJSON = "[]"
        self.layout              = layout.rawValue
        self.createdAt           = Date()
    }

    public var extractionRules: [ExtractionRule] {
        (try? JSONDecoder().decode([ExtractionRule].self, from: Data(extractionRulesJSON.utf8))) ?? []
    }

    public var rendererLayout: RendererLayout {
        RendererLayout(rawValue: layout) ?? .keyValue
    }

    public func setExtractionRules(_ rules: [ExtractionRule]) {
        extractionRulesJSON = (try? String(data: JSONEncoder().encode(rules), encoding: .utf8)) ?? "[]"
    }
}
