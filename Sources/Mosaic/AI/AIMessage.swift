import Foundation

enum AIMessageRole {
    case user
    case thinking
    case result
    case error
}

struct AIMessage: Identifiable {
    let id        = UUID()
    let role:     AIMessageRole
    var text:     String
    var command:  String?
    var rendererResult: RendererResult?
    let timestamp = Date()
}
