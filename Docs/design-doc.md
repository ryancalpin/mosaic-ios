# Mosaic — Design Document
*Modern Terminal Runtime for iOS*
*Last updated: April 2026*

---

## 🧠 Concept Summary

Mosaic is a native iOS terminal runtime that modernizes the shell experience from the rendering layer up. It doesn't wrap the terminal — it replaces its surface entirely. Every command still runs on a real shell over SSH or Mosh, but output is intercepted, parsed, and rendered as gorgeous native iOS components. The same way OpenCode took Claude Code's TUI and rebuilt it as a beautiful native app, Mosaic does this for the entire terminal power-user category.

**The core innovation:** native rendering is opt-out, not opt-in. Mosaic renders natively by default and always shows a "NATIVE · tap for raw" badge — one tap reveals the true terminal output underneath. Power users never feel like something is being hidden.

---

## 🎯 Problem Statement

The terminal hasn't been modernized at its foundation in decades. Today's "terminal apps for iOS" — Blink, Termius, Prompt — all make the same mistake: they port the terminal experience and call it done.

The result is a surface that:
- Renders ASCII box-drawing characters as UI
- Has no native scrollback (requires tmux/screen)
- Fights iOS autocorrect constantly
- Uses monospace for everything, even prose
- Has no tab/window management (requires tmux `ctrl+b c`)
- Dumps raw text walls for structured data (`ps aux`, `docker ps`, `git status`)
- Provides zero safety on destructive commands

Mosaic fixes all of this at the runtime level — not by removing the shell, but by building a smarter surface on top of it.

---

## ✨ Core Features (MVP)

### 1. Native Output Rendering Engine
The heart of Mosaic. Every command output is passed through a parser that matches it against known schemas. When a match is found, it renders a native component. When no match exists, it falls back to clean monospace terminal output — always safe, never lossy.

**The toggle contract:** every natively-rendered block carries a `NATIVE · [TYPE] · tap for raw` badge. One tap reveals the actual raw terminal output. One tap back returns to native. This is the trust mechanism that makes power users comfortable.

### 2. Native Tab Bar (Session Management)
Browser-style tabs for multiple SSH/Mosh sessions. No tmux. No `ctrl+b c`. Each tab shows:
- Server name + connection status dot (live/idle/offline)
- Protocol badge (MOSH / SSH)
- Close button on active tab
- `+` to open new session

### 3. Smart Input Bar (CodeCorrect)
A custom input layer that replaces iOS autocorrect with shell/code-aware intelligence:
- Knows `git commit` vs. `git comit` — corrects silently, never aggressively
- Inline autocomplete dropdown with type-tagged suggestions (history / command / snippet)
- Typed portion highlighted in accent color, completion ghosted in muted color
- `↑↓` to cycle, `↵` to apply
- Voice input (mic button) for AI-dictated commands

### 4. Native Scrollback
Swipe to scroll, momentum physics, infinite history — no tmux required. Scrollback is a native iOS scroll view. Output blocks are grouped per command, making visual scanning natural.

### 5. SSH + Mosh — First-Class
- Mosh as first-class protocol (purple badge), SSH as secondary (blue badge)
- Automatic reconnect on network change (Mosh's core strength, surfaced natively)
- Key auth + password, keychain-stored
- SSH config import
- Connection manager: card-based host browser, tap to connect, opens in new tab

### 6. Approval Card (Destructive Command Interception)
Any command matching a destructive pattern (`sudo rm -rf`, `drop table`, `kubectl delete`, `mkfs`, etc.) is intercepted before execution. Mosaic shows:
- Exactly what will be affected (files, sizes, counts)
- Total impact summary
- Cancel / Confirm buttons
- Raw preview of what the command will do
Only fires on confirm. Cancel shows "nothing deleted" with a retry link.

### 7. AI Terminal Tab
A dedicated `✦ AI` tab that accepts natural language input:
- "show me all containers using more than 10% CPU"
- "what's eating the most disk space in /var?"
- "tail the hermes log and tell me if there are any errors"

AI translates to real shell commands, executes on the connected server, and renders output natively — same rendering pipeline as the manual terminal. Same native badge toggle.

---

## 🖥️ Native Renderers (Full Catalogue)

All renderers share the same contract: native by default, tap badge for raw.

### System
| Command | Renderer | Key Features |
|---|---|---|
| `docker ps` | Container Cards | Status dot, CPU bars (live), memory, ports, uptime |
| `ps aux` / `top` | Process Table | Sortable columns, CPU color-coded, focused row detail |
| `df -h` | Disk Usage Bars | Per-mount bars, color shifts green→amber→red by % |
| `free -m` / `vmstat` | Memory Breakdown | Used / buffers / cache / free segments |
| `env` / `printenv` | Key-Value Table | Searchable, tap-to-copy |
| `uptime` | Load Sparklines | 1/5/15min trend lines |

### Network
| Command | Renderer | Key Features |
|---|---|---|
| `ping` | Latency Graph | Live sparkline, min/avg/max |
| `curl -v` / `-I` | HTTP Response Card | Status badge, headers, syntax-colored body |
| `traceroute` | Hop Map | Per-hop latency, geo location of each node |
| `netstat` / `ss` | Connection Table | State color-coded (ESTABLISHED, TIME_WAIT…) |
| `nmap` | Port Grid | Open/closed/filtered, service name labels |
| `whois` | Contact Card | Registrar, expiry, nameservers |

### Git
| Command | Renderer | Key Features |
|---|---|---|
| `git status` | Status View | M/D/? badges, branch, ahead/behind count |
| `git diff` | Code Diff | Side-by-side or unified, syntax-highlighted |
| `git log` | Commit Timeline | Hash, message, author, relative time |
| `git blame` | Annotated File | Each line tagged with commit + author |

### Files & Code
| Command | Renderer | Key Features |
|---|---|---|
| `ls -la` | File Browser | Icons, size, modified, tap to open/copy path |
| `cat file.py` | Code Block | Syntax-highlighted, line numbers, copy button |
| `du -sh *` | Size Bars | Per-directory, sorted, tap to drill down |
| `find . -name` | File Tree | Expandable results tree |

### Data & Processes
| Command | Renderer | Key Features |
|---|---|---|
| `psql/mysql -c "SELECT…"` | Data Table | Sortable, filterable, paginated |
| `cat file.json \| jq` | JSON Tree | Collapsible nodes, type-colored values, array/object counts |
| `pstree` | Process Tree | Expandable/collapsible parent-child |
| `crontab -l` | Cron Schedule | Human-readable frequency, next-run countdown |
| `redis-cli monitor` | Live KV Stream | Key-value pairs, scrolling live |

### Package Managers
| Command | Renderer | Key Features |
|---|---|---|
| `npm install` / `pip install` / `apt` | Progress Tracker | Per-package status (queued → installing → done), overall bar |
| `npm search` / `apt search` | Item Carousel | Name, version, description, install action |

### Infrastructure
| Command | Renderer | Key Features |
|---|---|---|
| `terraform plan` | Step Checklist | Add/change/destroy color-coded, resource names |
| `ansible-playbook --check` | Task Grid | Hosts × tasks matrix |
| `openssl x509 -text` | Certificate Card | Expiry countdown, issuer, SANs, fingerprint |
| `ssh-keygen -l` | Key Card | Algorithm, bits, fingerprint, comment |
| `docker logs` | Log Stream | Live tail, level badges, service tags |
| `journalctl -u` | Filtered Log Stream | Unit header, level filtering |

### Misc
| Command | Renderer | Key Features |
|---|---|---|
| `man <cmd>` | Man Page | Sections as collapsible cards, searchable |
| `curl wttr.in` | Weather Widget | Current + forecast |
| `ping` | Latency Graph | Already above |

### Safety (Approval Cards)
| Pattern | Trigger |
|---|---|
| `sudo rm -rf` | Shows files/dirs + sizes + count before executing |
| `DROP TABLE` / `DROP DATABASE` | Shows table name, row count |
| `kubectl delete` | Shows resource type, name, namespace |
| `mkfs` / `fdisk` | Shows device, current contents |
| `kill -9` / `pkill` | Shows process name, PID, parent |

---

## 🗺️ UX Flow

### Session Flow
1. Launch → tab bar with saved sessions (or empty state "Connect to a server")
2. Tap `+` → Connection sheet — pick saved host or enter new
3. Connected → breadcrumb shows `user@host › ~/path` + git branch
4. Type command in smart input bar
5. Hit send → command runs → output block appears with native rendering
6. Tap `NATIVE · TYPE · tap for raw` badge to toggle
7. Session is infinitely scrollable — all blocks preserved, grouped by command

### New Connection Flow
1. Tap `+` tab → Connection sheet slides up
2. Cards for saved hosts (status dot, protocol badge, last connected)
3. "New Server" form: hostname, user, port, auth method
4. Key management: import from Files, generate new, or paste
5. Test connection → success animates to new tab

### Destructive Interception Flow
1. User types `sudo rm -rf ./node_modules`
2. Input bar sends command
3. Mosaic intercepts — command does NOT run yet
4. Approval card renders inline showing impact
5. User taps Confirm → command runs → result rendered
6. User taps Cancel → "nothing deleted" card, retry available

### AI Tab Flow
1. Tap `✦ AI` tab
2. Natural language input: "show me disk usage"
3. Thinking block appears (grey, italic): "Running df -h on prod-01…"
4. Native renderer appears — same as if user ran `df -h` manually
5. Badge toggle works exactly the same

---

## 🏗️ Technical Architecture

### Recommended Stack

| Layer | Choice | Why |
|---|---|---|
| Frontend | SwiftUI | Ryan's stack, best native iOS UI |
| Terminal Emulator | SwiftTerm | Open-source VT100/xterm for Swift, actively maintained |
| SSH | NMSSH (libssh2) | Battle-tested, supports key auth + SFTP |
| Mosh | Mosh C++ library (via Swift bridging header) | Official mosh implementation, handles roaming |
| Rendering Engine | Custom Swift parser + SwiftUI views | See below |
| Smart Input | Custom UITextView subclass + JavaScriptCore for rules | Off-device model for suggestions |
| AI Layer | Claude API (Anthropic) | Natural language → command, context-aware |
| Local Storage | SwiftData | Workspaces, connections, history, renderer rules |
| Cloud Sync | CloudKit (iCloud) | Free for users, native, device handoff |
| Distribution | App Store + TestFlight | Standard |

### Rendering Engine Architecture

The rendering engine is the core technical innovation. It runs as a post-processor on all shell output:

```
Shell Output (raw bytes)
       ↓
  ANSI Stripper (remove escape codes)
       ↓
  Schema Matcher (try each renderer's parser in priority order)
       ↓
  ┌─── Match found ──────────────────────────────────────┐
  │   Parse structured data → SwiftUI native view        │
  │   Store raw output alongside for toggle              │
  └──────────────────────────────────────────────────────┘
  ┌─── No match ─────────────────────────────────────────┐
  │   Render as clean monospace terminal block           │
  │   No badge shown (it's just terminal output)         │
  └──────────────────────────────────────────────────────┘
```

**Schema Matchers** are per-renderer parsers. Each one:
- Has a `canParse(output: String, command: String) -> Bool` method
- Has a `parse(output: String) -> RendererData?` method
- Returns `nil` on parse failure (falls through to next matcher)
- Command hint (what the user typed) helps disambiguation

**Priority order:** command hint first, then output heuristics. `docker ps` output that doesn't match the expected schema (e.g., user added custom columns) falls through to raw. Never wrong.

**Destructive Interception** runs on the *input* side before the command is sent to the shell. A regex/AST pattern matcher on the command string determines if pre-confirmation is required.

### Data Model

```
Connection
  id, name, hostname, port, username
  authMethod: (password | key | agent)
  keyRef: KeychainReference?
  protocol: (ssh | mosh)
  lastConnected: Date
  color: Color (tab indicator)

Session
  id, connectionId
  startedAt: Date
  blocks: [OutputBlock]

OutputBlock
  id, command: String
  rawOutput: String
  rendererType: RendererType? (nil = plain terminal)
  renderedData: Data (JSON-encoded renderer model)
  timestamp: Date

RendererRule (user-customizable)
  id, commandPattern: Regex
  rendererType: RendererType
  enabled: Bool

Workspace
  id, name
  tabs: [Session]
  layout: WorkspaceLayout (single | split)
```

### Platform Considerations

**iOS first.** iPad is the ideal form factor — hardware keyboard common, screen real estate generous, split view maps naturally to the split pane model. iPhone is fully supported with single-pane layout.

**Device Handoff:** CloudKit syncs session state, connection list, and workspace layout. Leave a session on iPhone, pick it up on iPad. Implemented via `NSUserActivity` + CloudKit diff sync.

**Keyboard shortcuts (hardware keyboard):**
- `⌘T` — New tab
- `⌘W` — Close tab
- `⌘[1-9]` — Switch to tab N
- `⌘K` — Command palette
- `⌘D` — Split pane
- `⌘↑/↓` — Scroll to top/bottom of session
- `⌘F` — Search session output
- `⌃C` — Send SIGINT (works in terminal)

**iOS Shortcuts integration (MVP):**
- "Open Mosaic on [server]" → Siri-triggerable
- "Run workflow" → named saved command sequences
- Share sheet extension → paste selected text as command

**Rich Notifications (MVP):**
- Live process alerts (CPU threshold crossed, process died)
- Log stream keyword alerts ("error", custom regex)
- Certificate expiry warnings (30d, 14d, 7d, 1d)
- Connection status changes

**App Store category:** Developer Tools.

---

## 💸 Monetization

**Freemium + one-time Pro option:**

| Tier | Price | Limits |
|---|---|---|
| Free | $0 | 2 connections, 5 renderer types, no AI tab |
| Pro Monthly | $4.99/mo | Unlimited connections, all renderers, AI tab, iCloud sync |
| Pro Yearly | $29.99/yr | Same as monthly |
| Pro Forever | $49.99 | Lifetime, all current + future features |

The "Pro Forever" option is important for the developer tools audience — they hate subscriptions and will pay a premium for a one-time purchase. Proxyman, Pockity, and Retcon all use this model successfully.

---

## ⚠️ Risks & Gotchas

**Mosh on iOS is hard.** Mosh requires UDP and a custom roaming implementation. The official mosh C++ library exists but bridging it to Swift is non-trivial. Allocate significant Phase 1 time here. Alternative: ship SSH-only first, add Mosh in V1.1.

**App Store scrutiny on shell execution.** Apps that execute arbitrary code get extra review attention. The key argument: Mosaic is a remote terminal, not a local code executor. All shell execution happens on the remote server via SSH/Mosh. Precedent: Blink Shell, Termius, and Prompt are all on the App Store.

**Rendering engine edge cases.** `git status` output format changes between git versions. `docker ps` output changes with `--format` flags. Each renderer needs robust fallback — if parsing fails mid-output, fall through to raw immediately. Never partially render.

**JavaScriptCore sandboxing for CodeCorrect.** JSCore on iOS is sandboxed — no network, limited file access. The correction rules must be bundled or fetched at app launch and cached locally. No real-time model calls for autocorrect (too slow anyway).

**SwiftTerm integration depth.** Embedding a full VT100 emulator alongside the native rendering engine means two output consumers. The terminal emulator still needs to process everything (for escape codes, cursor position, etc.) even when we're rendering natively. Architecture: run SwiftTerm as the ground truth, tap its output stream for the renderer. Don't bypass it.

**Scope creep.** The renderer catalogue alone could take a year. Ship with 6–8 renderers for MVP, gate the rest behind updates.

---

## 🚀 Build Sequence

### Phase 1 — Proof of Concept (Weeks 1–4)
**Goal:** real SSH + Mosh session rendering in a native tab bar.

- [ ] SwiftTerm embedded, connecting to a real server via NMSSH (SSH)
- [ ] Mosh connection via `mosh-apple` (Blink's library) — both transports behind `TerminalConnection` protocol
- [ ] Native tab bar with session management (no tmux)
- [ ] Native scroll view wrapping terminal output
- [ ] Basic command input bar (no CodeCorrect yet)
- [ ] 3 renderers: `docker ps`, `git status`, `ls -la`
- [ ] Raw toggle on each renderer
- [ ] Mosh tab badge (purple MOSH / blue SSH), roaming indicator
- [ ] Deploy to TestFlight (self)

**Success criteria:** Ryan can connect to prod-01 via Mosh, run docker ps, and see containers natively. Toggle to raw and back. Switch to a second tab for staging via SSH.

### Phase 2 — MVP (Weeks 5–12)
**Goal:** shippable to a closed beta of power users.

- [ ] Connection manager (card UI, Keychain, key auth)
- [ ] 8 additional renderers: `ping`, `df -h`, `curl -I`, `npm install`, `jq`, `crontab -l`, `git diff`, `ps aux`
- [ ] Approval card (destructive command interception, all 3 tiers)
- [ ] CodeCorrect smart input (bundled rules, history ghost-text, completion engine)
- [ ] **No-code renderer builder** (Settings → Renderers → New Renderer, with live preview pane)
- [ ] Custom renderer sharing via `.mosaic-renderer` JSON + Share Sheet
- [ ] Breadcrumb navigation (host + path + git branch)
- [ ] iCloud sync (connections, session history, custom renderers)
- [ ] Device Handoff
- [ ] iOS Shortcuts integration
- [ ] Rich push notifications (process alerts, log keywords, cert expiry)
- [ ] Basic AI tab (Claude API, natural language → command, dedicated SSH session)
- [ ] iPad layout (split pane)
- [ ] Hardware keyboard shortcuts
- [ ] TestFlight: closed beta, 50–100 users

### Phase 3 — V1.0 App Store (Weeks 13–20)
**Goal:** public launch.

- [ ] Full renderer catalogue (all categories in design doc)
- [ ] Renderer user customization (disable/enable built-ins, reorder priority)
- [ ] Workflow builder (saved command sequences, Shortcuts-triggerable)
- [ ] Freemium paywall implementation (RevenueCat)
- [ ] Onboarding flow (first-run, test connection, first native render moment)
- [ ] Settings: themes (dark only for now), font size, CodeCorrect toggles, Safety tier customization
- [ ] Privacy + security audit (Keychain, no plaintext credentials)
- [ ] App Store submission

---

## 🔗 Related / Inspiration

- **OpenCode** — the direct conceptual model. TUI → native UI, same capabilities.
- **Warp** — closest desktop analog. Block-based output, AI integration, modern terminal UX. Study the block model deeply.
- **Blink Shell** — SSH done right for iOS. Reference for SSH/Mosh UX patterns and App Store precedent.
- **tool-ui.com** — component catalogue that maps almost 1:1 to terminal output types. Their schema-first rendering model is the right architecture pattern.
- **SwiftTerm** — the terminal emulator underpinning everything.
- **ClawdHub** — Ryan's existing iOS agent control app. Mosaic's live event stream and panel patterns share DNA.
- **Hermes** — the primary use case. Mosaic should feel like it was built to manage the Hermes stack specifically.
