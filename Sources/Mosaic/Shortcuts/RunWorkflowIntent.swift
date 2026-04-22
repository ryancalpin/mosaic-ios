import AppIntents
import SwiftData

struct RunWorkflowIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Workflow"
    static let description = IntentDescription("Run a saved Mosaic workflow on the active server connection.")

    @Parameter(title: "Workflow Name")
    var workflowName: String

    func perform() async throws -> some IntentResult {
        let schema = Schema([Workflow.self, WorkflowStep.self])
        let config = ModelConfiguration("local", schema: schema, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let ctx = ModelContext(container)

        var descriptor = FetchDescriptor<Workflow>()
        descriptor.predicate = #Predicate { $0.name == workflowName }
        let matches = try ctx.fetch(descriptor)

        guard let workflow = matches.first else {
            throw AppIntentError.workflowNotFound(workflowName)
        }

        guard let session = await MainActor.run(body: { SessionManager.shared.activeSession }) else {
            throw AppIntentError.noActiveSession
        }

        await session.runWorkflow(workflow)
        return .result()
    }
}
