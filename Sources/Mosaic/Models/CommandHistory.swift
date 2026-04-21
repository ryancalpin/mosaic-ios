import SwiftData
import Foundation

@Model
final class CommandHistory {
    var command: String
    var timestamp: Date
    var sessionHostname: String

    init(command: String, sessionHostname: String) {
        self.command = command
        self.timestamp = Date()
        self.sessionHostname = sessionHostname
    }
}
