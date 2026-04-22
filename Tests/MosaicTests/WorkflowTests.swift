// Tests/MosaicTests/WorkflowTests.swift
import Testing
import SwiftData
@testable import Mosaic

@Suite("Workflow Model")
struct WorkflowModelTests {

    @Test func workflowInitDefaults() throws {
        let w = Workflow()
        #expect(w.name == "")
        #expect(w.desc == "")
        #expect(w.steps.isEmpty)
    }

    @Test func workflowStepInitDefaults() throws {
        let s = WorkflowStep()
        #expect(s.command == "")
        #expect(s.delayAfter == 0.0)
        #expect(s.position == 0)
    }

    @Test func workflowStepsSortedByPosition() throws {
        let w = Workflow()
        let s1 = WorkflowStep(); s1.command = "echo first"; s1.position = 0
        let s2 = WorkflowStep(); s2.command = "echo second"; s2.position = 1
        w.steps = [s2, s1]
        let sorted = w.orderedSteps
        #expect(sorted.first?.command == "echo first")
        #expect(sorted.last?.command == "echo second")
    }

    @Test func workflowInMemoryContainer() throws {
        let schema = Schema([Workflow.self, WorkflowStep.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let ctx = ModelContext(container)

        let w = Workflow()
        w.name = "Deploy"
        w.desc = "Full deploy sequence"
        ctx.insert(w)

        let step = WorkflowStep()
        step.command = "npm run build"
        step.position = 0
        step.workflow = w
        w.steps.append(step)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Workflow>())
        #expect(fetched.count == 1)
        #expect(fetched[0].name == "Deploy")
        #expect(fetched[0].steps.count == 1)
    }
}
