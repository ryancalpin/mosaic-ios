# No-Code Renderer Builder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users create custom terminal output renderers via a form-based UI — no Swift code required — with live preview, export/import via `.mosaic-renderer` JSON files, and automatic registration into the rendering pipeline.

**Architecture:** A `CustomRenderer` SwiftData model stores the renderer definition (command pattern regex + extraction rules + layout choice) as persisted data. A `CustomRendererAdapter` struct wraps each model record and conforms to `OutputRenderer`, plugging into `RendererRegistry` transparently. The builder UI lives inside SettingsSheet as a dedicated `CustomRendererListView` + `RendererBuilderView` pair.

**Tech Stack:** Swift 5.9+, SwiftUI, SwiftData, NSRegularExpression, UniformTypeIdentifiers (UTType), ShareLink/ShareSheet for export, UIDocumentPickerViewController wrapped in SwiftUI for import.

---

## File Map

| Action | Path |
|--------|------|
| Create | `Sources/Mosaic/Models/CustomRenderer.swift` |
| Create | `Sources/Mosaic/Rendering/CustomRendererAdapter.swift` |
| Create | `Sources/Mosaic/UI/RendererBuilder/RendererBuilderView.swift` |
| Create | `Sources/Mosaic/UI/RendererBuilder/CustomRendererListView.swift` |
| Modify | `Sources/Mosaic/App/MosaicApp.swift` |
| Modify | `Sources/Mosaic/UI/Settings/SettingsSheet.swift` |
| Modify | `Sources/Mosaic/Rendering/RendererRegistry.swift` |

---

## Task 1 — `CustomRenderer` SwiftData Model

**File:** `Sources/Mosaic/Models/CustomRenderer.swift`

### What to build

- `@Model public final class CustomRenderer` with fields:
  - `id: UUID` — stable identifier, set in `init()`
  - `name: String` — user-chosen display name (e.g. "nginx access log")
  - `commandPattern: String` — regex matched against the command the user typed (e.g. `"^tail.*access.log"`)
  - `extractionRulesJSON: String` — JSON array of `ExtractionRule` structs
  - `layout: String` — raw value of `RendererLayout` enum (`"keyValue"`, `"badgeRow"`, `"table"`)
  - `createdAt: Date`

- `public enum RendererLayout: String, CaseIterable, Codable` with cases:
  - `keyValue` — label: value rows (default)
  - `badgeRow` — colored pill badges in a wrapping HStack
  - `table` — fixed-width columns

- `public struct ExtractionRule: Codable, Identifiable, Sendable`:
  - `id: UUID`
  - `label: String` — column / badge label shown in the rendered view
  - `pattern: String` — NSRegularExpression pattern (must include at least one capture group)
  - `captureGroup: Int` — which capture group to extract (1-indexed, default 1)

- Computed property `var extractionRules: [ExtractionRule]` — decodes `extractionRulesJSON` via `JSONDecoder`; returns `[]` on failure (never throws in view code).

- Computed property `var rendererLayout: RendererLayout` — parses `layout` rawValue; defaults to `.keyValue`.

- Designated `init` (no convenience — follow SwiftData pattern):
  ```swift
  public init(name: String, commandPattern: String, layout: RendererLayout = .keyValue)
  ```
  Sets `id = UUID()`, `extractionRulesJSON = "[]"`, `createdAt = Date()`.

- Helper `func setExtractionRules(_ rules: [ExtractionRule])` — encodes via `JSONEncoder` and writes to `extractionRulesJSON`.

### Steps

- [ ] Create `Sources/Mosaic/Models/CustomRenderer.swift` with the full implementation above
- [ ] Build: `xcodebuild build -scheme Mosaic -destination 'generic/platform=iOS Simulator' 2>&1 | tail -20`
- [ ] Confirm `** BUILD SUCCEEDED **`
- [ ] Commit: `feat: add CustomRenderer SwiftData model with ExtractionRule + RendererLayout`

---

## Task 2 — `CustomRendererAdapter` + Inline Layout Views

**File:** `Sources/Mosaic/Rendering/CustomRendererAdapter.swift`

### What to build

`CustomRendererAdapter` conforms to `OutputRenderer`. It must be `@MainActor` because the protocol is `@MainActor`. It wraps a `CustomRenderer` model instance captured at registration time (not re-fetched on every call — the registry holds strong references).

**`canRender(command:output:)`**
- Compile `model.commandPattern` with `NSRegularExpression`. Cache the compiled regex in a lazy private var on first use.
- Return `true` if the regex matches anywhere in `command`. If the pattern is empty or fails to compile, return `false`.
- Never throw; catch errors and return `false`.

**`parse(command:output:)`**
- For each `ExtractionRule` in `model.extractionRules`, run its pattern as an `NSRegularExpression` against `output`.
- Extract the text of capture group `rule.captureGroup` from the first match.
- Collect results as `[(label: String, value: String)]` — skip rules with no match.
- If zero rules matched, return `nil` (fall through to raw).
- Return `CustomRendererData(fields: results, layout: model.rendererLayout)`.

**`view(for:)`**
- Cast `data` to `CustomRendererData`.
- Switch on `data.layout`:
  - `.keyValue` → `AnyView(KeyValueLayoutView(fields: data.fields))`
  - `.badgeRow` → `AnyView(BadgeRowLayoutView(fields: data.fields))`
  - `.table` → `AnyView(TableLayoutView(fields: data.fields))`

**`CustomRendererData: RendererData`**
```swift
public struct CustomRendererData: RendererData {
    public let fields: [(label: String, value: String)]
    public let layout: RendererLayout
}
```
Note: `RendererData` requires `Sendable`. Use `@unchecked Sendable` on the struct since tuple arrays aren't auto-Sendable but are safe here (all strings, immutable after construction).

**Inline view types** (keep them small, in the same file):

`KeyValueLayoutView` — `VStack(alignment: .leading, spacing: 8)` of `HStack` rows:
- Label: JetBrains Mono 9pt `.bold`, `Color.mosaicTextSec`, uppercased, min-width 90pt, leading aligned
- Value: JetBrains Mono 11pt, `Color.mosaicTextPri`
- Container: `mosaicSurface1` background, 12pt corner radius, 12/10 h/v padding, `mosaicBorder` stroke

`BadgeRowLayoutView` — `FlowLayout` (manual `ViewThatFits`-based or simple wrapping via `LazyVGrid` with `.adaptive(minimum: 80)`) of pill badges:
- Each badge: label + value in one chip, JetBrains Mono 9pt, `mosaicAccent` foreground, `mosaicSurface2` background, 6pt corner radius, 8/4 h/v padding

`TableLayoutView` — `VStack(spacing: 0)` with a header row and data rows:
- Divider between header and data, `mosaicBorder` color
- Header: labels in `HStack`, JetBrains Mono 9pt `.bold`, `mosaicTextSec`
- Data row: values in `HStack`, JetBrains Mono 11pt, `mosaicTextPri`
- Alternating row background: even rows `mosaicSurface1`, odd rows `mosaicSurface2`

### Steps

- [ ] Create `Sources/Mosaic/Rendering/CustomRendererAdapter.swift`
- [ ] Build and confirm `** BUILD SUCCEEDED **`
- [ ] Commit: `feat: add CustomRendererAdapter with key-value, badge-row, and table layout views`

---

## Task 3 — `CustomRendererListView`

**File:** `Sources/Mosaic/UI/RendererBuilder/CustomRendererListView.swift`

### What to build

A SwiftUI view presented via `NavigationLink` from `SettingsSheet`. It is the management surface for all custom renderers.

**Data:**
```swift
@Query(sort: \CustomRenderer.createdAt, order: .forward) private var renderers: [CustomRenderer]
@Environment(\.modelContext) private var context
```

**Layout:**
- `NavigationStack` title "Custom Renderers"
- If `renderers.isEmpty`: empty state view — SF Symbol `paintbrush.pointed.fill`, message "No custom renderers yet.", subtext "Tap + to build your first renderer."
- Otherwise: `List` of rows. Each row:
  - Leading: renderer `name` in SF Pro `.body`, `mosaicTextPri`
  - Trailing: layout badge — small text pill showing `renderer.rendererLayout.rawValue`, JetBrains Mono 8pt, `mosaicAccent`
  - Tap row → sheet with `RendererBuilderView(renderer: renderer, onSave: { ... })`
  - `.swipeActions(edge: .trailing)`: destructive "Delete" button that calls `context.delete(renderer)` then `registerAllCustomRenderers()`
  - `.swipeActions(edge: .leading)`: non-destructive "Export" button (share icon)

**Toolbar:**
- `.navigationBarItems(trailing: Button { showBuilder = true } label: { Image(systemName: "plus") }.foregroundStyle(Color.mosaicAccent))`
- Sheet: `RendererBuilderView(renderer: nil, onSave: { showBuilder = false; registerAllCustomRenderers() })`

**Export:**
- `exportRenderer(_ r: CustomRenderer)` — encodes the model fields (id, name, commandPattern, extractionRulesJSON, layout) into a `CustomRendererExport` Codable struct, then to JSON `Data`.
- Wraps in a `ShareLink(item: exportData, preview: SharePreview(r.name))` using `Transferable` on a small wrapper type, or uses `UIActivityViewController` via a `UIViewControllerRepresentable`.
- File extension: `.mosaic-renderer`, UTType identifier: `com.mosaic.renderer` (declared in Info.plist in Task 5).

**Import:**
- "Import" toolbar button (secondary, leading side) → presents `DocumentPickerView` (UIDocumentPickerViewController wrapped in SwiftUI) filtered to `com.mosaic.renderer` UTType.
- On pick: decode JSON → create `CustomRenderer` → insert into context → `registerAllCustomRenderers()`.
- Show error alert if decoding fails.

**`registerAllCustomRenderers()`** — private helper that calls `RendererRegistry.shared.registerCustomRenderers(from: context)`.

**Codable export struct:**
```swift
struct CustomRendererExport: Codable {
    var id: UUID
    var name: String
    var commandPattern: String
    var extractionRulesJSON: String
    var layout: String
    var createdAt: Date
}
```

**`DocumentPickerView`** — `UIViewControllerRepresentable` wrapping `UIDocumentPickerViewController`:
```swift
struct DocumentPickerView: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    // makeUIViewController: UIDocumentPickerViewController(forOpeningContentTypes: [UTType("com.mosaic.renderer")!])
    // Coordinator: UIDocumentPickerDelegate, calls onPick with urls.first
}
```

### Steps

- [ ] Create `Sources/Mosaic/UI/RendererBuilder/CustomRendererListView.swift`
- [ ] Build and confirm `** BUILD SUCCEEDED **`
- [ ] Commit: `feat: add CustomRendererListView with CRUD, export, and import`

---

## Task 4 — `RendererBuilderView` (Create/Edit Form with Live Preview)

**File:** `Sources/Mosaic/UI/RendererBuilder/RendererBuilderView.swift`

### What to build

The full create/edit form. Presented as a sheet from `CustomRendererListView`.

**Signature:**
```swift
struct RendererBuilderView: View {
    var renderer: CustomRenderer?  // nil = create new
    var onSave: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
}
```

**Local state:**
```swift
@State private var name: String
@State private var commandPattern: String
@State private var layout: RendererLayout
@State private var rules: [ExtractionRule]
@State private var sampleOutput: String
@State private var patternError: String?
```
Initialized from `renderer` if non-nil, otherwise empty defaults.

**Form structure** — `Form` inside `NavigationStack`:

**Section "RENDERER NAME":**
- `TextField("e.g. nginx access log", text: $name)`
- JetBrains Mono input font, `mosaicTextPri` color

**Section "COMMAND PATTERN":**
- `TextField("regex, e.g. ^tail.*access\\.log", text: $commandPattern)`
- `.onChange(of: commandPattern)` → validate with `NSRegularExpression`; set `patternError` if invalid
- If `patternError != nil`: show inline red error text below the field: `Text(patternError!).foregroundStyle(Color.mosaicRed).font(.caption)`

**Section "LAYOUT":**
- `Picker("Layout", selection: $layout)` with `.segmented` style
- Options: Key-Value / Badge Row / Table (from `RendererLayout.allCases`)

**Section "EXTRACTION RULES":**
- `ForEach($rules)` — each rule renders:
  - `TextField("Label", text: $rule.label)` — SF Pro `.body`
  - `TextField("Pattern (regex)", text: $rule.pattern)` — JetBrains Mono
  - `Stepper("Group: \(rule.captureGroup)", value: $rule.captureGroup, in: 1...9)`
- `.onDelete(perform: deleteRule)` — enables swipe to delete
- Add-rule row at bottom: `Button("+ Add Rule") { rules.append(ExtractionRule(...)) }` in `mosaicAccent`
- Minimum 1 rule enforced: if `rules.isEmpty`, show inline hint "Add at least one extraction rule."

**Section "LIVE PREVIEW":**
- `TextEditor(text: $sampleOutput)` — monospace, 6-line min height, `mosaicBg` background, labelled "Paste sample output here…"
- Below: `previewResult` computed property — constructs a temporary `CustomRenderer`, wraps in `CustomRendererAdapter`, calls `adapter.parse(command: "", output: sampleOutput)`, then renders via `adapter.view(for:)`. If parse returns nil: show `Text("No match — rules didn't extract any values.").foregroundStyle(.secondary)`.
- Preview updates reactively via `.onChange(of: sampleOutput)` + `.onChange(of: rules)`.

**Toolbar:**
- Leading: `Button("Cancel") { dismiss() }`
- Trailing: `Button("Save") { save() }.disabled(!isValid)`
  - `isValid`: name non-empty, commandPattern non-empty and compiles, at least 1 rule with non-empty label and pattern

**`save()` function:**
```swift
private func save() {
    if let existing = renderer {
        existing.name = name
        existing.commandPattern = commandPattern
        existing.layout = layout.rawValue
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
```

**Styling:**
- All section headers: JetBrains Mono 8pt `.bold`, letter spacing 0.4, `mosaicTextSec` color, uppercased
- Form background: `mosaicBg`
- `.navigationTitle(renderer == nil ? "New Renderer" : "Edit Renderer")`
- `.navigationBarTitleDisplayMode(.inline)`

### Steps

- [ ] Create `Sources/Mosaic/UI/RendererBuilder/RendererBuilderView.swift`
- [ ] Build and confirm `** BUILD SUCCEEDED **`
- [ ] Commit: `feat: add RendererBuilderView with live preview and validation`

---

## Task 5 — Wire into App, Settings, and Registry

**Files modified:**
- `Sources/Mosaic/App/MosaicApp.swift`
- `Sources/Mosaic/UI/Settings/SettingsSheet.swift`
- `Sources/Mosaic/Rendering/RendererRegistry.swift`

### MosaicApp.swift

Add `CustomRenderer.self` to the `ModelContainer` schema:

```swift
container = try ModelContainer(
    for: Connection.self, CustomRenderer.self,
    configurations: config
)
```

After the container is created, call:
```swift
let ctx = ModelContext(container)
RendererRegistry.shared.registerCustomRenderers(from: ctx)
```

This runs synchronously at launch before the first render call, ensuring custom renderers are registered before any command output arrives.

### RendererRegistry.swift

Add a new public method:

```swift
/// Fetches all CustomRenderer records from the given context and registers
/// a CustomRendererAdapter for each. Clears any previously registered custom
/// adapters first so this is safe to call on every CRUD mutation.
public func registerCustomRenderers(from context: ModelContext) {
    // Remove previously registered custom adapters
    renderers.removeAll { $0.id.hasPrefix("custom.") }

    let all = (try? context.fetch(FetchDescriptor<CustomRenderer>())) ?? []
    for model in all {
        let adapter = CustomRendererAdapter(model: model)
        register(adapter)
    }
}
```

`CustomRendererAdapter.id` must be `"custom.\(model.id.uuidString)"` so the prefix filter works correctly.

### SettingsSheet.swift

Add a "CUSTOM RENDERERS" section inside the `Form`, below the "Display" section:

```swift
Section("Custom Renderers") {
    NavigationLink("Manage Renderers") {
        CustomRendererListView()
    }
    .foregroundStyle(Color.mosaicAccent)
}
```

The existing `NavigationStack` wrapper in `SettingsSheet` already provides the navigation environment needed for `NavigationLink` to work.

### Info.plist — UTType declaration

Add a `UTExportedTypeDeclarations` entry for `com.mosaic.renderer` so iOS recognizes `.mosaic-renderer` files. In the project's `Info.plist`:

```xml
<key>UTExportedTypeDeclarations</key>
<array>
    <dict>
        <key>UTTypeIdentifier</key>
        <string>com.mosaic.renderer</string>
        <key>UTTypeDescription</key>
        <string>Mosaic Renderer Definition</string>
        <key>UTTypeConformsTo</key>
        <array>
            <string>public.data</string>
            <string>public.json</string>
        </array>
        <key>UTTypeTagSpecification</key>
        <dict>
            <key>public.filename-extension</key>
            <array>
                <string>mosaic-renderer</string>
            </array>
        </dict>
    </dict>
</array>
```

Also add `UTImportedTypeDeclarations` with the same entry so the app can open files shared from other devices.

### Steps

- [ ] Modify `MosaicApp.swift` — add `CustomRenderer.self` to container schema and call `registerCustomRenderers`
- [ ] Modify `RendererRegistry.swift` — add `registerCustomRenderers(from:)` method
- [ ] Modify `SettingsSheet.swift` — add "Custom Renderers" section with NavigationLink
- [ ] Modify `Info.plist` — add UTExportedTypeDeclarations and UTImportedTypeDeclarations for `com.mosaic.renderer`
- [ ] Build: `xcodebuild build -scheme Mosaic -destination 'generic/platform=iOS Simulator' 2>&1 | tail -20`
- [ ] Confirm `** BUILD SUCCEEDED **`
- [ ] Run tests: `xcodebuild test -scheme Mosaic -destination 'platform=iOS Simulator,name=iPhone 15 Pro' 2>&1 | tail -20`
- [ ] Confirm all tests pass (report count)
- [ ] Boot simulator and take screenshot of Settings → Custom Renderers section to visually verify placement
- [ ] Commit: `feat: wire CustomRenderer into ModelContainer, RendererRegistry, and SettingsSheet`

---

## Acceptance Criteria

Before the plan is considered complete, ALL of the following must be true:

- [ ] `** BUILD SUCCEEDED **` with zero warnings added by this feature
- [ ] All existing tests still pass (no regressions)
- [ ] Settings sheet shows "Custom Renderers" section with working NavigationLink
- [ ] Tapping "+" in CustomRendererListView opens RendererBuilderView
- [ ] Filling out name + command pattern + at least one rule enables the Save button
- [ ] Saving a renderer persists it to SwiftData and it appears in the list
- [ ] Live preview in RendererBuilderView updates within one keystroke of editing sample output
- [ ] Swipe-to-delete removes a renderer from the list and from the registry
- [ ] Export produces valid JSON that can be re-imported on the same device
- [ ] A custom renderer with a valid `commandPattern` actually triggers in SessionView for a matching command
- [ ] Simulator screenshot confirms UI renders correctly on iPhone 15 Pro (large) and iPhone SE (small)
- [ ] No hardcoded font sizes — all UI text uses `.body`, `.caption`, `.headline`, or explicit `Font.custom` calls with design-system sizes
- [ ] Tap targets for + button, delete, export, and each rule add/remove are minimum 44×44 pt

---

## Dependencies and Notes

- `ExtractionRule.id` must be `UUID` so `ForEach($rules)` works with SwiftUI's binding foreach. Generate a new UUID in the `ExtractionRule` memberwise init.
- `CustomRendererAdapter` must hold a strong reference to the `CustomRenderer` model. Do not use `@ModelActor` or detach — the adapter is registered on `@MainActor` and used only from `@MainActor` call sites.
- The registry's `registerCustomRenderers` call at app launch must happen before the first `WindowGroup` render. In `MosaicApp.init()` — not in `.onAppear`.
- `RendererLayout.allCases` is needed for the `Picker` — ensure `CaseIterable` conformance is on the enum.
- The `table` layout view (`TableLayoutView`) should handle the case of a single field gracefully (showing it as a single-column table is fine).
- Do NOT use `@Query` inside `CustomRendererAdapter` — the adapter is not a View. It receives data at parse time from the model captured at registration.
- ShareLink requires the shared item to conform to `Transferable`. Wrap the JSON `Data` in a `CustomRendererFile: Transferable` struct with a `.data` representation and contentType `UTType("com.mosaic.renderer")!`. This is simpler than UIActivityViewController and stays within SwiftUI.
