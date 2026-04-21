# CLAUDE.md — Mosaic iOS App

## What Is This?
Mosaic is a modern terminal runtime for iOS. It is NOT a terminal emulator wrapped in a nicer UI. It replaces the terminal's **rendering layer** entirely while keeping the actual shell intact. Commands run on a real remote server over SSH or Mosh. Output is intercepted, parsed, and rendered as native SwiftUI components. Users can always tap a badge to see the raw output underneath.

Think of it the same way OpenCode reimplemented Claude Code's TUI as a beautiful native app — same capabilities, entirely new surface.

Read `Docs/design-doc.md` and `Docs/technical-decisions.md` before writing any code. They contain every decision already made.

---

## Stack
- **Language:** Swift 5.9+, SwiftUI
- **Min Target:** iOS 17.0
- **Terminal emulator:** SwiftTerm (Swift Package)
- **SSH:** NMSSH (Swift Package, wraps libssh2)
- **Mosh:** mosh-apple from Blink Shell (Swift Package — see Mosh section below)
- **Local storage:** SwiftData
- **Cloud sync:** CloudKit (iCloud)
- **AI:** Claude API (Anthropic) — `claude-sonnet-4-6` for most things, `claude-opus-4-6` for the rendering engine

---

## Pre-Written Files
These files are already in the repo and define the core architecture. **Do not change the protocols without good reason — the whole system depends on them.**

| File | What It Is |
|---|---|
| `Sources/Mosaic/Core/TerminalConnection.swift` | Protocol all transports (SSH, Mosh) conform to |
| `Sources/Mosaic/Core/Session.swift` | Session state management |
| `Sources/Mosaic/Models/Connection.swift` | SwiftData model for saved connections |
| `Sources/Mosaic/Models/OutputBlock.swift` | SwiftData model for command output blocks |
| `Sources/Mosaic/Rendering/OutputRenderer.swift` | Protocol all renderers conform to |
| `Sources/Mosaic/Rendering/RendererRegistry.swift` | Singleton that routes output to the right renderer |
| `Sources/Mosaic/Rendering/Renderers/DockerPsRenderer.swift` | First native renderer — docker ps |
| `Sources/Mosaic/Rendering/Renderers/GitStatusRenderer.swift` | Second native renderer — git status |
| `Sources/Mosaic/Rendering/Renderers/FileListRenderer.swift` | Third native renderer — ls / ls -la |
| `Sources/Mosaic/Safety/SafetyClassifier.swift` | Classifies commands into safety tiers |

---

## Phase 1 Build Spec — Your Job Right Now

**Goal:** Working iOS app where Ryan can connect to a real server via SSH or Mosh, run commands, and see native rendered output for docker ps, git status, and ls. Raw toggle works on all three.

### Step 1: Project Setup
1. Generate the Xcode project from `project.yml` using XcodeGen (install with `brew install xcodegen` if not present, then run `xcodegen generate` in the repo root)
2. Open `Mosaic.xcodeproj` in Xcode
3. Set the Development Team in project settings (Ryan's Apple ID)
4. Resolve Swift Package dependencies — they're defined in `project.yml`
5. Confirm it builds (blank app is fine at this point)

### Step 2: SSH Connection (NMSSH)
Implement `SSHConnection` conforming to `TerminalConnection` protocol in `Sources/Mosaic/Core/SSHConnection.swift`:
- Connect to host with username + password or private key
- Expose `outputStream: AsyncStream<Data>` for raw terminal bytes
- Handle disconnect and errors gracefully
- Store credentials in Keychain (NOT in SwiftData or UserDefaults)
- Test: hardcode Ryan's prod-01 credentials temporarily, confirm raw terminal data flows

### Step 3: Mosh Connection (mosh-apple)
Implement `MoshConnection` conforming to `TerminalConnection` protocol:
- Use the mosh-apple Swift Package from Blink Shell: https://github.com/blinksh/mosh
- Mosh requires an initial SSH handshake to get the mosh-server key/port, then switches to UDP
- Expose the same `outputStream: AsyncStream<Data>` interface — the rendering engine must not know the difference
- Handle roaming (network change) — Mosh does this internally, just don't interfere
- If mosh-apple integration is blocked for any reason, implement SSH-only first and flag it clearly

### Step 4: SwiftTerm Integration
Embed SwiftTerm as the ground-truth terminal emulator:
- SwiftTerm handles VT100/xterm escape code processing, cursor position, color
- Tap SwiftTerm's output delegate to get the clean text stream for the rendering engine
- The rendering engine reads the SAME output as SwiftTerm — it does not bypass SwiftTerm
- SwiftTerm view is always present but hidden when a renderer is active

### Step 5: Rendering Engine
Wire up `RendererRegistry` to the output stream:
1. When a command is sent, register it with the registry (`registry.setActiveCommand(cmd)`)
2. When output arrives, pass it through `registry.process(output:)` 
3. Registry returns either a `RendererResult.native(renderer, data)` or `RendererResult.raw(text)`
4. Display accordingly

### Step 6: Native Tab Bar UI
Build the session tab bar (see `Docs/design-doc.md` → UX Flow for exact spec):
- Each tab shows: connection status dot (animated pulse when live), server name, protocol badge (MOSH purple / SSH blue)
- Active tab has accent underline
- `+` button opens connection sheet
- Close button `✕` on active tab
- Tabs scroll horizontally if overflow

### Step 7: Session View
The main content area:
- List of `OutputBlock` items, each rendered by the registry result
- **Native block:** `NativeBadge` view + the renderer's SwiftUI view
- **Raw block:** clean monospace `Text` view, no badge
- `NativeBadge` tap toggles between native and raw — animates with `fadeIn` transition
- Native badge label format: `NATIVE · [TYPE] · tap for raw`
- Raw badge format: `← RAW OUTPUT · tap for native`
- Infinite native scroll — no tmux, no scroll hijacking

### Step 8: Smart Input Bar
At the bottom of the session view:
- `TextField` with `JetBrains Mono` font
- On send: create `OutputBlock`, send command via active `TerminalConnection`
- `CodeCorrect` pill badge (tappable, shows on/off state — functionality comes in Phase 2)
- Mic button (non-functional in Phase 1, just shows the UI)
- Send button: accent green when text is present, muted when empty

### Step 9: Breadcrumb
Thin bar between tabs and session content:
- `user@hostname` (muted) `›` `~/current/path` (accent color) `  branch` `↑N`
- Path and branch update as the user navigates (parse `pwd` and `git branch --show-current` output automatically after each command)

### Step 10: Three Working Renderers
The pre-written renderer files have the parsing logic stubbed. Complete the implementations:
- `DockerPsRenderer` — parse `docker ps` tabular output, render container cards with status dot, name, ports, uptime
- `GitStatusRenderer` — parse `git status` output, render branch info + file status badges (M/D/?)
- `FileListRenderer` — parse `ls -la` output, render file list with icons, sizes, dates

Each renderer MUST:
- Return `nil` from `parse()` if output doesn't match — never partially render
- Fall through to raw gracefully
- Store raw output alongside rendered data for the toggle

---

## Key Design Rules (Never Violate These)
1. **The toggle contract:** every natively rendered block shows `NATIVE · [TYPE] · tap for raw`. Tap shows raw. Tap again shows native. The raw output is ALWAYS preserved.
2. **Never bypass SwiftTerm.** The rendering engine taps SwiftTerm's output, it doesn't replace it.
3. **The rendering engine never knows about SSH vs Mosh.** It talks only to `TerminalConnection`.
4. **If a renderer's `parse()` fails, fall through to raw instantly.** No partial renders, no crashes, no broken UI.
5. **Credentials go in Keychain only.** Not UserDefaults, not SwiftData, not anywhere else.
6. **Destructive commands do not execute without confirmation.** `SafetyClassifier` runs on every command before it's sent. Check it first.

---

## Color Palette (Match Exactly)
```swift
extension Color {
    static let mosaicBg         = Color(hex: "#09090B")
    static let mosaicSurface1   = Color(hex: "#111115")
    static let mosaicSurface2   = Color(hex: "#17171C")
    static let mosaicBorder     = Color(hex: "#1E1E26")
    static let mosaicAccent     = Color(hex: "#00D4AA")  // primary teal
    static let mosaicBlue       = Color(hex: "#4A9EFF")  // SSH badge
    static let mosaicPurple     = Color(hex: "#A78BFA")  // Mosh badge
    static let mosaicTextPri    = Color(hex: "#D8E4F0")
    static let mosaicTextSec    = Color(hex: "#3A4A58")
    static let mosaicTextMut    = Color(hex: "#1E2830")
    static let mosaicGreen      = Color(hex: "#3DFF8F")
    static let mosaicYellow     = Color(hex: "#FFD060")
    static let mosaicRed        = Color(hex: "#FF4D6A")
    static let mosaicWarn       = Color(hex: "#FFB020")
}
```

## Typography
- **UI text:** SF Pro (system default) — do NOT import a custom font
- **Terminal / code / output:** JetBrains Mono — include in the Xcode project as a bundled font resource
- **Badge labels:** JetBrains Mono, 8pt, weight .bold, letter spacing 0.4

---

## Mosh Notes
- mosh-apple requires the `Network.framework` entitlement and `com.apple.security.network.client` in the entitlements file
- The initial connection uses SSH (NMSSH) for the handshake, then mosh takes over via UDP
- On network change, mosh reconnects automatically — show a brief `↻ ROAMING` state in the tab badge
- If mosh-server is not installed on the remote, catch the error and offer SSH fallback with an alert

---

## What Phase 1 Is NOT
- No CodeCorrect intelligence (just the UI placeholder)
- No approval cards firing yet (SafetyClassifier exists but is not wired to the UI)
- No AI tab
- No iCloud sync
- No iPad split pane
- No connection manager UI (hardcode a connection for now if needed)

Get the core loop working first: connect → type command → see native output → toggle to raw.
