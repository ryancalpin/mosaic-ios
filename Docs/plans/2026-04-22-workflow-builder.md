# Workflow Builder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Saved sequences of shell commands that can be run as a unit, browsed/edited/created via a sheet, triggered from iOS Shortcuts, and stored in SwiftData.

**Architecture:** Two new `@Model` classes — `Workflow` (name, description, steps, createdAt) and `WorkflowStep` (command, delayAfter, position) — added to the `localConfig` ModelContainer. `Session` gains a `runWorkflow(_:)` method that iterates steps sequentially via the existing `send(_:)` mechanism. A `WorkflowListView` sheet is accessible from SessionView's toolbar. `RunWorkflowIntent` (AppIntents) follows the existing `OpenServerIntent` pattern.

**Tech Stack:** SwiftData, SwiftUI, AppIntents, Swift Testing, `@Model`, `ModelContainer`

---

## File Map

| Action | Path |
|--------|------|
| Create | `Sources/Mosaic/Models/Workflow.swift` |
| Modify | `Sources/Mosaic/App/MosaicApp.swift` |
| Modify | `Sources/Mosaic/Core/Session.swift` |
| Create | `Sources/Mosaic/UI/Workflows/WorkflowListView.swift` |
| Create | `Sources/Mosaic/UI/Workflows/WorkflowFormView.swift` |
| Modify | `Sources/Mosaic/UI/Session/SessionView.swift` |
| Create | `Sources/Mosaic/Shortcuts/RunWorkflowIntent.swift` |
| Create | `Tests/MosaicTests/WorkflowTests.swift` |

---

### Task 1: Workflow and WorkflowStep SwiftData Models

**Files:**
- Create: `Sources/Mosaic/Models/Workflow.swift`
- Create: `Tests/MosaicTests/WorkflowTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
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
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
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
```

- [ ] **Step 2: Run to confirm failure**

```
xcodebuild test -scheme Mosaic -destination 'id=913B454F-493C-46DC-B2B4-63348DA39843' -only-testing:MosaicTests/WorkflowModelTests 2>&1 | tail -20
```

Expected: FAIL — `Workflow` and `WorkflowStep` types not found.

- [ ] **Step 3: Create Workflow.swift**

```swift
// Sources/Mosaic/Models/Workflow.swift
import Foundation
import SwiftData

@Model
public final class Workflow {
    public var name: String = ""
    public var desc: String = ""
    public var createdAt: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \WorkflowStep.workflow)
    public var steps: [WorkflowStep] = []

    public init() {}

    public var orderedSteps: [WorkflowStep] {
        steps.sorted { $0.position < $1.position }
    }
}

@Model
public final class WorkflowStep {
    public var command: String = ""
    public var delayAfter: Double = 0.0
    public var position: Int = 0
    public var workflow: Workflow?

    public init() {}
}
```

- [ ] **Step 4: Run tests — confirm passing**

```
xcodebuild test -scheme Mosaic -destination 'id=913B454F-493C-46DC-B2B4-63348DA39843' -only-testing:MosaicTests/WorkflowModelTests 2>&1 | tail -20
```

Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/Mosaic/Models/Workflow.swift Tests/MosaicTests/WorkflowTests.swift
git commit -m "feat(workflows): add Workflow and WorkflowStep SwiftData models with orderedSteps helper"
```

---

### Task 2: Add Workflow Models to ModelContainer

**Files:**
- Modify: `Sources/Mosaic/App/MosaicApp.swift`

- [ ] **Step 1: Add Workflow and WorkflowStep to localConfig**

In `MosaicApp.swift`, find the `localConfig` ModelConfiguration. It currently looks like:

```swift
let localConfig = ModelConfiguration(
    "local",
    schema: Schema([CommandHistory.self, CustomRenderer.self]),
    cloudKitDatabase: .none
)
```

Update it to include `Workflow` and `WorkflowStep`:

```swift
let localConfig = ModelConfiguration(
    "local",
    schema: Schema([CommandHistory.self, CustomRenderer.self, Workflow.self, WorkflowStep.self]),
    cloudKitDatabase: .none
)
```

- [ ] **Step 2: Build check**

```
xcodebuild build -scheme Mosaic -destination 'generic/platform=iOS Simulator' 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Sources/Mosaic/App/MosaicApp.swift
git commit -m "feat(workflows): register Workflow and WorkflowStep in localConfig ModelContainer"
```

---

### Task 3: Session.runWorkflow(_:)

**Files:**
- Modify: `Sources/Mosaic/Core/Session.swift`
- Modify: `Tests/MosaicTests/WorkflowTests.swift`

- [ ] **Step 1: Write failing test**

In `Tests/MosaicTests/WorkflowTests.swift`, add a new `@Suite`:

```swift
@Suite("Session runWorkflow")
@MainActor
struct SessionRunWorkflowTests {

    @Test func runWorkflowExecutesStepsInOrder() async throws {
        var sentCommands: [String] = []
        let session = Session(connection: RecordingMockConnection(onSend: { cmd in
            sentCommands.append(cmd)
        }))

        let w = Workflow()
        let s1 = WorkflowStep(); s1.command = "echo step1"; s1.position = 0; s1.delayAfter = 0
        let s2 = WorkflowStep(); s2.command = "echo step2"; s2.position = 1; s2.delayAfter = 0
        w.steps = [s2, s1]  // intentionally out of order

        await session.runWorkflow(w)

        #expect(sentCommands.count == 2)
        #expect(sentCommands[0].contains("echo step1"))
        #expect(sentCommands[1].contains("echo step2"))
    }
}

// Mock that records sent commands
final class RecordingMockConnection: TerminalConnection {
    let onSend: (String) -> Void
    var connectionInfo = ConnectionInfo(
        hostname: "test", port: 22, username: "user",
        transport: .ssh, authMethod: .password
    )
    var connectionState: ConnectionState = .connected
    var outputStream: AsyncStream<Data> { AsyncStream { _ in } }
    init(onSend: @escaping (String) -> Void) { self.onSend = onSend }
    func connect() async throws {}
    func disconnect() {}
    func send(_ data: Data) {
        if let s = String(data: data, encoding: .utf8) { onSend(s) }
    }
    func setTerminalSize(cols: Int, rows: Int) {}
}
```

- [ ] **Step 2: Run to confirm failure**

```
xcodebuild test -scheme Mosaic -destination 'id=913B454F-493C-46DC-B2B4-63348DA39843' -only-testing:MosaicTests/SessionRunWorkflowTests 2>&1 | tail -20
```

Expected: FAIL — `Session` has no `runWorkflow(_:)`.

- [ ] **Step 3: Add runWorkflow to Session**

In `Sources/Mosaic/Core/Session.swift`, add:

```swift
func runWorkflow(_ workflow: Workflow) async {
    for step in workflow.orderedSteps {
        send(step.command)
        if step.delayAfter > 0 {
            try? await Task.sleep(nanoseconds: UInt64(step.delayAfter * 1_000_000_000))
        }
    }
}
```

`send(_:)` is the existing method that creates an `OutputBlock` and transmits the command.

- [ ] **Step 4: Run tests — confirm passing**

```
xcodebuild test -scheme Mosaic -destination 'id=913B454F-493C-46DC-B2B4-63348DA39843' -only-testing:MosaicTests/SessionRunWorkflowTests 2>&1 | tail -20
```

Expected: PASS (1 test in this suite)

- [ ] **Step 5: Build check**

```
xcodebuild build -scheme Mosaic -destination 'generic/platform=iOS Simulator' 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add Sources/Mosaic/Core/Session.swift Tests/MosaicTests/WorkflowTests.swift
git commit -m "feat(workflows): add Session.runWorkflow(_:) — executes steps sequentially with optional delay"
```

---

### Task 4: WorkflowListView and WorkflowFormView

**Files:**
- Create: `Sources/Mosaic/UI/Workflows/WorkflowListView.swift`
- Create: `Sources/Mosaic/UI/Workflows/WorkflowFormView.swift`

- [ ] **Step 1: Create WorkflowFormView**

```swift
// Sources/Mosaic/UI/Workflows/WorkflowFormView.swift
import SwiftUI
import SwiftData

@MainActor
struct WorkflowFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // nil = create mode, non-nil = edit mode
    var workflow: Workflow?
    var onSave: ((Workflow) -> Void)?

    @State private var name = ""
    @State private var desc = ""
    @State private var steps: [DraftStep] = []

    struct DraftStep: Identifiable {
        let id = UUID()
        var command: String
        var delayAfter: Double
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Info") {
                    TextField("Name", text: $name)
                    TextField("Description (optional)", text: $desc)
                }

                Section("Steps") {
                    ForEach($steps) { $step in
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Command", text: $step.command)
                                .font(.custom("JetBrains Mono", size: 13))
                            HStack {
                                Text("Delay after")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Slider(value: $step.delayAfter, in: 0...10, step: 0.5)
                                Text(step.delayAfter == 0 ? "none" : String(format: "%.1fs", step.delayAfter))
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.secondary)
                                    .frame(width: 44)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onMove { from, to in steps.move(fromOffsets: from, toOffset: to) }
                    .onDelete { steps.remove(atOffsets: $0) }

                    Button {
                        steps.append(DraftStep(command: "", delayAfter: 0))
                    } label: {
                        Label("Add Step", systemImage: "plus")
                    }
                }
            }
            .navigationTitle(workflow == nil ? "New Workflow" : "Edit Workflow")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear { loadExisting() }
    }

    private func loadExisting() {
        guard let wf = workflow else { return }
        name = wf.name
        desc = wf.desc
        steps = wf.orderedSteps.map { DraftStep(command: $0.command, delayAfter: $0.delayAfter) }
    }

    private func save() {
        let wf = workflow ?? Workflow()
        wf.name = name.trimmingCharacters(in: .whitespaces)
        wf.desc = desc
        // Rebuild steps
        for existing in wf.steps { modelContext.delete(existing) }
        wf.steps = []
        for (idx, draft) in steps.enumerated() {
            let s = WorkflowStep()
            s.command = draft.command.trimmingCharacters(in: .whitespaces)
            s.delayAfter = draft.delayAfter
            s.position = idx
            s.workflow = wf
            wf.steps.append(s)
            modelContext.insert(s)
        }
        if workflow == nil { modelContext.insert(wf) }
        try? modelContext.save()
        onSave?(wf)
        dismiss()
    }
}
```

- [ ] **Step 2: Create WorkflowListView**

```swift
// Sources/Mosaic/UI/Workflows/WorkflowListView.swift
import SwiftUI
import SwiftData

@MainActor
struct WorkflowListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Workflow.createdAt, order: .reverse) private var workflows: [Workflow]

    var onRun: ((Workflow) -> Void)?

    @State private var showForm = false
    @State private var editingWorkflow: Workflow?

    var body: some View {
        NavigationStack {
            Group {
                if workflows.isEmpty {
                    ContentUnavailableView(
                        "No Workflows",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Create a saved sequence of commands to run as a unit.")
                    )
                } else {
                    List {
                        ForEach(workflows) { wf in
                            WorkflowRow(workflow: wf) {
                                onRun?(wf)
                            } onEdit: {
                                editingWorkflow = wf
                            }
                        }
                        .onDelete { indexSet in
                            for i in indexSet { modelContext.delete(workflows[i]) }
                            try? modelContext.save()
                        }
                    }
                }
            }
            .navigationTitle("Workflows")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showForm = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showForm) {
                WorkflowFormView()
            }
            .sheet(item: $editingWorkflow) { wf in
                WorkflowFormView(workflow: wf)
            }
        }
    }
}

private struct WorkflowRow: View {
    let workflow: Workflow
    let onRun: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(workflow.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                if !workflow.desc.isEmpty {
                    Text(workflow.desc)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Text("\(workflow.steps.count) step\(workflow.steps.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onRun()
            }) {
                Image(systemName: "play.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.mosaicAccent)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 3: Build check**

```
xcodebuild build -scheme Mosaic -destination 'generic/platform=iOS Simulator' 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Sources/Mosaic/UI/Workflows/WorkflowListView.swift Sources/Mosaic/UI/Workflows/WorkflowFormView.swift
git commit -m "feat(workflows): add WorkflowListView and WorkflowFormView with CRUD and step reordering"
```

---

### Task 5: Wire Workflows into SessionView Toolbar

**Files:**
- Modify: `Sources/Mosaic/UI/Session/SessionView.swift`

- [ ] **Step 1: Add state and sheet**

In `SessionView`, add:

```swift
@State private var showWorkflows = false
```

In the body, add a `.sheet` alongside the existing sheets:

```swift
.sheet(isPresented: $showWorkflows) {
    WorkflowListView { workflow in
        showWorkflows = false
        Task { await session.runWorkflow(workflow) }
    }
}
```

- [ ] **Step 2: Add toolbar button**

In the `SessionView` body, add a `.toolbar` modifier:

```swift
.toolbar {
    ToolbarItem(placement: .topBarTrailing) {
        Button {
            showWorkflows = true
        } label: {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 15))
                .foregroundColor(.mosaicTextSec)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
```

If `SessionView` doesn't use a `NavigationStack` (it sits inside the tab bar layout), add the button to the `BreadcrumbBar` trailing area instead by adding a parameter:

```swift
// In BreadcrumbBar, add trailing content:
var trailingContent: AnyView = AnyView(EmptyView())
```

Then pass the button as `trailingContent` from `SessionView`. Choose whichever integration point results in the button being visible and reachable without conflicting with existing controls.

- [ ] **Step 3: Build + all tests**

```
xcodebuild test -scheme Mosaic -destination 'id=913B454F-493C-46DC-B2B4-63348DA39843' 2>&1 | grep -E "(Test Suite|passed|failed)" | tail -10
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/Mosaic/UI/Session/SessionView.swift
git commit -m "feat(workflows): add Workflows button to SessionView toolbar, runs workflow via session.runWorkflow"
```

---

### Task 6: RunWorkflowIntent (iOS Shortcuts)

**Files:**
- Create: `Sources/Mosaic/Shortcuts/RunWorkflowIntent.swift`
- Modify: `Tests/MosaicTests/WorkflowTests.swift`

- [ ] **Step 1: Create RunWorkflowIntent**

```swift
// Sources/Mosaic/Shortcuts/RunWorkflowIntent.swift
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

        guard let session = await SessionManager.shared.activeSession else {
            throw AppIntentError.noActiveSession
        }

        await session.runWorkflow(workflow)
        return .result()
    }
}

enum AppIntentError: Swift.Error, LocalizedError {
    case workflowNotFound(String)
    case noActiveSession

    var errorDescription: String? {
        switch self {
        case .workflowNotFound(let name): return "No workflow named "\(name)" found."
        case .noActiveSession: return "No active server session. Connect to a server first."
        }
    }
}
```

Note: if `AppIntentError` is already defined in `OpenServerIntent.swift`, extend it with the two new cases there instead of creating a duplicate enum here.

- [ ] **Step 2: Write test**

In `Tests/MosaicTests/WorkflowTests.swift`, add:

```swift
@Suite("RunWorkflowIntent")
struct RunWorkflowIntentTests {

    @Test func intentTitleIsCorrect() {
        #expect(RunWorkflowIntent.title.key == "Run Workflow")
    }

    @Test func workflowNotFoundErrorMessage() {
        let err = AppIntentError.workflowNotFound("deploy")
        #expect(err.errorDescription?.contains("deploy") == true)
    }

    @Test func noActiveSessionErrorMessage() {
        let err = AppIntentError.noActiveSession
        #expect(err.errorDescription?.contains("session") == true)
    }
}
```

- [ ] **Step 3: Build + test**

```
xcodebuild test -scheme Mosaic -destination 'id=913B454F-493C-46DC-B2B4-63348DA39843' -only-testing:MosaicTests/RunWorkflowIntentTests 2>&1 | tail -20
```

Expected: PASS (3 tests)

- [ ] **Step 4: Full build + all tests**

```
xcodebuild test -scheme Mosaic -destination 'id=913B454F-493C-46DC-B2B4-63348DA39843' 2>&1 | grep -E "(Test Suite|passed|failed)" | tail -10
```

Expected: all tests pass, total count ≥ previous + ~12

- [ ] **Step 5: Commit**

```bash
git add Sources/Mosaic/Shortcuts/RunWorkflowIntent.swift Tests/MosaicTests/WorkflowTests.swift
git commit -m "feat(workflows): add RunWorkflowIntent AppIntent for iOS Shortcuts integration"
```

---

## Self-Review

**Spec coverage:**
- ✅ Workflow @Model: name, description, steps, createdAt
- ✅ WorkflowStep @Model: command, delayAfter, position
- ✅ Stored in SwiftData alongside Connection (localConfig)
- ✅ `Session.runWorkflow(_:)` — sequential execution via existing `send()`
- ✅ WorkflowListView — browse/run/create
- ✅ WorkflowFormView — create/edit with step reordering
- ✅ Entry point in SessionView (toolbar button → sheet)
- ✅ `RunWorkflowIntent` following OpenServerIntent pattern
- ✅ CRUD: list, create, edit, delete

**Placeholder scan:** Task 5 Step 2 has a conditional note about toolbar vs BreadcrumbBar — this is a design decision point, not a placeholder. The code for both paths is described.

**Type consistency:** `Workflow.orderedSteps` defined in Task 1, used in `Session.runWorkflow` (Task 3), `WorkflowFormView.loadExisting()` (Task 4), and `WorkflowRow.steps.count` display (Task 4). `WorkflowStep.workflow: Workflow?` inverse relationship defined in Task 1, set in `WorkflowFormView.save()` (Task 4). `RunWorkflowIntent` uses same `Workflow` and `WorkflowStep` models from Task 1, same `SessionManager.shared.activeSession` pattern from `OpenServerIntent`.
