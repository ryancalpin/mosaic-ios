import SwiftUI

// MARK: - OutputRenderer Protocol
//
// Every native renderer conforms to this.
// The registry tries each renderer in priority order.
// If parse() returns nil, the next renderer is tried.
// If all renderers fail, the output is shown as raw terminal text.
//
// RULE: parse() must NEVER partially succeed. If the output doesn't
// match the expected format exactly, return nil immediately.

// Renderers are always created and used on @MainActor (RendererRegistry is @MainActor).
@MainActor
public protocol OutputRenderer: AnyObject {
    /// Unique identifier e.g. "docker.ps", "git.status"
    var id: String { get }

    /// Human-readable name e.g. "Container List"
    var displayName: String { get }

    /// Text shown in the NATIVE badge e.g. "CONTAINERS"
    var badgeLabel: String { get }

    /// Higher priority = tried first. Built-ins are 100–999. Custom renderers default to 1000.
    var priority: Int { get }

    /// Quick pre-check before attempting a full parse.
    /// command: what the user typed (may be empty for alias-resolved commands)
    /// output: the raw terminal output string
    func canRender(command: String, output: String) -> Bool

    /// Full parse attempt. Returns nil if output doesn't match — never throws for format errors.
    func parse(command: String, output: String) -> (any RendererData)?

    /// The SwiftUI view to render. Called only after a successful parse().
    @ViewBuilder
    func view(for data: any RendererData) -> AnyView
}

// MARK: - RendererData

/// Marker protocol for typed renderer payloads.
/// Each renderer defines its own concrete RendererData type.
public protocol RendererData: Sendable {}

// MARK: - RendererResult

public enum RendererResult {
    /// A renderer matched and parsed successfully.
    case native(renderer: any OutputRenderer, data: any RendererData, raw: String)

    /// No renderer matched — show as clean monospace terminal text.
    case raw(String)

    public var rawText: String {
        switch self {
        case .native(_, _, let raw): return raw
        case .raw(let text):         return text
        }
    }

    public var isNative: Bool {
        if case .native = self { return true }
        return false
    }
}

// MARK: - Built-in Renderer Priority Constants

public enum RendererPriority {
    /// System-level output (processes, disk, network)
    static let system     = 900
    /// Docker / container output
    static let docker     = 850
    /// Git output
    static let git        = 800
    /// File system output
    static let filesystem = 750
    /// Network tools
    static let network    = 700
    /// Package managers
    static let packages   = 650
    /// Data / structured formats (JSON, CSV)
    static let data       = 600
    /// Catch-all / generic
    static let generic    = 100
    /// Custom user-defined renderers (checked first)
    static let custom     = 1000
}
