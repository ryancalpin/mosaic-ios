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
