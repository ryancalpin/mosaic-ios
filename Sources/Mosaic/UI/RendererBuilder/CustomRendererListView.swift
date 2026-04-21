import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - CustomRendererExport

private struct CustomRendererExport: Codable {
    var id: UUID
    var name: String
    var commandPattern: String
    var extractionRulesJSON: String
    var layout: String
    var createdAt: Date
}

// MARK: - ExportableRenderer (Transferable)

private struct ExportableRenderer: Transferable {
    let data: Data
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(contentType: UTType(mosaicRendererUTI) ?? .data) { r in
            r.data
        } importing: { data in
            ExportableRenderer(data: data, name: "imported")
        }
    }
}

private let mosaicRendererUTI = "com.mosaic.renderer"

// MARK: - CustomRendererListView

@MainActor
struct CustomRendererListView: View {
    @Query(sort: \CustomRenderer.createdAt, order: .forward) private var renderers: [CustomRenderer]
    @Environment(\.modelContext) private var context
    @State private var showBuilder      = false
    @State private var editingRenderer: CustomRenderer? = nil
    @State private var showImportPicker = false
    @State private var importError: String? = nil

    var body: some View {
        ZStack {
            Color.mosaicBg.ignoresSafeArea()
            if renderers.isEmpty {
                emptyState
            } else {
                rendererList
            }
        }
        .navigationTitle("Custom Renderers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    showImportPicker = true
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .foregroundStyle(Color.mosaicTextSec)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showBuilder = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(Color.mosaicAccent)
                }
            }
        }
        .sheet(isPresented: $showBuilder) {
            RendererBuilderView(renderer: nil) {
                showBuilder = false
                registerAll()
            }
        }
        .sheet(item: $editingRenderer) { r in
            RendererBuilderView(renderer: r) {
                editingRenderer = nil
                registerAll()
            }
        }
        .sheet(isPresented: $showImportPicker) {
            DocumentPickerView { url in
                importRenderer(from: url)
                showImportPicker = false
            }
        }
        .alert("Import Failed", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "paintbrush.pointed.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.mosaicTextSec)
            Text("No custom renderers yet.")
                .font(.custom("JetBrains Mono", size: 14))
                .foregroundStyle(Color.mosaicTextSec)
            Text("Tap + to build your first renderer.")
                .font(.custom("JetBrains Mono", size: 11))
                .foregroundStyle(Color.mosaicTextMut)
        }
    }

    private var rendererList: some View {
        List {
            ForEach(renderers) { r in
                Button { editingRenderer = r } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.name)
                                .font(.body)
                                .foregroundStyle(Color.mosaicTextPri)
                            Text(r.commandPattern)
                                .font(.custom("JetBrains Mono", size: 9))
                                .foregroundStyle(Color.mosaicTextSec)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(r.rendererLayout.rawValue)
                            .font(.custom("JetBrains Mono", size: 8))
                            .foregroundStyle(Color.mosaicAccent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.mosaicAccent.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.mosaicSurface1)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        context.delete(r)
                        try? context.save()
                        registerAll()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    if let exportData = makeExportData(r) {
                        ShareLink(
                            item: ExportableRenderer(data: exportData, name: r.name),
                            preview: SharePreview(r.name)
                        ) {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        .tint(Color.mosaicAccent)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func makeExportData(_ r: CustomRenderer) -> Data? {
        let export = CustomRendererExport(
            id: r.id, name: r.name, commandPattern: r.commandPattern,
            extractionRulesJSON: r.extractionRulesJSON, layout: r.layout, createdAt: r.createdAt
        )
        return try? JSONEncoder().encode(export)
    }

    private func importRenderer(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            importError = "Cannot access file."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let data = try Data(contentsOf: url)
            let export = try JSONDecoder().decode(CustomRendererExport.self, from: data)
            let r = CustomRenderer(name: export.name, commandPattern: export.commandPattern,
                                   layout: RendererLayout(rawValue: export.layout) ?? .keyValue)
            r.extractionRulesJSON = export.extractionRulesJSON
            context.insert(r)
            try context.save()
            registerAll()
        } catch {
            importError = "Failed to import: \(error.localizedDescription)"
        }
    }

    private func registerAll() {
        RendererRegistry.shared.registerCustomRenderers(from: context)
    }
}

// MARK: - DocumentPickerView

struct DocumentPickerView: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [UTType(mosaicRendererUTI) ?? .data]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}
