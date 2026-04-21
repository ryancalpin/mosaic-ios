import SwiftUI

@MainActor
struct RendererBuilderView: View {
    var renderer: CustomRenderer?
    var onSave: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss

    @State private var name:           String
    @State private var commandPattern: String
    @State private var layout:         RendererLayout
    @State private var rules:          [ExtractionRule]
    @State private var sampleOutput:   String
    @State private var patternError:   String?

    init(renderer: CustomRenderer?, onSave: @escaping () -> Void) {
        self.renderer = renderer
        self.onSave   = onSave
        _name           = State(initialValue: renderer?.name ?? "")
        _commandPattern = State(initialValue: renderer?.commandPattern ?? "")
        _layout         = State(initialValue: renderer?.rendererLayout ?? .keyValue)
        _rules          = State(initialValue: renderer?.extractionRules ?? [])
        _sampleOutput   = State(initialValue: "")
        _patternError   = State(initialValue: nil)
    }

    private var isValid: Bool {
        !name.isEmpty
        && !commandPattern.isEmpty
        && patternError == nil
        && !rules.isEmpty
        && rules.allSatisfy { !$0.label.isEmpty && !$0.pattern.isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. nginx access log", text: $name)
                        .font(.custom("JetBrains Mono", size: 12))
                        .foregroundStyle(Color.mosaicTextPri)
                } header: {
                    sectionHeader("Renderer Name")
                }

                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("regex, e.g. ^tail.*access\\.log", text: $commandPattern)
                            .font(.custom("JetBrains Mono", size: 11))
                            .foregroundStyle(Color.mosaicTextPri)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onChange(of: commandPattern) { validatePattern() }
                        if let err = patternError {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(Color.mosaicRed)
                        }
                    }
                } header: {
                    sectionHeader("Command Pattern")
                }

                Section {
                    Picker("Layout", selection: $layout) {
                        ForEach(RendererLayout.allCases, id: \.self) { l in
                            Text(l.rawValue).tag(l)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    sectionHeader("Layout")
                }

                Section {
                    ForEach($rules) { $rule in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Label", text: $rule.label)
                                .font(.body)
                            TextField("Pattern (regex)", text: $rule.pattern)
                                .font(.custom("JetBrains Mono", size: 11))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            Stepper("Capture group: \(rule.captureGroup)", value: $rule.captureGroup, in: 1...9)
                                .font(.custom("JetBrains Mono", size: 11))
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete(perform: deleteRule)

                    Button("+ Add Rule") {
                        rules.append(ExtractionRule())
                    }
                    .foregroundStyle(Color.mosaicAccent)
                    .font(.custom("JetBrains Mono", size: 11))

                    if rules.isEmpty {
                        Text("Add at least one extraction rule.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    sectionHeader("Extraction Rules")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        TextEditor(text: $sampleOutput)
                            .font(.custom("JetBrains Mono", size: 11))
                            .frame(minHeight: 100)
                            .foregroundStyle(Color.mosaicTextPri)
                            .scrollContentBackground(.hidden)
                            .background(Color.mosaicBg)
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                        previewResult
                    }
                } header: {
                    sectionHeader("Live Preview")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.mosaicBg)
            .navigationTitle(renderer == nil ? "New Renderer" : "Edit Renderer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.mosaicTextSec)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { save() }
                        .font(.custom("JetBrains Mono", size: 12).weight(.bold))
                        .foregroundStyle(isValid ? Color.mosaicAccent : Color.mosaicTextMut)
                        .disabled(!isValid)
                }
            }
        }
    }

    @ViewBuilder
    private var previewResult: some View {
        if sampleOutput.isEmpty {
            Text("Paste sample output above to see a preview.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            RendererPreviewContainer(
                name: name,
                commandPattern: commandPattern,
                layout: layout,
                rules: rules,
                sampleOutput: sampleOutput
            )
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.custom("JetBrains Mono", size: 8).weight(.bold))
            .kerning(0.4)
            .foregroundStyle(Color.mosaicTextSec)
    }

    private func deleteRule(at offsets: IndexSet) {
        rules.remove(atOffsets: offsets)
    }

    private func validatePattern() {
        guard !commandPattern.isEmpty else { patternError = nil; return }
        do {
            _ = try NSRegularExpression(pattern: commandPattern)
            patternError = nil
        } catch {
            patternError = "Invalid regex: \(error.localizedDescription)"
        }
    }

    private func save() {
        if let existing = renderer {
            existing.name           = name
            existing.commandPattern = commandPattern
            existing.layout         = layout.rawValue
            existing.setExtractionRules(rules)
        } else {
            let new = CustomRenderer(name: name, commandPattern: commandPattern, layout: layout)
            new.setExtractionRules(rules)
            context.insert(new)
        }
        try? context.save()
        onSave()
        dismiss()
    }
}

// MARK: - RendererPreviewContainer

/// Helper view that builds the adapter outside a @ViewBuilder closure
/// so we can call setExtractionRules (a Void statement) without issue.
@MainActor
private struct RendererPreviewContainer: View {
    let name: String
    let commandPattern: String
    let layout: RendererLayout
    let rules: [ExtractionRule]
    let sampleOutput: String

    var body: some View {
        let tempModel = CustomRenderer(name: name, commandPattern: commandPattern, layout: layout)
        tempModel.setExtractionRules(rules)
        let adapter = CustomRendererAdapter(model: tempModel)
        if let data = adapter.parse(command: "", output: sampleOutput) {
            return AnyView(adapter.view(for: data))
        } else {
            return AnyView(
                Text("No match — rules didn't extract any values.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            )
        }
    }
}
