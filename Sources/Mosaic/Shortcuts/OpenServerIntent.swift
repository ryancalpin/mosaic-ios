import AppIntents
import SwiftData

struct OpenServerIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Server in Mosaic"
    static var description = IntentDescription("Connect to a saved server by name.")

    @Parameter(title: "Server Name")
    var serverName: String

    func perform() async throws -> some IntentResult {
        let config = ModelConfiguration(cloudKitDatabase: .none)
        let container = try ModelContainer(for: Connection.self, configurations: config)
        let context = ModelContext(container)

        let descriptor = FetchDescriptor<Connection>(
            predicate: #Predicate { $0.name == serverName }
        )
        guard let connection = try context.fetch(descriptor).first else {
            throw AppIntentError.connectionNotFound(serverName)
        }

        await MainActor.run {
            Task { _ = await SessionManager.shared.openSessionThrowing(for: connection) }
        }
        return .result()
    }
}

enum AppIntentError: LocalizedError {
    case connectionNotFound(String)
    case workflowNotFound(String)
    case noActiveSession

    var errorDescription: String? {
        switch self {
        case .connectionNotFound(let name):
            return "No saved server named '\(name)' found in Mosaic."
        case .workflowNotFound(let name):
            return "No workflow named \"\(name)\" found."
        case .noActiveSession:
            return "No active server session. Connect to a server first."
        }
    }
}
