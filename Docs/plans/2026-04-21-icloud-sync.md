# iCloud Sync + Device Handoff Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sync `Connection` records across all of the user's iOS devices via CloudKit and let an active terminal session hand off to another device via NSUserActivity.
**Architecture:** SwiftData's built-in CloudKit mirror (`.automatic`) syncs `Connection` objects with no extra code; Device Handoff serialises the active connection's UUID into an `NSUserActivity` so the receiving device can fetch it from SwiftData and open a new session.
**Tech Stack:** SwiftData + CloudKit (CKContainer `iCloud.com.ryncalpin.mosaic`), NSUserActivity, `ModelContainer`, `@Query`

---

## Task 1: Enable CloudKit Entitlements and Wire ModelContainer

**Files to edit:**
- `Sources/Mosaic/App/Mosaic.entitlements` — entitlements already have the CloudKit keys; verify they are present and correct
- `Sources/Mosaic/App/MosaicApp.swift` — change `cloudKitDatabase: .none` to `.automatic`

### 1a — Verify entitlements (already present, no edit needed)

The file at `Sources/Mosaic/App/Mosaic.entitlements` already contains:

```xml
<key>com.apple.developer.icloud-services</key>
<array>
    <string>CloudKit</string>
</array>
<key>com.apple.developer.icloud-container-identifiers</key>
<array>
    <string>iCloud.com.ryncalpin.mosaic</string>
</array>
```

No changes required. Confirm the container identifier matches what is registered in the Apple Developer portal (Certificates → Identifiers → iCloud Containers).

### 1b — Enable CloudKit sync in ModelContainer

Edit `Sources/Mosaic/App/MosaicApp.swift`:

```swift
// BEFORE
let config = ModelConfiguration(cloudKitDatabase: .none)

// AFTER
let config = ModelConfiguration(cloudKitDatabase: .automatic)
```

Full updated `init()`:

```swift
init() {
    do {
        let config = ModelConfiguration(cloudKitDatabase: .automatic)
        container = try ModelContainer(for: Connection.self, configurations: config)
        injectTestSSHKeyIfNeeded(container: container)
    } catch {
        fatalError("Failed to create model container: \(error)")
    }
}
```

- [ ] Edit `Sources/Mosaic/App/MosaicApp.swift` — change `.none` to `.automatic`
- [ ] Verify `Mosaic.entitlements` has the correct container ID `iCloud.com.ryncalpin.mosaic`
- [ ] Build:

```bash
cd "/Users/ryancalpin/Documents/App Development/mosaic-ios" && xcodebuild build -scheme Mosaic -destination 'generic/platform=iOS Simulator' 2>&1 | grep -E 'error:|BUILD'
```

- [ ] Commit:

```bash
cd "/Users/ryancalpin/Documents/App Development/mosaic-ios" && git add Sources/Mosaic/App/MosaicApp.swift Sources/Mosaic/App/Mosaic.entitlements && git commit -m "feat: enable CloudKit sync for Connection model"
```

---

## Task 2: Verify CloudKit Sync

No code changes required. This task validates that the `.automatic` configuration correctly mirrors `Connection` records.

### Manual verification steps

**Option A — Two simulators (recommended):**

1. Boot two different iOS 17 simulators (e.g. iPhone 15 Pro and iPhone SE 3rd gen).
2. Sign into the same iCloud account in both: Settings → [your name] → iCloud.
3. Install and launch Mosaic on Simulator A.
4. Add a connection via the `+` sheet.
5. Launch Mosaic on Simulator B — the connection should appear within ~30 seconds.

**Option B — CloudKit Dashboard:**

```bash
# Confirm the container exists and is active
xcrun cloudkit-tool --container iCloud.com.ryncalpin.mosaic list-record-types 2>/dev/null || \
  echo "Use https://icloud.developer.apple.com/dashboard to inspect records"
```

Navigate to [https://icloud.developer.apple.com/dashboard](https://icloud.developer.apple.com/dashboard), select the container `iCloud.com.ryncalpin.mosaic`, choose the **Development** environment, and query the `CD_Connection` record type. Records created on the simulator should appear here within a few seconds.

**Known constraints:**
- CloudKit sync requires a signed-in iCloud account; the simulator sandbox account works.
- SwiftData mirrors every `@Model` property that is `Codable`-compatible. All `Connection` fields qualify.
- Credentials are stored in Keychain only — they do NOT sync via CloudKit. This is intentional and correct.

- [ ] Add a connection on Simulator A, confirm it appears on Simulator B (or in CloudKit Dashboard)
- [ ] Confirm Keychain entries are NOT synced (credentials must be re-entered on new devices — expected behavior)
- [ ] No commit required for this task

---

## Task 3: Device Handoff via NSUserActivity

Handoff broadcasts the UUID of the active connection. The receiving device fetches the `Connection` from its local (CloudKit-synced) SwiftData store and opens a new session.

**Activity type:** `com.mosaic.session` — must be added to the `NSUserActivityTypes` array in `Info.plist`.

### 3a — Register the activity type in Info.plist

Edit `Sources/Mosaic/App/Info.plist` (or the Xcode project's `Info` build settings tab):

Add to the root `<dict>`:

```xml
<key>NSUserActivityTypes</key>
<array>
    <string>com.mosaic.session</string>
</array>
```

### 3b — Advertise the activity from SessionView

Edit `Sources/Mosaic/UI/Session/SessionView.swift`. Add `.userActivity(...)` to the outermost `VStack` inside `body`:

```swift
var body: some View {
    VStack(spacing: 0) {
        // ... existing content unchanged ...
    }
    .userActivity("com.mosaic.session", isActive: true) { activity in
        activity.title = "Terminal — \(connInfo.username)@\(connInfo.hostname)"
        activity.addUserInfoEntries(from: [
            "connectionID": session.connection.id.uuidString
        ])
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = false
    }
}
```

`connInfo` is already computed at the top of `SessionView`:
```swift
private var connInfo: ConnectionInfo { session.connection.connectionInfo }
```

No new property is needed; the activity updates automatically when `session.connection` changes because SwiftUI re-evaluates the modifier on each render.

### 3c — Handle incoming activity in MosaicApp

Edit `Sources/Mosaic/App/MosaicApp.swift`. Add `.onContinueUserActivity(...)` to the `WindowGroup`:

```swift
var body: some Scene {
    WindowGroup {
        RootView()
            .modelContainer(container)
            .environment(AppSettings.shared)
            .onAppear { NotificationManager.shared.requestPermission() }
            .onContinueUserActivity("com.mosaic.session") { activity in
                guard
                    let idString = activity.userInfo?["connectionID"] as? String,
                    let uuid = UUID(uuidString: idString)
                else { return }

                let ctx = ModelContext(container)
                let descriptor = FetchDescriptor<Connection>(
                    predicate: #Predicate { $0.id == uuid }
                )
                guard let connection = try? ctx.fetch(descriptor).first else { return }

                Task { @MainActor in
                    try? await SessionManager.shared.openSession(for: connection)
                }
            }
    }
}
```

- [ ] Add `NSUserActivityTypes` to `Info.plist`
- [ ] Edit `Sources/Mosaic/UI/Session/SessionView.swift` — add `.userActivity(...)` modifier
- [ ] Edit `Sources/Mosaic/App/MosaicApp.swift` — add `.onContinueUserActivity(...)` handler
- [ ] Build:

```bash
cd "/Users/ryancalpin/Documents/App Development/mosaic-ios" && xcodebuild build -scheme Mosaic -destination 'generic/platform=iOS Simulator' 2>&1 | grep -E 'error:|BUILD'
```

- [ ] Test: open a session on Device A, swipe up on Device B's lock screen Handoff banner, confirm Mosaic opens with the same connection
- [ ] Commit:

```bash
cd "/Users/ryancalpin/Documents/App Development/mosaic-ios" && git add Sources/Mosaic/App/MosaicApp.swift Sources/Mosaic/UI/Session/SessionView.swift && git commit -m "feat: Device Handoff — advertise active session via NSUserActivity"
```

---

## Task 4: Conflict Handling and Remote-Change Awareness

**Architecture note:** SwiftData + CloudKit handles merge conflicts automatically using last-write-wins at the field level. The `@Query` macro in any SwiftUI view that lists connections (`ConnectionSheet`, connection pickers, etc.) automatically reflects remote changes because `@Query` observes the persistent store. No manual merge code is required.

**What to do:** Add a `NotificationCenter` publisher in `RootView` so the UI re-fetches connections immediately when a remote CloudKit push arrives, rather than waiting for the next app foreground cycle.

Edit `Sources/Mosaic/UI/RootView.swift`. Add the modifier to the outermost `ZStack` inside `body`:

```swift
var body: some View {
    ZStack {
        // ... existing content unchanged ...
    }
    .preferredColorScheme(settings.theme.colorScheme)
    // ... existing modifiers unchanged ...
    .onReceive(
        NotificationCenter.default.publisher(
            for: NSNotification.Name.NSPersistentStoreRemoteChange
        )
    ) { _ in
        // @Query views update automatically; this is a hook for any
        // imperative state that needs a refresh (e.g., session tab names).
        // Currently a no-op — left as the integration point for future work.
        // If SessionManager caches connection names, refresh them here.
    }
}
```

**Why this is mostly a no-op today:** `Connection` objects are displayed via `@Query` in `ConnectionSheet` and similar views; those update live. `SessionManager` holds strong references to `Session` objects (not to the `Connection` model objects directly — it holds a `TerminalConnection` transport). If a remote change renames a connection while a session is open, the tab name will not update until the session is closed and re-opened. A future task can address this by observing individual `Connection` objects inside `Session`.

**Reviewer note:** Do NOT use `NSPersistentCloudKitContainer.eventChangedNotification` here — that belongs to `NSPersistentCloudKitContainer`, which is the UIKit/Core Data API. Mosaic uses `ModelContainer` (SwiftData), which posts `NSPersistentStoreRemoteChange` to `NSPersistentStoreCoordinator` instead. The `.onReceive` pattern above is the correct SwiftData equivalent.

- [ ] Edit `Sources/Mosaic/UI/RootView.swift` — add `.onReceive(NSPersistentStoreRemoteChange)` modifier
- [ ] Build:

```bash
cd "/Users/ryancalpin/Documents/App Development/mosaic-ios" && xcodebuild build -scheme Mosaic -destination 'generic/platform=iOS Simulator' 2>&1 | grep -E 'error:|BUILD'
```

- [ ] Commit:

```bash
cd "/Users/ryancalpin/Documents/App Development/mosaic-ios" && git add Sources/Mosaic/UI/RootView.swift && git commit -m "feat: observe NSPersistentStoreRemoteChange for CloudKit push awareness"
```

---

## Completion Checklist

- [ ] `** BUILD SUCCEEDED **` after each task
- [ ] Connection added on Device A appears on Device B within ~30 s
- [ ] Handoff banner appears on Device B when a session is active on Device A
- [ ] Tapping Handoff banner opens Mosaic and connects to the same server
- [ ] Keychain credentials are NOT synced (user must re-enter password/key on each device)
- [ ] No SwiftData migrations required (no schema change — only `cloudKitDatabase` config changed)
