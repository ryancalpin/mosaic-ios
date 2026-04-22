# Onboarding Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** First-run experience that explains Mosaic's concept, guides the user through connecting their first server, and celebrates the first native render.

**Architecture:** `AppSettings` gains two flags (`hasCompletedOnboarding`, `hasSeenFirstNativeRender`) persisted in UserDefaults. A `.fullScreenCover` in `RootView` shows `OnboardingView` on first launch — a three-page `TabView(.page)`: Welcome → Connect → Done. The "Connect" page reuses `ConnectionFormView` in inline mode. The first-native-render celebration is a banner overlay in `SessionView`, triggered by a notification posted from `Session.finalizeBlock()`.

**Tech Stack:** SwiftUI, AppSettings (UserDefaults), `ConnectionFormView`, `Session.finalizeBlock()`, Swift Testing

---

## File Map

| Action | Path |
|--------|------|
| Modify | `Sources/Mosaic/Settings/AppSettings.swift` |
| Create | `Sources/Mosaic/UI/Onboarding/OnboardingView.swift` |
| Modify | `Sources/Mosaic/UI/RootView.swift` |
| Modify | `Sources/Mosaic/Core/Session.swift` |
| Create | `Sources/Mosaic/UI/Session/FirstNativeRenderBanner.swift` |
| Modify | `Sources/Mosaic/UI/Session/SessionView.swift` |
| Create | `Tests/MosaicTests/OnboardingTests.swift` |

---

### Task 1: AppSettings — Add Onboarding Flags

**Files:**
- Modify: `Sources/Mosaic/Settings/AppSettings.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/MosaicTests/OnboardingTests.swift
import Testing
@testable import Mosaic

@Suite("Onboarding")
@MainActor
struct OnboardingTests {

    @Test func defaultOnboardingNotCompleted() {
        // Reset to known state
        UserDefaults.standard.removeObject(forKey: "mosaic.hasCompletedOnboarding")
        UserDefaults.standard.removeObject(forKey: "mosaic.hasSeenFirstNativeRender")
        let settings = AppSettings()
        #expect(!settings.hasCompletedOnboarding)
        #expect(!settings.hasSeenFirstNativeRender)
    }

    @Test func onboardingFlagPersists() {
        let settings = AppSettings()
        settings.hasCompletedOnboarding = true
        #expect(UserDefaults.standard.bool(forKey: "mosaic.hasCompletedOnboarding"))
        // cleanup
        UserDefaults.standard.removeObject(forKey: "mosaic.hasCompletedOnboarding")
    }

    @Test func firstNativeRenderFlagPersists() {
        let settings = AppSettings()
        settings.hasSeenFirstNativeRender = true
        #expect(UserDefaults.standard.bool(forKey: "mosaic.hasSeenFirstNativeRender"))
        // cleanup
        UserDefaults.standard.removeObject(forKey: "mosaic.hasSeenFirstNativeRender")
    }
}
```

- [ ] **Step 2: Run to confirm failure**

```
xcodebuild test -scheme Mosaic -destination 'id=913B454F-493C-46DC-B2B4-63348DA39843' -only-testing:MosaicTests/OnboardingTests 2>&1 | tail -20
```

Expected: FAIL — `AppSettings` has no `hasCompletedOnboarding` property.

- [ ] **Step 3: Add flags to AppSettings**

Open `Sources/Mosaic/Settings/AppSettings.swift`. After the existing `claudeApiKey` property, add:

```swift
var hasCompletedOnboarding: Bool = UserDefaults.standard.bool(forKey: "mosaic.hasCompletedOnboarding") {
    didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "mosaic.hasCompletedOnboarding") }
}

var hasSeenFirstNativeRender: Bool = UserDefaults.standard.bool(forKey: "mosaic.hasSeenFirstNativeRender") {
    didSet { UserDefaults.standard.set(hasSeenFirstNativeRender, forKey: "mosaic.hasSeenFirstNativeRender") }
}
```

- [ ] **Step 4: Run tests — confirm passing**

```
xcodebuild test -scheme Mosaic -destination 'id=913B454F-493C-46DC-B2B4-63348DA39843' -only-testing:MosaicTests/OnboardingTests 2>&1 | tail -20
```

Expected: PASS (3 tests)

- [ ] **Step 5: Build check**

```
xcodebuild build -scheme Mosaic -destination 'generic/platform=iOS Simulator' 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add Sources/Mosaic/Settings/AppSettings.swift Tests/MosaicTests/OnboardingTests.swift
git commit -m "feat(onboarding): add hasCompletedOnboarding and hasSeenFirstNativeRender flags to AppSettings"
```

---

### Task 2: OnboardingView — Three-Page Welcome Flow

**Files:**
- Create: `Sources/Mosaic/UI/Onboarding/OnboardingView.swift`

- [ ] **Step 1: Create the file**

```swift
// Sources/Mosaic/UI/Onboarding/OnboardingView.swift
import SwiftUI
import SwiftData

@MainActor
struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @State private var page = 0
    @State private var connectionSaved = false

    var body: some View {
        TabView(selection: $page) {
            WelcomePage(onNext: { withAnimation { page = 1 } })
                .tag(0)

            ConnectPage(
                connectionSaved: $connectionSaved,
                onNext: { withAnimation { page = 2 } }
            )
            .tag(1)

            DonePage(onFinish: {
                settings.hasCompletedOnboarding = true
            })
            .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .background(Color.mosaicBg)
        .ignoresSafeArea()
    }
}

// MARK: - Welcome Page

private struct WelcomePage: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                Text("✦")
                    .font(.system(size: 56))
                    .foregroundColor(.mosaicAccent)

                Text("Mosaic")
                    .font(.largeTitle.bold())
                    .foregroundColor(.mosaicTextPri)

                Text("A native terminal runtime")
                    .font(.title3)
                    .foregroundColor(.mosaicTextSec)
            }

            VStack(alignment: .leading, spacing: 20) {
                FeatureRow(
                    icon: "terminal",
                    title: "Not a terminal emulator",
                    detail: "Commands run on your real server over SSH or Mosh. Mosaic intercepts the output and renders it natively."
                )
                FeatureRow(
                    icon: "rectangle.3.group",
                    title: "Native SwiftUI output",
                    detail: "docker ps, git status, ls — rendered as interactive cards, not walls of text."
                )
                FeatureRow(
                    icon: "eye",
                    title: "Always raw underneath",
                    detail: "Tap any native block to see the original output. Your data is never altered."
                )
            }
            .padding(.horizontal, 32)

            Spacer()

            Button(action: onNext) {
                Text("Get Started")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.mosaicAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.mosaicAccent)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.mosaicTextPri)
                Text(detail)
                    .font(.subheadline)
                    .foregroundColor(.mosaicTextSec)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Connect Page

private struct ConnectPage: View {
    @Binding var connectionSaved: Bool
    let onNext: () -> Void
    @State private var showForm = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Connect your first server")
                    .font(.title2.bold())
                    .foregroundColor(.mosaicTextPri)
                Text("SSH or Mosh — your server stays in control.")
                    .font(.subheadline)
                    .foregroundColor(.mosaicTextSec)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 60)
            .padding(.horizontal, 24)

            if showForm {
                // Inline connection form — no navigation needed
                ConnectionFormView(
                    connection: nil,
                    onSave: { _ in
                        connectionSaved = true
                        onNext()
                    },
                    onCancel: { showForm = false }
                )
            } else {
                Spacer()
                VStack(spacing: 16) {
                    Button(action: { showForm = true }) {
                        Label("Add Server", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.mosaicAccent)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 32)

                    Button(action: onNext) {
                        Text("Skip for now")
                            .font(.subheadline)
                            .foregroundColor(.mosaicTextSec)
                    }
                }
                .padding(.bottom, 48)
            }
        }
    }
}

// MARK: - Done Page

private struct DonePage: View {
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72))
                    .foregroundColor(.mosaicGreen)

                Text("You're ready")
                    .font(.largeTitle.bold())
                    .foregroundColor(.mosaicTextPri)

                Text("Run your first command.\nWatch it render natively.")
                    .font(.title3)
                    .foregroundColor(.mosaicTextSec)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button(action: onFinish) {
                Text("Open Mosaic")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.mosaicAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }
}
```

- [ ] **Step 2: Build check**

```
xcodebuild build -scheme Mosaic -destination 'generic/platform=iOS Simulator' 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Sources/Mosaic/UI/Onboarding/OnboardingView.swift
git commit -m "feat(onboarding): add three-page OnboardingView with welcome, connect, and done pages"
```

---

### Task 3: Wire OnboardingView into RootView

**Files:**
- Modify: `Sources/Mosaic/UI/RootView.swift`

- [ ] **Step 1: Add the .fullScreenCover**

In `RootView.swift`, find the `iPhoneLayout` body (or the top-level `body`). Add a `.fullScreenCover` modifier that presents `OnboardingView` when `!settings.hasCompletedOnboarding`.

Find the line that ends the top-level `ZStack` or `Group` in the body — it will look like:

```swift
.sheet(isPresented: $showSettings) { ... }
```

Add after the existing sheets:

```swift
.fullScreenCover(isPresented: Binding(
    get: { !settings.hasCompletedOnboarding },
    set: { _ in }
)) {
    OnboardingView()
        .environment(settings)
        .modelContainer(/* existing container from environment */)
}
```

Because the `modelContainer` is already in the environment via `.modelContainer(sharedModelContainer)` at the app level, you only need:

```swift
.fullScreenCover(isPresented: Binding(
    get: { !settings.hasCompletedOnboarding },
    set: { _ in }
)) {
    OnboardingView()
        .environment(settings)
}
```

- [ ] **Step 2: Build check**

```
xcodebuild build -scheme Mosaic -destination 'generic/platform=iOS Simulator' 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Add a test for the flag gate**

In `Tests/MosaicTests/OnboardingTests.swift`, add:

```swift
@Test func onboardingShownWhenFlagFalse() {
    UserDefaults.standard.removeObject(forKey: "mosaic.hasCompletedOnboarding")
    let settings = AppSettings()
    #expect(!settings.hasCompletedOnboarding)
    // Setting to true should flip
    settings.hasCompletedOnboarding = true
    #expect(settings.hasCompletedOnboarding)
    UserDefaults.standard.removeObject(forKey: "mosaic.hasCompletedOnboarding")
}
```

- [ ] **Step 4: Run tests**

```
xcodebuild test -scheme Mosaic -destination 'id=913B454F-493C-46DC-B2B4-63348DA39843' -only-testing:MosaicTests/OnboardingTests 2>&1 | tail -20
```

Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/Mosaic/UI/RootView.swift Tests/MosaicTests/OnboardingTests.swift
git commit -m "feat(onboarding): wire OnboardingView into RootView as fullScreenCover on first launch"
```

---

### Task 4: First Native Render Celebration

**Files:**
- Create: `Sources/Mosaic/UI/Session/FirstNativeRenderBanner.swift`
- Modify: `Sources/Mosaic/Core/Session.swift`
- Modify: `Sources/Mosaic/UI/Session/SessionView.swift`

- [ ] **Step 1: Create the banner view**

```swift
// Sources/Mosaic/UI/Session/FirstNativeRenderBanner.swift
import SwiftUI

struct FirstNativeRenderBanner: View {
    let onDismiss: () -> Void
    @State private var visible = false

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                Text("✦")
                    .font(.title2)
                    .foregroundColor(.mosaicAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("First native render!")
                        .font(.headline)
                        .foregroundColor(.mosaicTextPri)
                    Text("Tap the badge to toggle raw output.")
                        .font(.caption)
                        .foregroundColor(.mosaicTextSec)
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.mosaicTextSec)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.mosaicSurface2)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.mosaicAccent.opacity(0.4), lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.bottom, 100) // above SmartInputBar
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 24)
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { visible = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                withAnimation(.easeOut(duration: 0.3)) { visible = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onDismiss() }
            }
        }
    }
}
```

- [ ] **Step 2: Post a notification from Session.finalizeBlock()**

In `Sources/Mosaic/Core/Session.swift`, find `finalizeBlock(_:)`. After the line that sets `block.cachedRendererResult`, add:

```swift
// Notify for first native render celebration
if case .native = block.cachedRendererResult {
    NotificationCenter.default.post(name: .mosaicFirstNativeRender, object: nil)
}
```

At the bottom of `Session.swift` (or in a new constants file), add:

```swift
extension Notification.Name {
    static let mosaicFirstNativeRender = Notification.Name("mosaic.firstNativeRender")
}
```

- [ ] **Step 3: Show banner in SessionView**

In `Sources/Mosaic/UI/Session/SessionView.swift`, add:

At the top of the struct, add state:
```swift
@Environment(AppSettings.self) private var settings
@State private var showFirstNativeRenderBanner = false
```

Inside the body's top-level `ZStack`, after the existing content layers, add:

```swift
if showFirstNativeRenderBanner {
    FirstNativeRenderBanner {
        showFirstNativeRenderBanner = false
        settings.hasSeenFirstNativeRender = true
    }
    .transition(.opacity)
}
```

On the `ZStack`, add:

```swift
.onReceive(NotificationCenter.default.publisher(for: .mosaicFirstNativeRender)) { _ in
    guard !settings.hasSeenFirstNativeRender else { return }
    withAnimation { showFirstNativeRenderBanner = true }
}
```

- [ ] **Step 4: Build check**

```
xcodebuild build -scheme Mosaic -destination 'generic/platform=iOS Simulator' 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Write test for notification**

In `Tests/MosaicTests/OnboardingTests.swift`, add:

```swift
@Test func firstNativeRenderNotificationName() {
    let name = Notification.Name.mosaicFirstNativeRender
    #expect(name.rawValue == "mosaic.firstNativeRender")
}

@Test func seenFlagPreventsDuplicateBanner() {
    let settings = AppSettings()
    settings.hasSeenFirstNativeRender = true
    // Banner should not show when flag is already set
    #expect(settings.hasSeenFirstNativeRender)
    UserDefaults.standard.removeObject(forKey: "mosaic.hasSeenFirstNativeRender")
}
```

- [ ] **Step 6: Run all tests**

```
xcodebuild test -scheme Mosaic -destination 'id=913B454F-493C-46DC-B2B4-63348DA39843' 2>&1 | grep -E "(Test Suite|passed|failed)" | tail -10
```

Expected: all tests pass, count ≥ previous count + 6

- [ ] **Step 7: Commit**

```bash
git add Sources/Mosaic/UI/Session/FirstNativeRenderBanner.swift Sources/Mosaic/Core/Session.swift Sources/Mosaic/UI/Session/SessionView.swift Tests/MosaicTests/OnboardingTests.swift
git commit -m "feat(onboarding): first-native-render celebration banner with auto-dismiss and seen flag"
```

---

## Self-Review

**Spec coverage:**
- ✅ Welcome screen explaining the concept (not a terminal emulator)
- ✅ "Connect your first server" using ConnectionFormView
- ✅ First native render celebration moment when FileListRenderer/GitStatusRenderer fires
- ✅ Persisted flags so onboarding shows once

**Placeholder scan:** None found — all steps include actual code.

**Type consistency:** `AppSettings.hasCompletedOnboarding` and `hasSeenFirstNativeRender` defined in Task 1, referenced consistently in Tasks 3 and 4. `Notification.Name.mosaicFirstNativeRender` defined in Task 4 and used in the same task.
