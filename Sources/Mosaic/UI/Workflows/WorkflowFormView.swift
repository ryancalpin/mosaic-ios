// Sources/Mosaic/UI/Workflows/WorkflowFormView.swift
import SwiftUI
import SwiftData

@MainActor
struct WorkflowFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

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
        for existing in wf.steps { modelContext.delete(existing) }
        wf.steps = []
        let nonEmptySteps = steps.filter { !$0.command.trimmingCharacters(in: .whitespaces).isEmpty }
        for (idx, draft) in nonEmptySteps.enumerated() {
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
