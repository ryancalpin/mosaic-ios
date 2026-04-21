# Power User Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a persistent settings system covering dark/light/system theme, terminal font size, output density, native renderer toggle, and timestamp display — all accessible via a gear icon in the tab bar.

**Architecture:** A singleton `AppSettings` (`@Observable`) stores preferences in `UserDefaults` and is injected into the SwiftUI environment at the root. Color palette becomes adaptive dark/light using `UIColor` dynamic providers. Four environment keys propagate per-view settings (font size, density, native renderers, timestamps) from `RootView` down to consuming views without threading the values through every initializer.

**Tech Stack:** Swift 5.9, SwiftUI, `@Observable`, `UserDefaults`, `UIColor` dynamic color providers, SwiftUI `EnvironmentKey`

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `Sources/Mosaic/Settings/AppSettings.swift` | `AppTheme`, `OutputDensity` enums + `AppSettings` singleton |
| Create | `Sources/Mosaic/Settings/TerminalEnvironment.swift` | Four `EnvironmentKey` definitions + `EnvironmentValues` extensions |
| Create | `Sources/Mosaic/UI/Settings/SettingsSheet.swift` | Settings sheet UI |
| Modify | `Sources/Mosaic/Extensions/Color+Hex.swift` | Add `UIColor(hex:)` initializer |
| Modify | `Sources/Mosaic/Extensions/Color+Mosaic.swift` | Replace static hex constants with adaptive dark/light colors |
| Modify | `Sources/Mosaic/UI/Session/OutputBlockView.swift` | Read `terminalFontSize`, `showNativeRenderers`, `showTimestamps`, `outputDensity` from environment |
| Modify | `Sources/Mosaic/UI/Input/SmartInputBar.swift` | Read `terminalFontSize` from environment for text field |
| Modify | `Sources/Mosaic/UI/TabBar/TabBarView.swift` | Add gear button at trailing edge (outside ScrollView) |
| Modify | `Sources/Mosaic/UI/RootView.swift` | Inject `AppSettings` environment, `preferredColorScheme`, show `SettingsSheet` |

---

### Task 1: AppSettings model

**Files:**
- Create: `Sources/Mosaic/Settings/AppSettings.swift`

- [ ] **Step 1: Create the file**

```swift
// Sources/Mosaic/Settings/AppSettings.swift
import SwiftUI

// MARK: - Enums

enum AppTheme: String, CaseIterable {
    case dark, light, system

    var colorScheme: ColorScheme? {
        switch self {
        case .dark:   return .dark
        case .light:  return .light
        case .system: return nil
        }
    }

    var label: String { rawValue.capitalized }
}

enum OutputDensity: String, CaseIterable {
    case compact, standard, spacious

    var verticalPadding: CGFloat {
        switch self {
        case .compact:  return 6
        case .standard: return 10
        case .spacious: return 16
        }
    }

    var label: String { rawValue.capitalized }
}

// MARK: - AppSettings

@Observable
final class AppSettings {
    static let shared = AppSettings()

    var theme: AppTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "mosaic.theme") }
    }
    var terminalFontSize: Double {
        didSet { UserDefaults.standard.set(terminalFontSize, forKey: "mosaic.fontSize") }
    }
    var outputDensity: OutputDensity {
        didSet { UserDefaults.standard.set(outputDensity.rawValue, forKey: "mosaic.density") }
    }
    var showNativeRenderers: Bool {
        didSet { UserDefaults.standard.set(showNativeRenderers, forKey: "mosaic.nativeRenderers") }
    }
    var showTimestamps: Bool {
        didSet { UserDefaults.standard.set(showTimestamps, forKey: "mosaic.timestamps") }
    }

    private init() {
        let ud = UserDefaults.standard
        theme            = AppTheme(rawValue: ud.string(forKey: "mosaic.theme") ?? "") ?? .dark
        let size         = ud.double(forKey: "mosaic.fontSize")
        terminalFontSize = size > 0 ? size : 13.0
        outputDensity    = OutputDensity(rawValue: ud.string(forKey: "mosaic.density") ?? "") ?? .standard
        showNativeRenderers = ud.object(forKey: "mosaic.nativeRenderers") as? Bool ?? true
        showTimestamps   = ud.bool(forKey: "mosaic.timestamps")
    }
}
```

- [ ] **Step 2: Build to confirm no compile errors**

Run: `xcodebuild build -scheme Mosaic -destination 'generic/platform=iOS Simulator' 2>&1 | grep -E 'error:|BUILD'`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Sources/Mosaic/Settings/AppSettings.swift
git commit -m "feat: AppSettings model with UserDefaults persistence"
```

---

### Task 2: UIColor hex init + adaptive color palette

**Files:**
- Modify: `Sources/Mosaic/Extensions/Color+Hex.swift`
- Modify: `Sources/Mosaic/Extensions/Color+Mosaic.swift`

- [ ] **Step 1: Add `UIColor(hex:)` initializer to `Color+Hex.swift`**

The existing file only has `Color(hex:)`. Append a `UIColor` extension so `Color+Mosaic.swift` can construct adaptive colors.

Replace the entire file content with:

```swift
// Sources/Mosaic/Extensions/Color+Hex.swift
import SwiftUI

extension Color {
    init(hex: String) {
        var hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        guard scanner.scanHexInt64(&rgb) else {
            self.init(red: 0.5, green: 0.5, blue: 0.5)
            return
        }
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >>  8) & 0xFF) / 255.0
        let b = Double( rgb        & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

extension UIColor {
    convenience init(hex: String) {
        var hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        guard scanner.scanHexInt64(&rgb) else {
            self.init(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
            return
        }
        let r = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let g = CGFloat((rgb >>  8) & 0xFF) / 255.0
        let b = CGFloat( rgb        & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}
```

- [ ] **Step 2: Rewrite `Color+Mosaic.swift` with adaptive dark/light pairs**

The `adaptive` function uses `UIColor`'s dynamic color provider — when `.preferredColorScheme` overrides the root, the `userInterfaceStyle` in the trait collection matches the user's chosen theme.

Replace the entire file content with:

```swift
// Sources/Mosaic/Extensions/Color+Mosaic.swift
import SwiftUI

// Returns a Color that automatically switches between dark and light hex values
// based on the effective color scheme (driven by .preferredColorScheme at the root).
private func adaptive(dark: String, light: String) -> Color {
    Color(UIColor { traits in
        UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
    })
}

extension Color {
    // Backgrounds
    static let mosaicBg       = adaptive(dark: "#09090B", light: "#F7F7FA")
    static let mosaicSurface1 = adaptive(dark: "#111115", light: "#EDEDF2")
    static let mosaicSurface2 = adaptive(dark: "#17171C", light: "#E4E4EB")
    static let mosaicBorder   = adaptive(dark: "#1E1E26", light: "#CECEDA")

    // Accent / protocol colors — unchanged across themes
    static let mosaicAccent   = Color(hex: "#00D4AA")
    static let mosaicBlue     = Color(hex: "#4A9EFF")
    static let mosaicPurple   = Color(hex: "#A78BFA")

    // Text
    static let mosaicTextPri  = adaptive(dark: "#D8E4F0", light: "#1A1E2E")
    static let mosaicTextSec  = adaptive(dark: "#3A4A58", light: "#607084")
    static let mosaicTextMut  = adaptive(dark: "#1E2830", light: "#C0CAD4")

    // Semantic
    static let mosaicGreen    = Color(hex: "#3DFF8F")
    static let mosaicYellow   = Color(hex: "#FFD060")
    static let mosaicRed      = Color(hex: "#FF4D6A")
    static let mosaicWarn     = Color(hex: "#FFB020")
}
```

- [ ] **Step 3: Build**

Run: `xcodebuild build -scheme Mosaic -destination 'generic/platform=iOS Simulator' 2>&1 | grep -E 'error:|BUILD'`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Sources/Mosaic/Extensions/Color+Hex.swift Sources/Mosaic/Extensions/Color+Mosaic.swift
git commit -m "feat: adaptive dark/light color palette via UIColor dynamic provider"
```

---

### Task 3: Environment keys

**Files:**
- Create: `Sources/Mosaic/Settings/TerminalEnvironment.swift`

- [ ] **Step 1: Create the file**

```swift
// Sources/Mosaic/Settings/TerminalEnvironment.swift
import SwiftUI

// MARK: - TerminalFontSize

private struct TerminalFontSizeKey: EnvironmentKey {
    static let defaultValue: Double = 13.0
}

// MARK: - OutputDensity

private struct OutputDensityKey: EnvironmentKey {
    static let defaultValue: OutputDensity = .standard
}

// MARK: - ShowNativeRenderers

private struct ShowNativeRenderersKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

// MARK: - ShowTimestamps

private struct ShowTimestampsKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

// MARK: - EnvironmentValues extensions

extension EnvironmentValues {
    var terminalFontSize: Double {
        get { self[TerminalFontSizeKey.self] }
        set { self[TerminalFontSizeKey.self] = newValue }
    }
    var outputDensity: OutputDensity {
        get { self[OutputDensityKey.self] }
        set { self[OutputDensityKey.self] = newValue }
    }
    var showNativeRenderers: Bool {
        get { self[ShowNativeRenderersKey.self] }
        set { self[ShowNativeRenderersKey.self] = newValue }
    }
    var showTimestamps: Bool {
        get { self[ShowTimestampsKey.self] }
        set { self[ShowTimestampsKey.self] = newValue }
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild build -scheme Mosaic -destination 'generic/platform=iOS Simulator' 2>&1 | grep -E 'error:|BUILD'`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Sources/Mosaic/Settings/TerminalEnvironment.swift
git commit -m "feat: environment keys for terminal font size, density, native renderers, timestamps"
```

---

### Task 4: Update OutputBlockView to consume environment settings

**Files:**
- Modify: `Sources/Mosaic/UI/Session/OutputBlockView.swift`

The current file has hardcoded font sizes `12` (command line) and `11` (raw output), hardcoded `.padding(.vertical, 10)`, and always shows native renders. This task wires in all four environment keys.

- [ ] **Step 1: Replace `OutputBlockView.swift` entirely**

```swift
// Sources/Mosaic/UI/Session/OutputBlockView.swift
import SwiftUI

// MARK: - OutputBlockView

@MainActor
struct OutputBlockView: View {
    @ObservedObject var block: OutputBlock

    @Environment(\.terminalFontSize)    private var fontSize
    @Environment(\.outputDensity)       private var density
    @Environment(\.showNativeRenderers) private var showNativeRenderers
    @Environment(\.showTimestamps)      private var showTimestamps

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Command line
            HStack(spacing: 6) {
                Text("›")
                    .font(.custom("JetBrains Mono", size: fontSize - 1).weight(.bold))
                    .foregroundColor(.mosaicAccent)
                Text(block.displayCommand)
                    .font(.custom("JetBrains Mono", size: fontSize - 1))
                    .foregroundColor(.mosaicTextPri)
                Spacer()
                if showTimestamps && !block.isStreaming {
                    Text(block.timestamp, style: .time)
                        .font(.custom("JetBrains Mono", size: 9))
                        .foregroundColor(.mosaicTextSec)
                }
                if block.isStreaming {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(.mosaicAccent)
                }
            }

            // Output
            if block.isStreaming && block.rawOutput.isEmpty {
                EmptyView()
            } else if showNativeRenderers,
                      block.isNativelyRendered,
                      let label = block.rendererBadgeLabel,
                      let result = block.cachedRendererResult {
                NativeOutputView(label: label, result: result, rawOutput: block.rawOutput, fontSize: fontSize)
            } else {
                rawText(block.rawOutput)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, density.verticalPadding)
    }

    private func rawText(_ output: String) -> some View {
        Text(output)
            .font(.custom("JetBrains Mono", size: fontSize))
            .foregroundColor(.mosaicTextPri)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - NativeOutputView

@MainActor
private struct NativeOutputView: View {
    let label: String
    let result: RendererResult
    let rawOutput: String
    let fontSize: Double

    @State private var showingRaw = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            NativeBadge(label: label, showingRaw: $showingRaw)

            if showingRaw {
                rawView.transition(.opacity)
            } else {
                nativeView.transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: showingRaw)
    }

    private var rawView: some View {
        Text(rawOutput)
            .font(.custom("JetBrains Mono", size: fontSize))
            .foregroundColor(.mosaicTextPri)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var nativeView: some View {
        if case .native(let renderer, let data, _) = result {
            renderer.view(for: data)
        } else {
            rawView
        }
    }
}
```

> **Note on font size math:** Command line text uses `fontSize - 1` (so at default 13pt it shows at 12pt, matching the old hardcode). Raw output uses `fontSize` directly (was 11pt; at default 13pt it's slightly larger — acceptable since the user can adjust). If you want exact parity at default, change `fontSize` in `rawText` to `fontSize - 2`. Choose what looks right in the simulator.

- [ ] **Step 2: Build**

Run: `xcodebuild build -scheme Mosaic -destination 'generic/platform=iOS Simulator' 2>&1 | grep -E 'error:|BUILD'`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Sources/Mosaic/UI/Session/OutputBlockView.swift
git commit -m "feat: OutputBlockView reads font size, density, native renderers, timestamps from environment"
```

---

### Task 5: Update SmartInputBar to use terminalFontSize

**Files:**
- Modify: `Sources/Mosaic/UI/Input/SmartInputBar.swift`

The text field currently uses hardcoded `14` pt. Change it to use the environment font size so the input field scales with the user's preference.

- [ ] **Step 1: Add `@Environment(\.terminalFontSize)` and use it in the TextField**

Add this property to `SmartInputBar` (after `@FocusState private var isFocused`):

```swift
@Environment(\.terminalFontSize) private var fontSize
```

Then change the `TextField` font and prompt font from `14` to `fontSize`:

```swift
// Text field
TextField("", text: $text, prompt:
    Text("command")
        .font(.custom("JetBrains Mono", size: fontSize))
        .foregroundColor(Color.mosaicTextSec.opacity(0.5))
)
.font(.custom("JetBrains Mono", size: fontSize))
.foregroundColor(.mosaicTextPri)
.tint(.mosaicAccent)
.focused($isFocused)
.autocorrectionDisabled()
.textInputAutocapitalization(.never)
.onSubmit { submit() }
```

- [ ] **Step 2: Build**

Run: `xcodebuild build -scheme Mosaic -destination 'generic/platform=iOS Simulator' 2>&1 | grep -E 'error:|BUILD'`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Sources/Mosaic/UI/Input/SmartInputBar.swift
git commit -m "feat: SmartInputBar text field scales with terminalFontSize environment"
```

---

### Task 6: SettingsSheet UI

**Files:**
- Create: `Sources/Mosaic/UI/Settings/SettingsSheet.swift`

- [ ] **Step 1: Create the file**

```swift
// Sources/Mosaic/UI/Settings/SettingsSheet.swift
import SwiftUI

@MainActor
struct SettingsSheet: View {
    @Environment(\.dismiss)      private var dismiss
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var s = settings
        NavigationStack {
            Form {
                // MARK: Appearance
                Section("Appearance") {
                    Picker("Theme", selection: $s.theme) {
                        ForEach(AppTheme.allCases, id: \.self) { theme in
                            Text(theme.label).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // MARK: Terminal
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Font Size")
                            Spacer()
                            Text("\(Int(s.terminalFontSize)) pt")
                                .font(.custom("JetBrains Mono", size: 12))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $s.terminalFontSize, in: 9...20, step: 1)
                            .tint(.mosaicAccent)

                        // Live preview
                        Text("$ ls -la ~/projects")
                            .font(.custom("JetBrains Mono", size: s.terminalFontSize))
                            .foregroundColor(.mosaicTextPri)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.mosaicBg)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .padding(.vertical, 4)

                    Picker("Output Density", selection: $s.outputDensity) {
                        ForEach(OutputDensity.allCases, id: \.self) { d in
                            Text(d.label).tag(d)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Terminal")
                }

                // MARK: Display
                Section("Display") {
                    Toggle("Native Renderers", isOn: $s.showNativeRenderers)
                    Toggle("Show Timestamps", isOn: $s.showTimestamps)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.custom("JetBrains Mono", size: 12).weight(.bold))
                        .foregroundColor(.mosaicAccent)
                }
            }
        }
        .preferredColorScheme(settings.theme.colorScheme)
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild build -scheme Mosaic -destination 'generic/platform=iOS Simulator' 2>&1 | grep -E 'error:|BUILD'`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Sources/Mosaic/UI/Settings/SettingsSheet.swift
git commit -m "feat: SettingsSheet with theme picker, font slider, density, display toggles"
```

---

### Task 7: Wire gear button into TabBarView

**Files:**
- Modify: `Sources/Mosaic/UI/TabBar/TabBarView.swift`

Add an `onSettings: () -> Void` parameter and render the gear button outside the horizontal `ScrollView` so it stays pinned at the right edge regardless of tab count.

- [ ] **Step 1: Update `TabBarView` initializer and body**

Replace the `TabBarView` struct (lines 10–52 of the current file) with:

```swift
@MainActor
struct TabBarView: View {
    @ObservedObject var manager: SessionManager
    let onAddTab: () -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Scrollable tabs + add button
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(manager.sessions) { session in
                        TabItemView(
                            session: session,
                            isActive: manager.activeSessionID == session.id,
                            onSelect: { manager.activate(session) },
                            onClose:  { manager.closeSession(session) }
                        )
                    }

                    // Add tab button
                    Button {
                        onAddTab()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.mosaicTextSec)
                            .frame(width: 44, height: tabBarHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
                }
                .padding(.horizontal, 8)
            }

            // Gear — pinned at trailing edge, outside the scroll view
            Rectangle()
                .fill(Color.mosaicBorder)
                .frame(width: 0.5, height: 20)

            Button {
                onSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.mosaicTextSec)
                    .frame(width: 44, height: tabBarHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(height: tabBarHeight)
        .background(Color.mosaicSurface1)
        .overlay(
            Rectangle()
                .fill(Color.mosaicBorder)
                .frame(height: 0.5),
            alignment: .bottom
        )
    }
}
```

- [ ] **Step 2: Build — expect a compile error in `RootView` because `TabBarView` now requires `onSettings`**

Run: `xcodebuild build -scheme Mosaic -destination 'generic/platform=iOS Simulator' 2>&1 | grep -E 'error:|BUILD'`
Expected: `error: missing argument for parameter 'onSettings'` in `RootView.swift`

This is expected — fix it in Step 3.

---

### Task 8: Wire RootView — environment injection, settings sheet, preferredColorScheme

**Files:**
- Modify: `Sources/Mosaic/UI/RootView.swift`

- [ ] **Step 1: Replace `RootView.swift` entirely**

```swift
// Sources/Mosaic/UI/RootView.swift
import SwiftUI

// MARK: - RootView

@MainActor
struct RootView: View {
    @ObservedObject private var manager = SessionManager.shared
    @Environment(AppSettings.self) private var settings

    @State private var showConnectionSheet = false
    @State private var showSettings        = false
    @State private var connectionError: String? = nil

    var body: some View {
        @Bindable var s = settings
        ZStack {
            Color.mosaicBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Tab bar (always visible when sessions exist)
                if !manager.sessions.isEmpty {
                    TabBarView(
                        manager: manager,
                        onAddTab:  { showConnectionSheet = true },
                        onSettings: { showSettings = true }
                    )
                }

                // Content
                if let session = manager.activeSession {
                    SessionView(session: session)
                        .id(session.id)
                } else {
                    EmptyStateView(onConnect: {
                        showConnectionSheet = true
                    })
                    .overlay(alignment: .topTrailing) {
                        // Gear icon when no tabs visible
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 15))
                                .foregroundColor(.mosaicTextSec)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                    }
                }
            }
        }
        .preferredColorScheme(settings.theme.colorScheme)
        // Inject terminal environment values from AppSettings
        .environment(\.terminalFontSize,    settings.terminalFontSize)
        .environment(\.outputDensity,       settings.outputDensity)
        .environment(\.showNativeRenderers, settings.showNativeRenderers)
        .environment(\.showTimestamps,      settings.showTimestamps)
        .sheet(isPresented: $showConnectionSheet) {
            ConnectionSheet { connection in
                Task {
                    if let err = await manager.openSessionThrowing(for: connection) {
                        connectionError = (err as any Error).localizedDescription
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
        }
        .alert("Connection Error", isPresented: Binding(
            get: { connectionError != nil },
            set: { if !$0 { connectionError = nil } }
        )) {
            Button("OK") { connectionError = nil }
        } message: {
            Text(connectionError ?? "")
        }
    }
}
```

- [ ] **Step 2: Inject `AppSettings` into the environment in `MosaicApp.swift`**

In `Sources/Mosaic/App/MosaicApp.swift`, change:

```swift
WindowGroup {
    RootView()
        .modelContainer(container)
        .onAppear { NotificationManager.shared.requestPermission() }
}
```

to:

```swift
WindowGroup {
    RootView()
        .modelContainer(container)
        .environment(AppSettings.shared)
        .onAppear { NotificationManager.shared.requestPermission() }
}
```

- [ ] **Step 3: Build**

Run: `xcodebuild build -scheme Mosaic -destination 'generic/platform=iOS Simulator' 2>&1 | grep -E 'error:|BUILD'`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Sources/Mosaic/UI/RootView.swift Sources/Mosaic/App/MosaicApp.swift Sources/Mosaic/UI/TabBar/TabBarView.swift
git commit -m "feat: wire AppSettings into RootView environment + gear button + dynamic color scheme"
```

---

### Task 9: Regenerate Xcode project + final build + visual verify

New directories (`Settings/`, `UI/Settings/`) need XcodeGen to pick them up.

- [ ] **Step 1: Regenerate project**

```bash
cd /Users/ryancalpin/Documents/App\ Development/mosaic-ios && xcodegen generate
```

Expected: `Created project at .../Mosaic.xcodeproj`

- [ ] **Step 2: Final build**

Run: `xcodebuild build -scheme Mosaic -destination 'generic/platform=iOS Simulator' 2>&1 | grep -E 'error:|BUILD'`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Run in simulator and verify**

Using XcodeBuildMCP: build, run, screenshot. Verify:
- Dark theme: background is `#09090B` near-black ✓
- Light theme: background switches to off-white ✓  
- Font size slider at 9pt: terminal output is noticeably smaller ✓
- Font size slider at 20pt: terminal output is large ✓
- Native Renderers off: `docker ps` / `git status` fall back to plain text ✓
- Timestamps on: time appears after command name ✓
- Gear icon visible in tab bar (right edge) and on empty state ✓

- [ ] **Step 4: Commit if any minor fixes were needed**

```bash
git add -p  # review and add only intentional changes
git commit -m "fix: visual verification corrections"
```

---

## Self-Review

### Spec Coverage

| Requirement | Task |
|-------------|------|
| Dark/light/system theme | Task 1 (enum), Task 2 (adaptive colors), Task 8 (preferredColorScheme) |
| Font size control | Task 1 (model), Task 3 (env key), Task 4 (OutputBlockView), Task 5 (SmartInputBar), Task 6 (slider UI) |
| Output density | Task 1 (enum + padding values), Task 3 (env key), Task 4 (OutputBlockView), Task 6 (picker UI) |
| Native renderer toggle | Task 1 (model), Task 3 (env key), Task 4 (OutputBlockView gates nativeView), Task 6 (toggle UI) |
| Timestamps toggle | Task 1 (model), Task 3 (env key), Task 4 (OutputBlockView shows time), Task 6 (toggle UI) |
| Settings entry point | Task 7 (gear in TabBarView), Task 8 (gear overlay on EmptyState) |
| Persistence across launches | Task 1 (UserDefaults in didSet + init) |

### No Placeholders Found ✓

### Type Consistency Check

- `AppTheme` defined in Task 1, used in Task 6 (`Picker`) and Task 8 (`preferredColorScheme`) ✓
- `OutputDensity` defined in Task 1, `verticalPadding` used in Task 4 ✓
- `TerminalEnvironment.swift` keys named `terminalFontSize`, `outputDensity`, `showNativeRenderers`, `showTimestamps` — all four used consistently in Tasks 4, 5, 8 ✓
- `AppSettings.shared` injected via `.environment(AppSettings.shared)` in Task 8 Step 2, read via `@Environment(AppSettings.self)` in Tasks 6 and 8 ✓
- `TabBarView(manager:onAddTab:onSettings:)` — new signature defined in Task 7, called in Task 8 ✓
