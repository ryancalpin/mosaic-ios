# Phase 1 Setup & Verification Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Get the fully-implemented Phase 1 Mosaic app building, running on simulator, and verified end-to-end with a real SSH connection.

**Architecture:** All Phase 1 code is already written in `mosaic/Sources/Mosaic/`. The Xcode project is generated from `project.yml` via XcodeGen. The app connects over SSH (NMSSH), feeds output through SwiftTerm (VT100), then routes it through RendererRegistry → native SwiftUI views with a raw toggle.

**Tech Stack:** Swift 5.9+, SwiftUI, iOS 17+, NMSSH, SwiftTerm, SwiftData

---

### Task 1: Repository Cleanup

**Files:**
- Delete: `mosaic-ios/` (entire directory — default Xcode template, not the real project)
- Git: unstage all `mosaic-ios/` files from index

- [ ] **Step 1: Unstage and delete the template project**

```bash
cd /Users/ryancalpin/Documents/App\ Development/mosaic-ios
git restore --staged mosaic-ios/
rm -rf mosaic-ios/
```

Expected: `mosaic-ios/` directory gone. `git status` shows clean working tree (no staged files).

- [ ] **Step 2: Verify clean state**

```bash
git status
```

Expected: `nothing to commit, working tree clean` (the `mosaic/` files are already committed).

- [ ] **Step 3: Commit cleanup**

```bash
git add -A
git commit -m "chore: remove stale Xcode template scaffold (mosaic-ios/)"
```

---

### Task 2: Create Xcode Project via XcodeGen

**Files:**
- Create (generated): `mosaic/Mosaic.xcodeproj/` — git-ignored per `.gitignore`
- Create (downloaded): `mosaic/Resources/JetBrainsMono-Regular.ttf`
- Create (downloaded): `mosaic/Resources/JetBrainsMono-Bold.ttf`
- Create (downloaded): `mosaic/Resources/JetBrainsMono-SemiBold.ttf`

- [ ] **Step 1: Run setup.sh**

```bash
cd /Users/ryancalpin/Documents/App\ Development/mosaic-ios/mosaic
./setup.sh
```

Expected output ends with:
```
✅ Done! Next steps:
   1. Open Mosaic.xcodeproj in Xcode
   ...
```

If XcodeGen isn't installed: `brew install xcodegen` (setup.sh does this automatically).

- [ ] **Step 2: Verify project was generated**

```bash
ls -la /Users/ryancalpin/Documents/App\ Development/mosaic-ios/mosaic/Mosaic.xcodeproj/
ls /Users/ryancalpin/Documents/App\ Development/mosaic-ios/mosaic/Resources/
```

Expected: `Mosaic.xcodeproj` directory exists with `project.pbxproj`. Resources contains three `.ttf` files.

- [ ] **Step 3: Commit the plans directory**

```bash
cd /Users/ryancalpin/Documents/App\ Development/mosaic-ios
git add mosaic/Docs/plans/
git commit -m "docs: add phase 1 setup & verification plan"
```

---

### Task 3: First Build in Xcode

**Performed manually in Xcode — Claude cannot type into Xcode.**

- [ ] **Step 1: Open the project**

```bash
open /Users/ryancalpin/Documents/App\ Development/mosaic-ios/mosaic/Mosaic.xcodeproj
```

- [ ] **Step 2: Set Development Team**

Xcode → `Mosaic` target → Signing & Capabilities → Team → select Ryan's Apple ID.
Bundle ID is `com.ryncalpin.mosaic` (set in `project.yml`).

- [ ] **Step 3: Let SPM resolve dependencies**

Xcode resolves automatically on first open. Two packages:
- `NMSSH` from `https://github.com/NMSSH/NMSSH` ≥ 2.3.2
- `SwiftTerm` from `https://github.com/migueldeicaza/SwiftTerm` ≥ 1.2.0

Wait for "Resolving package graph..." to complete in the status bar.

- [ ] **Step 4: Build for simulator**

Select `Mosaic` scheme + `iPhone 16 Pro` simulator → `⌘B`.

Expected: `** BUILD SUCCEEDED **` with zero errors.

If any errors occur, check:
- Missing font files in `Resources/` → re-run `setup.sh`
- Missing package → File → Packages → Resolve Package Versions
- Signing error → confirm Team is set

- [ ] **Step 5: Run on simulator**

`⌘R` to launch. Expected: app opens showing `EmptyStateView` ("No sessions") with a `+` button in the center.

---

### Task 4: End-to-End SSH Connection Test

**Test server:** prod-01 (Ryan's dev server). Use the `NewConnectionForm` in the app UI.

- [ ] **Step 1: Add a connection in the app**

Tap `+` → fill in:
- Name: `prod-01`
- Hostname: your server's IP/hostname
- Port: `22`
- Username: your username
- Authentication: Password or SSH key

Tap Save → tap the card → tab opens.

Expected: tab bar shows `prod-01` with animated green status dot, `SSH` badge, and BreadcrumbBar showing `user@hostname › ~/`.

- [ ] **Step 2: Verify breadcrumb updates**

Run:
```
cd /tmp
```

Expected: BreadcrumbBar path changes from `~/` to `/tmp`.

- [ ] **Step 3: Verify raw output**

Run:
```
echo "hello mosaic"
```

Expected: output block appears with `› echo "hello mosaic"` header and `hello mosaic` in monospace below. No native badge (raw output).

---

### Task 5: Three Renderer Verification

- [ ] **Step 1: FileListRenderer**

```bash
ls -la
```

Expected: `OutputBlockView` shows a `FILE LIST` badge above a styled table with filename + size + modified columns. Tap the badge → raw text toggle works. Tap again → native view returns.

- [ ] **Step 2: GitStatusRenderer**

Navigate to a git repository:
```bash
cd /path/to/any/git/repo
git status
```

Expected: `GIT STATUS` badge, branch header row with `🌿 main`, file rows with colored `M`/`?`/`D`/`S` badges. Toggle works.

If the server has no git repos at hand, create one:
```bash
mkdir /tmp/test-repo && cd /tmp/test-repo && git init && touch foo.txt && git status
```

Expected: `GIT STATUS` badge, `main` branch, `? foo.txt` row.

- [ ] **Step 3: DockerPsRenderer**

On a server with Docker:
```bash
docker ps
```

Expected: `CONTAINERS` badge, container cards with status dot, name, image, ports.

If Docker isn't available on the test server, verify graceful raw fallback by confirming no badge and clean monospace output.

- [ ] **Step 4: Safety classifier smoke test**

Type (do NOT send):
```
sudo rm -rf /tmp/testdir
```

Expected: `ApprovalCardView` appears before execution — hold-to-confirm or cancel. Cancel → command stays in input field.

---

### Task 6: Simulator Screenshots & Final Commit

- [ ] **Step 1: Take simulator screenshots via XcodeBuildMCP**

Use `mcp__xcodebuildmcp__screenshot` to capture:
1. Empty state (no sessions)
2. Active session with FileListRenderer output
3. Active session with GitStatusRenderer output
4. NativeBadge in raw mode (after toggle)

- [ ] **Step 2: Confirm Phase 1 checklist**

Verify all CLAUDE.md Phase 1 goals are met:
- [x] SSH connection to real server
- [x] Command output flows through SwiftTerm
- [x] RendererRegistry routes to correct renderer
- [x] DockerPsRenderer (or graceful fallback)
- [x] GitStatusRenderer
- [x] FileListRenderer
- [x] Toggle contract: NATIVE badge ↔ raw
- [x] Breadcrumb updates on `cd`
- [x] Smart input bar with SafetyClassifier gating

- [ ] **Step 3: Commit verified state**

```bash
cd /Users/ryancalpin/Documents/App\ Development/mosaic-ios
git add mosaic/Docs/plans/
git commit -m "feat: phase 1 complete — SSH connection, three renderers, toggle verified"
```
