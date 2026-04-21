# iPad Split Pane Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On iPad (regular horizontal size class), replace the horizontal tab bar with a `NavigationSplitView` sidebar showing active sessions; iPhone keeps the existing tab-bar layout unchanged.

**Architecture:** A new `SidebarView` renders the session list vertically in a `List` with selection bound to `SessionManager.activeSessionID`. `RootView` branches on `horizontalSizeClass`: regular → `NavigationSplitView(sidebar: SidebarView, detail: SessionView)`; compact → existing `VStack` layout. All sheets and environment modifiers stay on the top-level `Group` so they apply to both branches.

**Tech Stack:** Swift 5.9, SwiftUI `NavigationSplitView` (iOS 16+), `@Environment(\.horizontalSizeClass)`, existing `SessionManager`, `StatusDot`, `ProtocolBadge`

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `Sources/Mosaic/UI/iPad/SidebarView.swift` | Vertical session list for iPad; toolbar add + settings buttons |
| Modify | `Sources/Mosaic/UI/RootView.swift` | Branch on size class; iPadLayout / iPhoneLayout computed vars |

---

### Task 1: SidebarView — iPad session list

**Files:**
- Create: `Sources/Mosaic/UI/iPad/SidebarView.swift`

- [ ] **Step 1: Create the file**

```swift
// Sources/Mosaic/UI/iPad/SidebarView.swift
import SwiftUI

// MARK: - SidebarView
//
// iPad sidebar: vertical session list bound to SessionManager.activeSessionID.
// Toolbar: gear (settings) + plus (add session).
// Empty overlay when no sessions exist.

@MainActor
struct SidebarView: View {
    @ObservedObject var manager: SessionManager
    let onAddTab: () -> Void
    let onSettings: () -> Void

    var body: some View {
        List(manager.sessions, selection: Binding<UUID?>(
            get: { manager.activeSessionID },
            set: { manager.activeSessionID = $0 }
        )) { session in
            SidebarRow(session: session, onClose: { manager.closeSession(session) })
                .tag(session.id)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color.mosaicSurface1)
        .overlay {
            if manager.sessions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.mosaicTextSec)
                    Text("No sessions")
                        .font(.custom("JetBrains Mono", size: 12))
                        .foregroundStyle(Color.mosaicTextSec)
                }
            }
        }
        .navigationTitle("Mosaic")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { onSettings() } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(Color.mosaicTextSec)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { onAddTab() } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(Color.mosaicAccent)
                }
            }
        }
    }
}

// MARK: - SidebarRow

@MainActor
private struct SidebarRow: View {
    @ObservedObject var session: Session
    let onClose: () -> Void

    private var connInfo: ConnectionInfo { session.connection.connectionInfo }
    private var connState: ConnectionState { session.connectionState }

    var body: some View {
        HStack(spacing: 10) {
            StatusDot(state: connState)

            VStack(alignment: .leading, spacing: 2) {
                Text(connInfo.hostname)
                    .font(.custom("JetBrains Mono", size: 11).weight(.semibold))
                    .foregroundStyle(Color.mosaicTextPri)
                    .lineLimit(1)
                Text(connInfo.username)
                    .font(.custom("JetBrains Mono", size: 9))
                    .foregroundStyle(Color.mosaicTextSec)
            }

            Spacer()

            ProtocolBadge(transport: connInfo.transport, isRoaming: connState == .roaming)

            Button { onClose() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.mosaicTextSec)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
```

- [ ] **Step 2: Build**

```bash
cd "/Users/ryancalpin/Documents/App Development/mosaic-ios" && xcodegen generate && xcodebuild build -scheme Mosaic -destination 'generic/platform=iOS Simulator' 2>&1 | grep -E 'error:|BUILD'
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
cd "/Users/ryancalpin/Documents/App Development/mosaic-ios" && git add Sources/Mosaic/UI/iPad/SidebarView.swift && git commit -m "feat: SidebarView — iPad session list for NavigationSplitView"
```

---

### Task 2: Adaptive RootView — NavigationSplitView on iPad, tab bar on iPhone

**Files:**
- Modify: `Sources/Mosaic/UI/RootView.swift`

Replace the entire file. The key change is splitting `body` into `iPadLayout` and `iPhoneLayout` computed vars, branched on `horizontalSizeClass`. All sheets and environment modifiers stay on the outer `Group` so they apply regardless of branch.

- [ ] **Step 1: Replace the file**

```swift
// Sources/Mosaic/UI/RootView.swift
import SwiftUI

// MARK: - RootView
//
// Top-level layout, adaptive by horizontal size class:
//   regular (iPad)  → NavigationSplitView with SidebarView sidebar
//   compact (iPhone) → vertical tab bar + content stack
// Sheets and environment keys are applied once on the outer Group.

@MainActor
struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ObservedObject private var manager = SessionManager.shared
    @State private var showConnectionSheet = false
    @State private var showSettingsSheet = false
    @State private var connectionError: String? = nil
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        Group {
            if sizeClass == .regular {
                iPadLayout
            } else {
                iPhoneLayout
            }
        }
        .preferredColorScheme(settings.theme.colorScheme)
        .environment(\.terminalFontSize,    settings.terminalFontSize)
        .environment(\.outputDensity,       settings.outputDensity)
        .environment(\.showNativeRenderers, settings.showNativeRenderers)
        .environment(\.showTimestamps,      settings.showTimestamps)
        .sheet(isPresented: $showSettingsSheet) {
            SettingsSheet()
        }
        .sheet(isPresented: $showConnectionSheet) {
            ConnectionSheet { connection in
                Task {
                    if let err = await manager.openSessionThrowing(for: connection) {
                        connectionError = (err as any Error).localizedDescription
                    }
                }
            }
            .environment(AppSettings.shared)
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

    // MARK: - iPad Layout

    private var iPadLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                manager: manager,
                onAddTab:   { showConnectionSheet = true },
                onSettings: { showSettingsSheet = true }
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            if let session = manager.activeSession {
                SessionView(session: session)
                    .id(session.id)
            } else {
                EmptyStateView(onConnect: { showConnectionSheet = true })
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - iPhone Layout

    private var iPhoneLayout: some View {
        ZStack {
            Color.mosaicBg.ignoresSafeArea()
            VStack(spacing: 0) {
                if !manager.sessions.isEmpty {
                    TabBarView(
                        manager:    manager,
                        onAddTab:   { showConnectionSheet = true },
                        onSettings: { showSettingsSheet = true }
                    )
                }
                if let session = manager.activeSession {
                    SessionView(session: session)
                        .id(session.id)
                } else {
                    EmptyStateView(onConnect: { showConnectionSheet = true })
                        .overlay(alignment: .topTrailing) {
                            Button { showSettingsSheet = true } label: {
                                Image(systemName: "gearshape")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color.mosaicTextSec)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(8)
                        }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Build**

```bash
cd "/Users/ryancalpin/Documents/App Development/mosaic-ios" && xcodebuild build -scheme Mosaic -destination 'generic/platform=iOS Simulator' 2>&1 | grep -E 'error:|BUILD'
```

Expected: `** BUILD SUCCEEDED **`

If you see `error: value of type 'UUID' cannot be used as type 'UUID?'` — the List tag needs an explicit cast: `.tag(session.id as UUID?)`.

- [ ] **Step 3: Commit**

```bash
cd "/Users/ryancalpin/Documents/App Development/mosaic-ios" && git add Sources/Mosaic/UI/RootView.swift && git commit -m "feat: RootView adaptive layout — NavigationSplitView on iPad, tab bar on iPhone"
```

---

### Task 3: Build, run, visual verify on iPad + confirm iPhone unchanged

- [ ] **Step 1: Find an iPad simulator**

```bash
xcrun simctl list devices available | grep -i ipad | head -10
```

Note the UDID of an available iPad simulator (e.g. `iPad Pro 13-inch (M4)` or `iPad (10th generation)`).

- [ ] **Step 2: Build and run on iPad simulator**

Use XcodeBuildMCP `session_use_defaults_profile` if available, or run directly:

```bash
# Replace <IPAD_UDID> with the actual UDID from Step 1
cd "/Users/ryancalpin/Documents/App Development/mosaic-ios" && xcodebuild build -scheme Mosaic -destination 'id=<IPAD_UDID>' 2>&1 | tail -5
```

Then launch via XcodeBuildMCP `build_run_sim` after setting the simulator to an iPad.

- [ ] **Step 3: Take a screenshot and verify iPad layout**

Expected on iPad:
- Left column (~260 pt wide): "Mosaic" navigation title, gear + plus toolbar buttons, empty session list with "No sessions" overlay
- Right column (detail): EmptyStateView with "Connect to a server" button
- `NavigationSplitView` visible split line between columns

- [ ] **Step 4: Confirm iPhone layout unchanged**

Switch back to iPhone 17 Pro simulator (UUID `913B454F-493C-46DC-B2B4-63348DA39843`):

```bash
cd "/Users/ryancalpin/Documents/App Development/mosaic-ios" && xcodebuild build -scheme Mosaic -destination 'id=913B454F-493C-46DC-B2B4-63348DA39843' 2>&1 | tail -5
```

Take screenshot. Expected: existing empty state with "Connect to a server" button, gear overlay top-right — no sidebar visible.

- [ ] **Step 5: Commit any fixes**

```bash
cd "/Users/ryancalpin/Documents/App Development/mosaic-ios" && git add -p && git commit -m "fix: iPad split pane visual verification corrections"
```

---

## Self-Review

### Spec Coverage

| Requirement | Task |
|---|---|
| iPad shows sidebar instead of tab bar | Task 2 (`sizeClass == .regular` → `iPadLayout`) |
| Sidebar lists active sessions | Task 1 (`SidebarView` with `List(manager.sessions)`) |
| Sidebar session rows show status dot, hostname, username, protocol badge | Task 1 (`SidebarRow`) |
| Session selection in sidebar activates that session | Task 1 (`Binding<UUID?>` → `manager.activeSessionID`) |
| Close button in sidebar row closes session | Task 1 (`onClose: { manager.closeSession(session) }`) |
| Sidebar toolbar: + (add) and gear (settings) | Task 1 (`.toolbar` with two `ToolbarItem`s) |
| iPhone keeps existing tab-bar layout | Task 2 (`iPhoneLayout` computed var — same code as before) |
| Empty state shown in sidebar when no sessions | Task 1 (`.overlay` with "No sessions" text) |
| Detail pane: SessionView when session active, EmptyStateView otherwise | Task 2 (`iPadLayout` detail closure) |
| Theme propagates through NavigationSplitView | Task 2 (`.preferredColorScheme` on outer `Group`) |
| Environment keys propagate to both branches | Task 2 (all four `.environment(\.key, value)` on outer `Group`) |

### No Placeholders ✓

### Type Consistency

- `SidebarView(manager: SessionManager, onAddTab: () -> Void, onSettings: () -> Void)` — defined Task 1, used Task 2 ✓
- `SidebarRow` is `private` — only used inside `SidebarView.swift` ✓
- `manager.activeSessionID: UUID?` — `Binding<UUID?>` in Task 1 matches the `@Published` type in `SessionManager` ✓
- `session.id: UUID` used as `.tag(session.id)` — selection type `UUID?`, SwiftUI handles implicit Optional wrapping ✓
- `StatusDot(state: ConnectionState)` — used in `SidebarRow`, exists in `TabBarView.swift` ✓
- `ProtocolBadge(transport: TransportProtocol, isRoaming: Bool)` — used in `SidebarRow`, exists in `TabBarView.swift` ✓
- `NavigationSplitViewVisibility` — `@State var columnVisibility: NavigationSplitViewVisibility = .all` matches `NavigationSplitView(columnVisibility: $columnVisibility)` ✓
