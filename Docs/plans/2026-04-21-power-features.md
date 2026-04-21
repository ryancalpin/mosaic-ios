# Power Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add hardware keyboard shortcuts, iOS Shortcuts/AppIntents integration, and rich push notifications with actionable categories to Mosaic.
**Architecture:** Keyboard shortcuts live in a SwiftUI `Commands` struct attached to the `WindowGroup` in `MosaicApp.swift` and via `.keyboardShortcut` modifiers in `RootView.swift`; AppIntents are self-contained files under `Sources/Mosaic/Shortcuts/`; notification enhancements extend the existing `NotificationManager` singleton with new scheduling methods and category registration.
**Tech Stack:** SwiftUI `Commands`, `AppIntents` framework, `UserNotifications` (`UNUserNotificationCenter`, `UNNotificationAction`, `UNNotificationCategory`)

---

## Task 1: Hardware Keyboard Shortcuts

**Files touched:**
- `Sources/Mosaic/App/MosaicApp.swift` — attach `MosaicCommands` to `WindowGroup`
- `Sources/Mosaic/UI/RootView.swift` — add `.keyboardShortcut` modifiers and scroll notification posting
- `Sources/Mosaic/Core/Session.swift` — add `sendSignal(_ signal: TerminalSignal)` method
- `Sources/Mosaic/Core/TerminalConnection.swift` — add `TerminalSignal` enum (no protocol change)

### Steps

- [ ] **1.1 — Add `TerminalSignal` enum to `TerminalConnection.swift`**

  Append after the closing brace of `ConnectionError`, still within the same file:

  ```swift
  // MARK: - TerminalSignal

  public enum TerminalSignal {
      case interrupt   // Ctrl-C  → \u{03}
      case suspend     // Ctrl-Z  → \u{1A}
      case quit        // Ctrl-\  → \u{1C}
  }
  ```

- [ ] **1.2 — Add `sendSignal(_:)` to `Session.swift`**

  Add the following public method inside `Session`, after the `send(_:)` method (around line 134):

  ```swift
  public func sendSignal(_ signal: TerminalSignal) {
      let byte: String
      switch signal {
      case .interrupt: byte = "\u{03}"
      case .suspend:   byte = "\u{1A}"
      case .quit:      byte = "\u{1C}"
      }
      Task { @MainActor [weak self] in
          try? await self?.connection.send(byte)
      }
  }
  ```

- [ ] **1.3 — Add `SessionManager.activate(at:)` helper to `SessionManager.swift`**

  Append inside `SessionManager` after the existing `activate(_ session:)` method:

  ```swift
  /// Activates the session at a 1-based keyboard index (⌘1 = index 1).
  public func activate(at oneBasedIndex: Int) {
      let idx = oneBasedIndex - 1
      guard sessions.indices.contains(idx) else { return }
      activeSessionID = sessions[idx].id
  }
  ```

- [ ] **1.4 — Create `Sources/Mosaic/App/MosaicCommands.swift`**

  ```swift
  import SwiftUI

  // MARK: - MosaicCommands
  //
  // Hardware keyboard shortcuts surfaced in the system menu bar and via ⌘ key on iPad.
  // Scroll notifications are observed by SessionView.

  struct MosaicCommands: Commands {
      @ObservedObject private var manager = SessionManager.shared

      // Bound as @State in RootView and passed in — use a binding so sheet opens from menu.
      @Binding var showConnectionSheet: Bool

      var body: some Commands {
          CommandMenu("Session") {
              Button("New Connection") {
                  showConnectionSheet = true
              }
              .keyboardShortcut("t", modifiers: .command)

              Button("Close Session") {
                  guard let session = manager.activeSession else { return }
                  manager.closeSession(session)
              }
              .keyboardShortcut("w", modifiers: .command)
              .disabled(manager.activeSession == nil)

              Divider()

              Button("Command Palette") {
                  showConnectionSheet = true
              }
              .keyboardShortcut("k", modifiers: .command)

              Divider()

              Button("Scroll to Top") {
                  NotificationCenter.default.post(name: .mosaicScrollToTop, object: nil)
              }
              .keyboardShortcut(.upArrow, modifiers: .command)
              .disabled(manager.activeSession == nil)

              Button("Scroll to Bottom") {
                  NotificationCenter.default.post(name: .mosaicScrollToBottom, object: nil)
              }
              .keyboardShortcut(.downArrow, modifiers: .command)
              .disabled(manager.activeSession == nil)

              Divider()

              Button("Send Interrupt (^C)") {
                  manager.activeSession?.sendSignal(.interrupt)
              }
              .keyboardShortcut("c", modifiers: .control)
              .disabled(manager.activeSession == nil)

              Divider()

              // ⌘1 – ⌘9 session switching
              ForEach(1...9, id: \.self) { index in
                  Button("Switch to Session \(index)") {
                      manager.activate(at: index)
                  }
                  .keyboardShortcut(KeyEquivalent(Character(String(index))), modifiers: .command)
                  .disabled(manager.sessions.count < index)
              }
          }
      }
  }

  // MARK: - Notification names

  extension Notification.Name {
      static let mosaicScrollToTop    = Notification.Name("mosaic.scrollToTop")
      static let mosaicScrollToBottom = Notification.Name("mosaic.scrollToBottom")
  }
  ```

- [ ] **1.5 — Wire `MosaicCommands` into `MosaicApp.swift`**

  The `WindowGroup` needs a `@State` var for `showConnectionSheet` so it can be passed as a binding to `MosaicCommands`. Replace the `body` in `MosaicApp.swift` with:

  ```swift
  @State private var showConnectionSheet = false

  var body: some Scene {
      WindowGroup {
          RootView(externalShowConnectionSheet: $showConnectionSheet)
              .modelContainer(container)
              .environment(AppSettings.shared)
              .onAppear { NotificationManager.shared.requestPermission() }
      }
      .commands {
          MosaicCommands(showConnectionSheet: $showConnectionSheet)
      }
  }
  ```

- [ ] **1.6 — Update `RootView.swift` to accept an external binding**

  Add the external binding initializer and merge it with the local state:

  ```swift
  @State private var showConnectionSheet = false
  @State private var showSettingsSheet = false
  @State private var connectionError: String? = nil

  // Accepts an optional external binding from MosaicApp (keyboard shortcut driven).
  var externalShowConnectionSheet: Binding<Bool>?

  init(externalShowConnectionSheet: Binding<Bool>? = nil) {
      self.externalShowConnectionSheet = externalShowConnectionSheet
  }

  // Computed property merges local and external state
  private var connectionSheetBinding: Binding<Bool> {
      guard let ext = externalShowConnectionSheet else {
          return $showConnectionSheet
      }
      return Binding(
          get: { ext.wrappedValue || self.showConnectionSheet },
          set: { newVal in
              ext.wrappedValue = newVal
              self.showConnectionSheet = newVal
          }
      )
  }
  ```

  Then replace every `$showConnectionSheet` reference in `body` with `connectionSheetBinding`.

- [ ] **1.7 — Subscribe to scroll notifications in `SessionView.swift`**

  Inside `SessionView`, add a `ScrollViewProxy` via `ScrollViewReader` around the existing scroll content, then subscribe:

  ```swift
  // In the ScrollView content wrapper:
  ScrollViewReader { proxy in
      // existing LazyVStack content
  }
  .onReceive(NotificationCenter.default.publisher(for: .mosaicScrollToTop)) { _ in
      withAnimation { proxy.scrollTo("top", anchor: .top) }
  }
  .onReceive(NotificationCenter.default.publisher(for: .mosaicScrollToBottom)) { _ in
      withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
  }
  ```

  Ensure the first item in the list has `.id("top")` and a spacer at the end has `.id("bottom")`.

- [ ] **1.8 — Build and verify**

  ```bash
  cd "/Users/ryancalpin/Documents/App Development/mosaic-ios" && xcodebuild build -scheme Mosaic -destination 'generic/platform=iOS Simulator' 2>&1 | grep -E 'error:|BUILD'
  ```

  Expected: `** BUILD SUCCEEDED **`

- [ ] **1.9 — Commit**

  ```bash
  cd "/Users/ryancalpin/Documents/App Development/mosaic-ios" && git add \
    Sources/Mosaic/Core/TerminalConnection.swift \
    Sources/Mosaic/Core/Session.swift \
    Sources/Mosaic/Core/SessionManager.swift \
    Sources/Mosaic/App/MosaicCommands.swift \
    Sources/Mosaic/App/MosaicApp.swift \
    Sources/Mosaic/UI/RootView.swift \
    Sources/Mosaic/UI/Session/SessionView.swift && \
  git commit -m "feat: hardware keyboard shortcuts — ⌘T/W/K/1-9/↑↓ and ^C interrupt"
  ```

---

## Task 2: iOS Shortcuts / AppIntents

**Files touched:**
- `Sources/Mosaic/Shortcuts/OpenServerIntent.swift` (new)
- `Sources/Mosaic/Shortcuts/AppShortcutsProvider.swift` (new)
- `project.yml` — add `AppIntents` to framework dependencies

### Steps

- [ ] **2.1 — Create `Sources/Mosaic/Shortcuts/OpenServerIntent.swift`**

  ```swift
  import AppIntents
  import SwiftData

  // MARK: - OpenServerIntent
  //
  // Siri / Shortcuts: "Open Mosaic on prod-01"
  // Fetches a Connection by name from SwiftData and opens a session.

  struct OpenServerIntent: AppIntent {
      static var title: LocalizedStringResource = "Open Server in Mosaic"
      static var description = IntentDescription("Connect to a saved server by name.")

      @Parameter(title: "Server Name")
      var serverName: String

      @MainActor
      func perform() async throws -> some IntentResult {
          // Resolve a ModelContainer identical to the one in MosaicApp
          let config = ModelConfiguration(cloudKitDatabase: .none)
          let container = try ModelContainer(for: Connection.self, configurations: config)
          let context = ModelContext(container)

          let descriptor = FetchDescriptor<Connection>(
              predicate: #Predicate { $0.name == serverName }
          )
          guard let connection = try context.fetch(descriptor).first else {
              throw AppIntentError.connectionNotFound(serverName)
          }

          if let error = await SessionManager.shared.openSessionThrowing(for: connection) {
              throw error
          }

          return .result()
      }
  }

  // MARK: - Intent errors

  enum AppIntentError: LocalizedError {
      case connectionNotFound(String)

      var errorDescription: String? {
          switch self {
          case .connectionNotFound(let name):
              return "No saved server named '\(name)' found in Mosaic."
          }
      }
  }
  ```

- [ ] **2.2 — Create `Sources/Mosaic/Shortcuts/AppShortcutsProvider.swift`**

  ```swift
  import AppIntents

  // MARK: - MosaicShortcuts
  //
  // Registers Siri phrases for the OpenServerIntent.
  // iOS surfaces these automatically in Shortcuts.app and Spotlight.

  struct MosaicShortcuts: AppShortcutsProvider {
      static var appShortcuts: [AppShortcut] {
          AppShortcut(
              intent: OpenServerIntent(),
              phrases: [
                  "Open \(.applicationName) on \(\.$serverName)",
                  "Connect to \(\.$serverName) in \(.applicationName)",
                  "SSH to \(\.$serverName) with \(.applicationName)"
              ],
              shortTitle: "Open Server",
              systemImageName: "terminal"
          )
      }
  }
  ```

- [ ] **2.3 — Add `AppIntents` framework to `project.yml`**

  In `project.yml`, under the target's `dependencies:` or `settings: FRAMEWORK_SEARCH_PATHS`, add `AppIntents` as a system framework. The typical location in a `project.yml` using XcodeGen is:

  ```yaml
  # Under targets: Mosaic: dependencies:
  - sdk: AppIntents.framework
  ```

  If the target already lists `sdk` entries, append this entry alongside them.

- [ ] **2.4 — Build and verify**

  ```bash
  cd "/Users/ryancalpin/Documents/App Development/mosaic-ios" && xcodebuild build -scheme Mosaic -destination 'generic/platform=iOS Simulator' 2>&1 | grep -E 'error:|BUILD'
  ```

  Expected: `** BUILD SUCCEEDED **`

- [ ] **2.5 — Commit**

  ```bash
  cd "/Users/ryancalpin/Documents/App Development/mosaic-ios" && git add \
    Sources/Mosaic/Shortcuts/OpenServerIntent.swift \
    Sources/Mosaic/Shortcuts/AppShortcutsProvider.swift \
    project.yml && \
  git commit -m "feat: iOS Shortcuts integration — OpenServerIntent + Siri phrases"
  ```

---

## Task 3: Rich Push Notifications

**Files touched:**
- `Sources/Mosaic/Notifications/NotificationManager.swift` — add three scheduling methods and category/action registration

### Steps

- [ ] **3.1 — Replace `NotificationManager.swift` with full implementation**

  The existing file has `requestPermission()` and `notifyCommandComplete()`. Replace the entire file contents with the expanded version below, which adds the three new scheduling methods and wires up notification categories and actions:

  ```swift
  import UserNotifications

  // MARK: - NotificationManager

  final class NotificationManager: NSObject {
      static let shared = NotificationManager()

      // Category identifiers
      private static let categoryProcessAlert = "PROCESS_ALERT"
      private static let categoryLogKeyword   = "LOG_KEYWORD"
      private static let categoryCertExpiry   = "CERT_EXPIRY"

      // Action identifiers
      private static let actionViewSession    = "VIEW_SESSION"
      private static let actionDismiss        = "DISMISS"

      private override init() {
          super.init()
      }

      // MARK: - Permission + Category Registration

      func requestPermission() {
          // Register actionable categories before requesting authorization
          // so they are available as soon as permission is granted.
          registerCategories()

          UNUserNotificationCenter.current().requestAuthorization(
              options: [.alert, .sound, .badge]
          ) { _, _ in }

          UNUserNotificationCenter.current().delegate = self
      }

      private func registerCategories() {
          let viewAction = UNNotificationAction(
              identifier: Self.actionViewSession,
              title: "View Session",
              options: [.foreground]
          )
          let dismissAction = UNNotificationAction(
              identifier: Self.actionDismiss,
              title: "Dismiss",
              options: [.destructive]
          )

          let processAlertCategory = UNNotificationCategory(
              identifier: Self.categoryProcessAlert,
              actions: [viewAction, dismissAction],
              intentIdentifiers: [],
              options: []
          )

          let logKeywordCategory = UNNotificationCategory(
              identifier: Self.categoryLogKeyword,
              actions: [viewAction, dismissAction],
              intentIdentifiers: [],
              options: []
          )

          let certExpiryCategory = UNNotificationCategory(
              identifier: Self.categoryCertExpiry,
              actions: [viewAction, dismissAction],
              intentIdentifiers: [],
              options: []
          )

          UNUserNotificationCenter.current().setNotificationCategories([
              processAlertCategory,
              logKeywordCategory,
              certExpiryCategory
          ])
      }

      // MARK: - Existing: Command Complete

      func notifyCommandComplete(command: String, duration: TimeInterval) {
          guard duration >= 5 else { return }

          UNUserNotificationCenter.current().getNotificationSettings { settings in
              guard settings.authorizationStatus == .authorized else { return }

              let content = UNMutableNotificationContent()
              content.title = "Command finished"
              content.body = "$ \(command) (\(Int(duration))s)"
              content.sound = .default

              let request = UNNotificationRequest(
                  identifier: UUID().uuidString,
                  content: content,
                  trigger: nil
              )
              UNUserNotificationCenter.current().add(request)
          }
      }

      // MARK: - New: Process CPU Alert
      //
      // Call when a process in the active session exceeds a CPU threshold.
      // Example: NotificationManager.shared.scheduleProcessAlert(sessionName: "prod-01",
      //              process: "webpack", cpuPercent: 95.2)

      func scheduleProcessAlert(sessionName: String, process: String, cpuPercent: Double) {
          UNUserNotificationCenter.current().getNotificationSettings { settings in
              guard settings.authorizationStatus == .authorized else { return }

              let content = UNMutableNotificationContent()
              content.title = "High CPU — \(sessionName)"
              content.body = String(format: "%@ is using %.0f%% CPU", process, cpuPercent)
              content.sound = .default
              content.categoryIdentifier = Self.categoryProcessAlert
              content.userInfo = ["sessionName": sessionName, "process": process]

              // Fire after a 0.1 s delay (minimum non-zero interval)
              let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
              let request = UNNotificationRequest(
                  identifier: "process-alert-\(sessionName)-\(process)",
                  content: content,
                  trigger: trigger
              )
              UNUserNotificationCenter.current().add(request)
          }
      }

      // MARK: - New: Log Keyword Alert
      //
      // Call when a watched keyword (e.g. "ERROR", "FATAL") appears in session output.
      // Example: NotificationManager.shared.scheduleLogKeywordAlert(sessionName: "prod-01",
      //              keyword: "ERROR", line: "ERROR: disk full at /var/log")

      func scheduleLogKeywordAlert(sessionName: String, keyword: String, line: String) {
          UNUserNotificationCenter.current().getNotificationSettings { settings in
              guard settings.authorizationStatus == .authorized else { return }

              let truncatedLine = line.count > 100
                  ? String(line.prefix(97)) + "…"
                  : line

              let content = UNMutableNotificationContent()
              content.title = "[\(keyword)] — \(sessionName)"
              content.body = truncatedLine
              content.sound = .default
              content.categoryIdentifier = Self.categoryLogKeyword
              content.userInfo = ["sessionName": sessionName, "keyword": keyword]

              let request = UNNotificationRequest(
                  identifier: "log-keyword-\(sessionName)-\(UUID().uuidString)",
                  content: content,
                  trigger: nil   // fire immediately
              )
              UNUserNotificationCenter.current().add(request)
          }
      }

      // MARK: - New: Certificate Expiry Alert
      //
      // Call from a background certificate check.
      // Uses critical sound when <= 7 days remain, default otherwise.
      // Example: NotificationManager.shared.scheduleCertExpiryAlert(hostname: "prod-01.example.com",
      //              daysLeft: 5)

      func scheduleCertExpiryAlert(hostname: String, daysLeft: Int) {
          UNUserNotificationCenter.current().getNotificationSettings { settings in
              guard settings.authorizationStatus == .authorized else { return }

              let content = UNMutableNotificationContent()
              content.title = "Certificate Expiring Soon"
              content.body = daysLeft == 1
                  ? "\(hostname): certificate expires tomorrow!"
                  : "\(hostname): certificate expires in \(daysLeft) days."
              content.sound = daysLeft <= 7 ? .defaultCritical : .default
              content.categoryIdentifier = Self.categoryCertExpiry
              content.userInfo = ["hostname": hostname, "daysLeft": daysLeft]

              let request = UNNotificationRequest(
                  identifier: "cert-expiry-\(hostname)",
                  content: content,
                  trigger: nil   // fire immediately
              )
              UNUserNotificationCenter.current().add(request)
          }
      }
  }

  // MARK: - UNUserNotificationCenterDelegate

  extension NotificationManager: UNUserNotificationCenterDelegate {
      // Show notifications even when app is in foreground
      func userNotificationCenter(
          _ center: UNUserNotificationCenter,
          willPresent notification: UNNotification,
          withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
      ) {
          completionHandler([.banner, .sound])
      }

      // Handle action taps
      func userNotificationCenter(
          _ center: UNUserNotificationCenter,
          didReceive response: UNNotificationResponse,
          withCompletionHandler completionHandler: @escaping () -> Void
      ) {
          let userInfo = response.notification.request.content.userInfo

          switch response.actionIdentifier {
          case Self.actionViewSession:
              // If the notification carries a sessionName, activate that session.
              if let sessionName = userInfo["sessionName"] as? String {
                  Task { @MainActor in
                      if let session = SessionManager.shared.sessions.first(where: {
                          $0.connection.connectionInfo.hostname == sessionName ||
                          // Match against the Connection name stored in userInfo
                          (userInfo["sessionName"] as? String) == sessionName
                      }) {
                          SessionManager.shared.activate(session)
                      }
                  }
              }
          default:
              break
          }

          completionHandler()
      }
  }
  ```

- [ ] **3.2 — Build and verify**

  ```bash
  cd "/Users/ryancalpin/Documents/App Development/mosaic-ios" && xcodebuild build -scheme Mosaic -destination 'generic/platform=iOS Simulator' 2>&1 | grep -E 'error:|BUILD'
  ```

  Expected: `** BUILD SUCCEEDED **`

- [ ] **3.3 — Commit**

  ```bash
  cd "/Users/ryancalpin/Documents/App Development/mosaic-ios" && git add \
    Sources/Mosaic/Notifications/NotificationManager.swift && \
  git commit -m "feat: rich push notifications — process alert, log keyword, cert expiry with actionable categories"
  ```

---

## Completion Checklist

- [ ] All three tasks build cleanly with `** BUILD SUCCEEDED **`
- [ ] Hardware keyboard shortcuts: `⌘T`, `⌘W`, `⌘K`, `⌘1-9`, `⌘↑`, `⌘↓`, `⌃C` all respond correctly on iPad with keyboard attached
- [ ] `OpenServerIntent` appears in Shortcuts.app when the app has been launched at least once
- [ ] All three notification methods fire correctly; categories surface action buttons on long-press of the notification banner
- [ ] No regressions in existing session open/close/switch flows
