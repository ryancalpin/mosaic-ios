# Mosaic iOS — Comprehensive Test Plan

**Target:** Phase 1 complete (SSH + Mosh + 3 renderers + full UI)  
**Devices:** iPhone SE 3rd gen (small), iPhone 15 Pro (standard), iPad (split-view future)  
**OS:** iOS 26.0+  
**Test environment:** Xcode 26.4, iPhone 17 Pro simulator, physical device with real server

---

## How to Use This Document

Tests are grouped by area. Each test has:
- **Setup** — preconditions
- **Steps** — exact actions
- **Expected** — what must be true to pass
- **Pass criteria** — binary pass/fail

Run the full suite before any release. Run the relevant section after any code change.

---

## 1. Build Verification

### T-BUILD-1: Clean build succeeds
- **Steps:** `Product → Clean Build Folder`, then `Cmd+B`
- **Expected:** `** BUILD SUCCEEDED **`, zero errors, warnings acceptable
- **Pass:** ✓ No errors

### T-BUILD-2: Simulator launch
- **Steps:** Run on iPhone 17 Pro simulator
- **Expected:** App launches to EmptyStateView without crash
- **Pass:** ✓ App running, no crash log

---

## 2. Empty State & Initial Load

### T-EMPTY-1: Empty state shown on first launch
- **Setup:** Fresh install or cleared data
- **Steps:** Launch app
- **Expected:** "Connect to a server" prompt visible, "+" button visible, no sessions in tab bar
- **Pass:** ✓

### T-EMPTY-2: "+" button opens connection sheet
- **Steps:** Tap "+" in tab bar
- **Expected:** ConnectionSheet slides up as modal sheet
- **Pass:** ✓

### T-EMPTY-3: Empty state gone after first connection
- **Setup:** Successful connection established
- **Steps:** Observe root view
- **Expected:** SessionView replaces EmptyStateView, tab bar shows one tab
- **Pass:** ✓

---

## 3. Connection Sheet — New Connection Form

### T-FORM-1: Default state
- **Steps:** Open ConnectionSheet → tap "New Connection" tab
- **Expected:** Hostname empty, port shows "22", username empty, transport = SSH, auth = Password
- **Pass:** ✓

### T-FORM-2: Port updates when transport changes
- **Steps:** Change transport picker to MOSH
- **Expected:** Port field updates to "60001" (or mosh default)
- **Steps (2):** Change back to SSH
- **Expected:** Port reverts to "22"
- **Pass:** ✓

### T-FORM-3: Connect button disabled with empty fields
- **Steps:** Leave hostname empty, tap Connect
- **Expected:** Nothing happens or button is visually disabled; no crash; no connection attempt
- **Pass:** ✓

### T-FORM-4: Auth method toggles credential input
- **Steps:** Select "Private Key" auth method
- **Expected:** SecureField (password) replaced by multi-line TextField for key paste
- **Steps (2):** Switch back to Password
- **Expected:** Password SecureField shown again
- **Pass:** ✓

### T-FORM-5: Credentials stored in Keychain, not visible in form after navigation
- **Steps:** Enter password, connect, disconnect, re-open ConnectionSheet, select same server
- **Expected:** Password field empty (not pre-filled from Keychain), but connection still works
- **Pass:** ✓ (Keychain read happens at connect time, never displayed back)

---

## 4. SSH Connection

### T-SSH-1: Password auth — successful connection
- **Setup:** Valid server with password auth enabled
- **Steps:** Fill form (hostname, port, username, password), tap Connect
- **Expected:**
  - Sheet dismisses
  - Tab appears with hostname, "SSH" blue badge
  - Status dot: blue (connecting) → green (connected) with pulse animation
  - BreadcrumbBar shows `username@hostname › ~`
- **Pass:** ✓

### T-SSH-2: Private key auth — successful connection
- **Setup:** Valid server, SSH key auth configured
- **Steps:** Paste PEM private key (test with Ed25519, P256 keys), connect
- **Expected:** Same as T-SSH-1
- **Pass:** ✓ Test with at least 2 key types

### T-SSH-3: Wrong password shows error alert
- **Setup:** Valid host, wrong password
- **Steps:** Connect with bad credentials
- **Expected:** Error alert: "Authentication failed. Check credentials." Tab not added.
- **Pass:** ✓

### T-SSH-4: Unreachable host shows error alert
- **Setup:** Non-existent hostname or blocked port
- **Steps:** Connect
- **Expected:** Error alert: "Host unreachable…" after reasonable timeout (≤30s)
- **Pass:** ✓

### T-SSH-5: Disconnect via close button
- **Setup:** Active SSH session
- **Steps:** Tap "✕" close button on active tab
- **Expected:** Tab removed immediately from UI; connection closes async; no hanging
- **Pass:** ✓

### T-SSH-6: Session survives app backgrounding briefly
- **Steps:** Background app for 10 seconds, foreground
- **Expected:** SSH session still connected (iOS keeps socket alive briefly); tab shows green dot
- **Pass:** ✓ (may disconnect after longer background; that is expected)

---

## 5. Mosh Connection

### T-MOSH-1: Successful mosh connection
- **Setup:** Server with mosh-server installed
- **Steps:** Select MOSH transport, connect
- **Expected:**
  - Bootstrap: SSH handshake completes, mosh-server starts, UDP session established
  - Tab shows "MOSH" purple badge, green pulsing status dot
  - BreadcrumbBar shows `username@hostname › ~`
  - Terminal responsive to input
- **Pass:** ✓

### T-MOSH-2: mosh-server not installed — shows actionable error
- **Setup:** Server without mosh-server installed
- **Steps:** Connect via MOSH
- **Expected:** Error alert: "mosh-server not found on remote. Install it or use SSH."
- **Pass:** ✓

### T-MOSH-3: Mosh output indistinguishable from SSH at app level
- **Steps:** Run `echo hello`, `ls`, `git status` on both SSH and Mosh sessions
- **Expected:** Same renderer behavior, same native/raw toggle, identical UX
- **Pass:** ✓

### T-MOSH-4: Mosh roaming — network change
- **Steps:** Connect via Mosh, disable WiFi, re-enable WiFi (or switch to cellular)
- **Expected:** Tab badge briefly shows "↻ ROAMING" (yellow), then returns to "MOSH" (purple); session not lost; shell still responsive
- **Pass:** ✓

### T-MOSH-5: Mosh disconnect
- **Setup:** Active Mosh session
- **Steps:** Tap "✕" close button
- **Expected:** Stdin pipe closes → mosh_main exits → thread finishes; tab removed; no zombie thread
- **Pass:** ✓

---

## 6. Multiple Sessions (Tab Management)

### T-TABS-1: Open second session
- **Setup:** One active session
- **Steps:** Tap "+" → connect to another server (can be same server)
- **Expected:** Second tab appears in tab bar; second tab becomes active; first session's content preserved
- **Pass:** ✓

### T-TABS-2: Switch between sessions
- **Setup:** Two active sessions
- **Steps:** Tap first tab
- **Expected:** SessionView immediately switches to first session's output history; BreadcrumbBar updates; no data loss in second session
- **Pass:** ✓

### T-TABS-3: Tab bar scrolls with many sessions
- **Setup:** 4+ sessions
- **Steps:** Swipe left/right on tab bar
- **Expected:** Tab bar scrolls horizontally; all tabs accessible; active tab visible with accent underline
- **Pass:** ✓

### T-TABS-4: Close non-active tab
- **Setup:** Two sessions; second is active
- **Steps:** Tap first tab to activate it; tap "✕"
- **Expected:** First tab removed; second session becomes active; second session's state unchanged
- **Pass:** ✓

### T-TABS-5: Close last tab returns to empty state
- **Setup:** One session
- **Steps:** Close tab
- **Expected:** EmptyStateView shown, tab bar shows only "+"
- **Pass:** ✓

### T-TABS-6: Status dot colors are correct
| State | Expected color |
|---|---|
| Connecting | Blue, no pulse |
| Connected | Green, pulsing |
| Roaming | Yellow, no pulse |
| Disconnected | Gray/muted |
| Error | Red |
- **Pass:** ✓ Verify each state by observing tab during connection lifecycle

---

## 7. Command Input & Smart Input Bar

### T-INPUT-1: Send button disabled when empty
- **Steps:** Open session with empty input bar
- **Expected:** Send button muted color; tapping has no effect
- **Pass:** ✓

### T-INPUT-2: Send button green when text present
- **Steps:** Type any character in input bar
- **Expected:** Send button turns accent green immediately
- **Pass:** ✓

### T-INPUT-3: Send clears input field
- **Steps:** Type `echo hello`, tap send
- **Expected:** Command sent; input field clears; send button returns to muted
- **Pass:** ✓

### T-INPUT-4: JetBrains Mono font in input bar
- **Steps:** Type text in input bar
- **Expected:** Monospace font rendered (visually distinct from system font); confirm it's JetBrains Mono via Accessibility Inspector
- **Pass:** ✓

### T-INPUT-5: No autocorrect or autocapitalize
- **Steps:** Type `docker ps` — observe iOS autocorrect suggestions
- **Expected:** No red underlines; no autocorrect popups; no capitalization of first letter
- **Pass:** ✓

### T-INPUT-6: Mic button visible but non-functional
- **Steps:** Tap mic button
- **Expected:** No action (Phase 1 placeholder); button visible, tappable with no crash
- **Pass:** ✓

### T-INPUT-7: CodeCorrect pill visible but toggles show/hide only
- **Steps:** Tap CodeCorrect pill
- **Expected:** Visual toggle state changes (on/off); no AI functionality in Phase 1; no crash
- **Pass:** ✓

---

## 8. Safety Classifier

### T-SAFETY-SAFE: Safe command sends immediately
- **Steps:** Type `ls -la`, tap send
- **Expected:** No approval card; command sent immediately; OutputBlock appears
- **Pass:** ✓

### T-SAFETY-T3: Tier 3 auto-dismiss warning
- **Steps:** Type `sudo apt update`, tap send
- **Expected:**
  - ApprovalCardView slides in inline
  - Reason shown ("Elevated privileges requested" or similar)
  - Green Confirm button visible
  - If no action taken: auto-dismisses in ~1.5s, command NOT sent
  - Input bar text remains for review
- **Pass:** ✓

### T-SAFETY-T3-CONFIRM: Tier 3 can be confirmed
- **Steps:** Type `sudo apt update`, tap send, tap Confirm before 1.5s
- **Expected:** Card dismisses; command sent; OutputBlock appears
- **Pass:** ✓

### T-SAFETY-T3-CANCEL: Tier 3 cancel
- **Steps:** Type `sudo apt update`, tap send, tap Cancel
- **Expected:** Card dismisses; command NOT sent; text remains in input bar
- **Pass:** ✓

### T-SAFETY-T2: Tier 2 explicit confirm
- **Steps:** Type `rm -r ~/testfolder`, tap send
- **Expected:**
  - ApprovalCardView shown
  - Green "Confirm" button (single tap)
  - "Cancel" button
  - NO auto-dismiss (waits indefinitely for user)
- **Pass:** ✓

### T-SAFETY-T2-HOLD: Tier 1 requires hold gesture
- **Steps:** Type `sudo rm -rf /`, tap send
- **Expected:**
  - ApprovalCardView shown
  - Red "Hold to Confirm" button (NOT a tap — requires 1.5s continuous hold)
  - Brief tap does NOT confirm; button animation resets on release
  - Full 1.5s hold confirms and sends
  - "Cancel" button visible and functional
- **Pass:** ✓

### T-SAFETY-T2-CANCEL: Tier 2/1 cancel
- **Steps:** Any destructive command → approval card → Cancel
- **Expected:** Card dismissed; command NOT sent; input text preserved
- **Pass:** ✓

---

## 9. Output Rendering — Session & OutputBlocks

### T-OUTPUT-1: OutputBlock appears per command
- **Steps:** Send `echo hello`
- **Expected:** New OutputBlock with `› echo hello` appears; output `hello` appears below
- **Pass:** ✓

### T-OUTPUT-2: Streaming indicator during output
- **Steps:** Send a command with slow output (e.g., `ping 8.8.8.8`)
- **Expected:** Spinner/progress indicator visible next to command while output is streaming
- **Pass:** ✓

### T-OUTPUT-3: Auto-scroll to latest block
- **Steps:** Send multiple commands in sequence; scroll up mid-stream; send another command
- **Expected:** View auto-scrolls to new block when output arrives; does NOT force-scroll while user is manually scrolled up (if implemented)
- **Pass:** ✓

### T-OUTPUT-4: Raw text block — monospace font
- **Steps:** Run any command that falls through to raw (e.g., `top` partial output, non-supported command)
- **Expected:** Output rendered in JetBrains Mono; selectable text; word-wrapping at screen edge
- **Pass:** ✓

### T-OUTPUT-5: Text selection in raw blocks
- **Steps:** Long-press raw output text
- **Expected:** Native iOS text selection handles appear; can copy to clipboard
- **Pass:** ✓

### T-OUTPUT-6: ANSI color codes stripped from raw text
- **Steps:** Run `ls --color=auto` or `git diff` (colorized)
- **Expected:** No raw escape sequences visible (`\x1b[...m`); colors either rendered or stripped cleanly
- **Pass:** ✓

---

## 10. Native Renderers

### T-DOCKER-1: `docker ps` renders natively
- **Setup:** Docker running with at least one container
- **Steps:** Type `docker ps`, send
- **Expected:**
  - OutputBlock shows "NATIVE · DOCKER PS · tap for raw" badge (accent teal)
  - Container rows rendered: status dot (green=running/gray=stopped), container name, image, ports, uptime
  - Container table has visible dividers, rounded corners, border
- **Pass:** ✓

### T-DOCKER-2: `docker ps` with no containers
- **Steps:** Run `docker ps` when no containers running
- **Expected:** Native view shows empty state OR falls through to raw (either is acceptable if consistent)
- **Pass:** ✓

### T-DOCKER-3: `docker ps` running status dot
- **Steps:** Run `docker ps` with mix of running/stopped containers
- **Expected:** Running containers: green dot. Stopped: muted dot.
- **Pass:** ✓

### T-DOCKER-4: docker ps raw toggle
- **Steps:** Run `docker ps` → tap "NATIVE · DOCKER PS · tap for raw" badge
- **Expected:**
  - Badge changes to "← RAW OUTPUT · tap for native"
  - Badge color changes from accent to muted
  - Raw terminal text appears (original docker ps output)
  - Transition: 0.18s fade animation
- **Pass:** ✓

### T-DOCKER-5: docker ps toggle back to native
- **Steps:** From raw state → tap "← RAW OUTPUT · tap for native"
- **Expected:** Returns to native card view; badge text and color reset
- **Pass:** ✓

### T-DOCKER-6: docker ps on non-standard output falls through to raw
- **Steps:** Run `docker ps --format "{{.Names}}"` (custom format that doesn't match parser)
- **Expected:** OutputBlock shows raw text, no native badge
- **Pass:** ✓

---

### T-GIT-1: `git status` renders natively
- **Setup:** In a git repository with staged/modified/untracked files
- **Steps:** `cd` to repo, run `git status`
- **Expected:**
  - OutputBlock shows "NATIVE · GIT STATUS · tap for raw" badge
  - Branch name visible
  - File status badges: S=staged (green), M=modified (yellow), ?=untracked (blue), D=deleted (red)
  - File names visible and truncated gracefully
- **Pass:** ✓

### T-GIT-2: `git status` on clean repo
- **Steps:** Run `git status` on clean repo (no changes)
- **Expected:** Native view shows clean state OR falls through to raw; no crash
- **Pass:** ✓

### T-GIT-3: `git status` ahead/behind indicator
- **Setup:** Repo with commits ahead of remote
- **Steps:** Run `git status`
- **Expected:** ↑N count shown (green if N > 0)
- **Pass:** ✓

### T-GIT-4: `git status` raw toggle
- **Steps:** Native view → tap badge
- **Expected:** Same toggle behavior as T-DOCKER-4
- **Pass:** ✓

### T-GIT-5: `git status` outside a git repo
- **Steps:** `cd /tmp`, run `git status`
- **Expected:** Falls through to raw (shows "not a git repository" message as plain text)
- **Pass:** ✓

---

### T-LS-1: `ls -la` renders natively
- **Steps:** Run `ls -la` in any directory
- **Expected:**
  - OutputBlock shows "NATIVE · FILE LIST · tap for raw" badge
  - Columns: NAME (with icon), SIZE, MODIFIED
  - Directories shown in blue, executables in green, symlinks in purple
  - Sizes and dates right-aligned
  - Rounded container with border
- **Pass:** ✓

### T-LS-2: `ls` short format (no -la) renders natively
- **Steps:** Run `ls` (short listing)
- **Expected:** FileListRenderer handles simple format; file names shown without size/date columns
- **Pass:** ✓

### T-LS-3: `ls -la` directory-first sort
- **Steps:** Run `ls -la` in directory with mixed files and dirs
- **Expected:** Directories appear before files; alphabetical within each group
- **Pass:** ✓

### T-LS-4: `ls` on empty directory
- **Steps:** `ls -la` on empty dir
- **Expected:** Shows only `.` and `..` hidden (skipped), or appropriate empty state; no crash
- **Pass:** ✓

### T-LS-5: `ls -la` raw toggle
- **Steps:** Native view → tap badge
- **Expected:** Same toggle behavior as T-DOCKER-4
- **Pass:** ✓

### T-LS-6: `ls -la` on large directory (100+ files)
- **Steps:** `ls -la /usr/bin`
- **Expected:** All files rendered; view scrollable; no performance lag; no crash
- **Pass:** ✓

---

## 11. Breadcrumb Bar

### T-BREAD-1: Initial path after connection
- **Steps:** Connect, observe breadcrumb
- **Expected:** Shows `username@hostname › ~` (or actual home dir)
- **Pass:** ✓

### T-BREAD-2: Path updates after `cd`
- **Steps:** Run `cd /var/log`
- **Expected:** Breadcrumb path updates to `/var/log` within 1-2 commands
- **Pass:** ✓

### T-BREAD-3: Branch shown in git directory
- **Steps:** `cd` to a git repository
- **Expected:** Branch icon + branch name appears in breadcrumb (e.g., ` main`)
- **Pass:** ✓

### T-BREAD-4: Branch hides outside git repo
- **Steps:** `cd /tmp` (non-git directory)
- **Expected:** Branch icon and name absent from breadcrumb
- **Pass:** ✓

### T-BREAD-5: Long path truncates gracefully
- **Steps:** `cd` to a deeply nested directory
- **Expected:** Path truncated with ellipsis; hostname still visible; no layout overflow
- **Pass:** ✓

### T-BREAD-6: Ahead count shown
- **Steps:** `cd` to repo with unpushed commits
- **Expected:** `↑N` shown in green (N = commit count)
- **Pass:** ✓

### T-BREAD-7: Breadcrumb updates between sessions
- **Setup:** Two sessions, different directories
- **Steps:** Switch between tabs
- **Expected:** Breadcrumb shows correct session's path for each tab
- **Pass:** ✓

---

## 12. Keychain Credential Storage

### T-KC-1: Password stored in Keychain, not in SwiftData
- **Steps:** Connect with password auth; inspect app data (Xcode → Devices → App Container)
- **Expected:** No passwords in any `.sqlite` file or `UserDefaults`; credentials only in Keychain
- **Pass:** ✓ (code review: `KeychainHelper.savePassword()` called, no SwiftData field for password)

### T-KC-2: Credentials isolated per connection
- **Setup:** Two connections to different servers, different passwords
- **Steps:** Connect to each; verify each uses its own credentials
- **Expected:** Each connection authenticates with its own credentials; no cross-contamination
- **Pass:** ✓

### T-KC-3: Reconnect uses saved credentials
- **Setup:** Connected once with password; close session; reopen saved connection
- **Steps:** Tap saved connection card
- **Expected:** Connects without re-entering password (loaded from Keychain)
- **Pass:** ✓

---

## 13. UI/UX — Visual & Interaction Quality

### T-UX-1: Minimum tap target sizes (44×44pt)
- **Components to check:**
  - "+" button in tab bar
  - Close "✕" button on tab
  - Tab items
  - Send button
  - Mic button
  - CodeCorrect pill
  - NativeBadge toggle
  - ApprovalCard buttons (Confirm, Cancel)
  - ConnectionSheet saved connection cards
- **Tool:** Accessibility Inspector → tap target overlay
- **Pass:** ✓ All ≥ 44×44pt

### T-UX-2: SF Symbols used for all icons
- **Check:** All icons throughout app (send arrow, mic, xmark, branch indicator, file icons)
- **Expected:** No custom bitmap icons; all SF Symbols or text
- **Pass:** ✓ (code review: `.systemName` used throughout)

### T-UX-3: Color palette matches spec exactly
- **Check against `Color+Mosaic.swift` hex values:**
  - Background: `#09090B` (near-black)
  - Surface 1: `#111115`
  - Accent teal: `#00D4AA`
  - SSH badge blue: `#4A9EFF`
  - Mosh badge purple: `#A78BFA`
  - Terminal text: `#D8E4F0`
- **Tool:** Digital color meter on simulator screenshot
- **Pass:** ✓

### T-UX-4: JetBrains Mono used for terminal content only
- **Check:** Input bar, output text, command lines, breadcrumb, badge labels = JetBrains Mono. Connection sheet, alerts, sheet UI = SF Pro system font.
- **Pass:** ✓

### T-UX-5: Badge label format correct
- **Expected format:** `NATIVE · [TYPE] · tap for raw` (all caps, monospace 8pt bold, letter spacing)
- **Raw format:** `← RAW OUTPUT · tap for native`
- **Pass:** ✓

### T-UX-6: Status dot pulse animation
- **Steps:** Observe connected session's status dot
- **Expected:** Smooth repeating pulse (scale + opacity) animation; not jarring; stops when disconnected
- **Pass:** ✓

### T-UX-7: Native/raw toggle animation
- **Steps:** Tap NativeBadge
- **Expected:** 0.18s easeInOut fade transition between native and raw views; no layout jump
- **Pass:** ✓

### T-UX-8: No blank screens — all states handled
| State | Expected UI |
|---|---|
| No sessions | EmptyStateView with prompt and "+" |
| Connecting | Tab with blue dot, session view loading |
| Connection failed | Error alert with message |
| Empty command output | Raw block (blank is acceptable) |
| Renderer parse fail | Falls through to raw immediately |
- **Pass:** ✓

### T-UX-9: 8pt grid spacing
- **Check:** Padding and margins throughout are multiples of 8pt (8, 16, 24, 32)
- **Tool:** Accessibility Inspector or layout debugging
- **Pass:** ✓

### T-UX-10: Approval card scrolls into view
- **Steps:** Send destructive command when output list is long (scroll position at top)
- **Expected:** ScrollView animates to reveal the ApprovalCardView
- **Pass:** ✓

---

## 14. Device & Layout Tests

### T-DEVICE-1: iPhone SE (375pt wide) — no overflow
- **Steps:** Run on iPhone SE 3rd gen simulator
- **Check:**
  - Tab bar items not clipped
  - Breadcrumb not overflowing
  - Input bar buttons all visible
  - Native renderer cards not truncated
  - Approval card fully visible
- **Pass:** ✓

### T-DEVICE-2: iPhone 15 Pro (393pt wide) — golden path
- **Steps:** Run on iPhone 15 Pro simulator
- **Expected:** Ideal layout; test all major flows
- **Pass:** ✓

### T-DEVICE-3: Landscape orientation
- **Steps:** Rotate device to landscape
- **Expected:**
  - Layout adapts (tab bar + session view still usable)
  - Keyboard doesn't obscure input bar
  - No clipped UI elements
- **Pass:** ✓

### T-DEVICE-4: Dynamic Type — Large
- **Steps:** Settings → Accessibility → Larger Text → Large
- **Expected:** All text scales appropriately; no truncated labels; no overlapping elements
- **Pass:** ✓

### T-DEVICE-5: Dynamic Type — Accessibility XL
- **Steps:** Settings → Accessibility → Larger Text → max size
- **Expected:** Text truncates gracefully (ellipsis), not clipped; buttons remain functional
- **Pass:** ✓

---

## 15. Edge Cases & Stress Tests

### T-EDGE-1: Command with no output
- **Steps:** Run `true` (exits silently with no output)
- **Expected:** OutputBlock shows command line; output area empty or minimal; no crash; next command works normally
- **Pass:** ✓

### T-EDGE-2: Long-running command interrupted by disconnect
- **Steps:** Run `sleep 60`, then close tab
- **Expected:** Tab closes immediately; session cleaned up; no crash
- **Pass:** ✓

### T-EDGE-3: Renderer failure falls through to raw
- **Steps:** Run `docker ps` when Docker daemon is not running (error output)
- **Expected:** Output shown as raw text (error message readable); no crash; no broken native card
- **Pass:** ✓

### T-EDGE-4: Rapid command submission
- **Steps:** Send 10 commands in quick succession
- **Expected:** All 10 OutputBlocks appear in order; no commands lost or duplicated; no UI jank
- **Pass:** ✓

### T-EDGE-5: Very large output (10,000+ lines)
- **Steps:** Run `cat /var/log/syslog` or `find / -name "*.log" 2>/dev/null`
- **Expected:** Output streams progressively; no memory spike crash; scroll performance acceptable; app remains responsive
- **Pass:** ✓

### T-EDGE-6: Unicode and emoji in output
- **Steps:** Run `echo "Hello 🌍 こんにちは"` and `echo "├── file"`
- **Expected:** Unicode characters displayed correctly in both native and raw views; no mojibake
- **Pass:** ✓

### T-EDGE-7: VT100 escape codes in raw output
- **Steps:** Run `ls --color=always` and observe raw view
- **Expected:** ANSI color codes stripped; clean readable text; no raw escape chars visible (`ESC[0m`)
- **Pass:** ✓

### T-EDGE-8: Connection drop mid-command
- **Steps:** Start a long command, kill network connection (airplane mode), observe behavior
- **Expected:**
  - SSH: session eventually transitions to error/disconnected state; tab shows error or gray dot
  - Mosh: tab shows "↻ ROAMING"; reconnects when network restored
- **Pass:** ✓

### T-EDGE-9: Multiple rapid connection attempts
- **Steps:** Tap Connect multiple times quickly before first connection completes
- **Expected:** Only one connection created (button disabled or idempotent); no duplicate sessions
- **Pass:** ✓

### T-EDGE-10: App killed and relaunched during active session
- **Steps:** Force-quit app during active SSH session; relaunch
- **Expected:** Sessions not restored (expected Phase 1 behavior); EmptyStateView shown; no crash on launch
- **Pass:** ✓

---

## 16. End-to-End Golden Path

This is the primary scenario that must pass 100% before any release.

### T-E2E-1: Full SSH session with all 3 renderers

**Setup:** Real server with Docker, git, and standard filesystem

1. Launch app → EmptyStateView ✓
2. Tap "+" → ConnectionSheet ✓
3. Enter credentials → Connect → SSH session opens ✓
4. Tab shows hostname, blue "SSH" badge, green pulsing dot ✓
5. BreadcrumbBar shows `user@hostname › ~` ✓
6. Run `ls -la` → FileListRenderer native view → toggle to raw → toggle back ✓
7. Run `cd /my-git-repo` → BreadcrumbBar path updates ✓
8. Run `git status` → GitStatusRenderer native view with branch + file badges → toggle raw/native ✓
9. BreadcrumbBar shows branch name ✓
10. Run `docker ps` → DockerPsRenderer native view with container rows → toggle raw/native ✓
11. Run `sudo rm -rf /important` → Tier 1 approval card → hold 1.5s → command sent ✓
12. Run `rm -r ~/testdir` → Tier 2 approval card → Confirm → sent ✓
13. Run `sudo apt list` → Tier 3 auto-dismiss → times out → command NOT sent ✓
14. Close tab → EmptyStateView returns ✓

**Pass:** ✓ All 14 checkpoints pass

### T-E2E-2: Full Mosh session golden path

Same steps as T-E2E-1 but using MOSH transport. Purple badge. Verify roaming if possible.

**Pass:** ✓

---

## 17. Regression Checklist

Run these after any code change to catch regressions:

| After changing | Run |
|---|---|
| SSHConnection.swift | T-SSH-1 through T-SSH-6 |
| MoshConnection.swift | T-MOSH-1 through T-MOSH-5 |
| Any renderer | T-DOCKER-* or T-GIT-* or T-LS-* + T-EDGE-3 |
| SessionManager.swift | T-TABS-1 through T-TABS-6 + T-E2E-1 |
| SafetyClassifier.swift | T-SAFETY-* |
| SmartInputBar.swift | T-INPUT-* + T-SAFETY-* |
| TabBarView.swift | T-TABS-* + T-UX-6 |
| BreadcrumbBar.swift | T-BREAD-* |
| project.yml / XcodeGen | T-BUILD-1 + T-BUILD-2 |

---

## 18. Known Phase 1 Limitations (Not Bugs)

These are intentional and should not be filed as defects:

- **CodeCorrect pill:** Shows on/off toggle only; no AI functionality
- **Mic button:** Visible but no action
- **Mosh resize:** Resize dimensions update at next state sync, not instantly
- **Session persistence:** Sessions not restored after app kill (by design for Phase 1)
- **iCloud sync:** Not implemented in Phase 1
- **iPad split-pane:** Not implemented in Phase 1
- **Connection manager:** No edit/delete for saved connections in Phase 1
- **Host key verification:** `acceptAnything()` used; Phase 2 will persist and verify
- **Mosh SSH fallback UI:** `offerSSHFallback` logic exists but UI button not wired in Phase 1

---

*Generated: 2026-04-21 | App Version: 1.0 Phase 1*
