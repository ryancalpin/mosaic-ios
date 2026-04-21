# Mosaic — Technical Decisions
*Opinionated answers to every hard question. No "it depends."*

---

## 1. Rendering Engine — How It Knows What to Render

**Decision: Two-signal system — command string first, output heuristics as fallback.**

### Signal 1: Command Prefix Match (Primary)
Parse the first 1–3 tokens of the typed command and match against a renderer registry:

```swift
let registry: [String: OutputRenderer] = [
  "docker ps":    DockerPsRenderer(),
  "git status":   GitStatusRenderer(),
  "git diff":     GitDiffRenderer(),
  "git log":      GitLogRenderer(),
  "ls":           FileListRenderer(),
  "ls -la":       FileListRenderer(),
  "df -h":        DiskUsageRenderer(),
  "ping":         PingRenderer(),
  "curl -I":      HttpResponseRenderer(),
  "curl -sI":     HttpResponseRenderer(),
  "npm install":  ProgressRenderer(type: .npm),
  "pip install":  ProgressRenderer(type: .pip),
  "apt install":  ProgressRenderer(type: .apt),
  "jq":           JsonTreeRenderer(),
  "cat":          SmartCatRenderer(), // detects JSON, code, etc.
  "ps aux":       ProcessTableRenderer(),
  "crontab -l":   CronRenderer(),
  // ... etc
]
```

Match is greedy — tries longest prefix first. `git status -s` matches `git status`. `docker ps --format` matches `docker ps`.

### Signal 2: Output Heuristics (Fallback for Aliases + Pipes)
On connection, Mosaic runs `alias` and caches the mapping:
```
dps → docker ps  →  use DockerPsRenderer
gs  → git status →  use GitStatusRenderer
```

If command still doesn't match after alias resolution, run output through shape detectors:
- Starts with `{` or `[` and is valid JSON → `JsonTreeRenderer`
- First line matches `CONTAINER ID   IMAGE   COMMAND` pattern → `DockerPsRenderer`
- First line matches `On branch` → `GitStatusRenderer`
- Lines match `HH:MM:SS bytes from` pattern → `PingRenderer`
- etc.

### Edge Cases
| Scenario | Behavior |
|---|---|
| `alias dps="docker ps"` | Resolved via cached alias map → DockerPsRenderer |
| `watch docker ps` | Strip watch header, apply DockerPsRenderer to inner output |
| `docker ps \| grep running` | Try DockerPsRenderer, if parse fails → raw (graceful) |
| `docker ps --format "{{.Names}}"` | Parse fails (custom columns) → raw, no badge shown |
| Unknown command | Both signals fail → clean monospace, no badge |

**Rule:** if the renderer's `parse()` throws or returns nil at any point, instantly fall through to raw. Never partially render. Never crash. Never show a broken native view.

---

## 2. Mosh — Phase 1, Using mosh-apple

**Decision: Mosh ships in Phase 1 alongside SSH. Use Blink Shell's `mosh-apple` library — the hard C++ bridging work is already done.**

### Why This Is Now Feasible in Phase 1
Blink Shell (the gold-standard iOS terminal) open-sourced their Mosh implementation as [`mosh-apple`](https://github.com/blinksh/mosh-apple) under MIT license. This is the official mosh C++ library already bridged to Objective-C/Swift for iOS. Every hard problem — UDP socket management, roaming on network change, key exchange handoff — is already solved. We add it as a Swift Package dependency and implement the protocol. No C++ bridging work required on our end.

### Transport Abstraction (Same Plan, Just Both in Phase 1)
```swift
protocol TerminalConnection {
  func connect() async throws
  func disconnect()
  func send(_ input: String)
  var outputStream: AsyncStream<Data> { get }
  var isConnected: Bool { get }
}

class SSHConnection:  TerminalConnection { ... }  // Phase 1 — via NMSSH
class MoshConnection: TerminalConnection { ... }  // Phase 1 — via mosh-apple
```

The rendering engine talks only to `TerminalConnection`. It has zero knowledge of whether the underlying transport is SSH or Mosh. Adding future transports (Telnet for legacy gear, WebSocket for browser-based shells) is additive with zero engine changes.

### Mosh-Specific UX
- Purple `MOSH` protocol badge in tab bar (vs. blue `SSH`)
- On network change: tab badge briefly shows `↻ ROAMING` then snaps back to `MOSH` when reconnected — no user action needed, no session lost
- Connection sheet lets user pick SSH or Mosh per host (Mosh requires mosh-server installed on remote)
- Fallback: if mosh-server not found on remote, offer to fall back to SSH automatically

### App Store Risk — Mitigated
Blink Shell ships mosh-apple through the App Store successfully. We cite the same precedent. The key argument: all execution is remote, UDP is used only for the Mosh protocol transport (not arbitrary networking), and the `Network.framework` entitlement is standard.

---

## 3. Approval Card — The Full Ruleset

**Decision: Three-tier system. Bundled rules, user-extensible post-MVP.**

### Tier 1 — Always Block (Cannot Proceed Without Explicit Confirm)
These are catastrophic. The confirm button is red and requires a 1.5s hold, not a tap.

```
sudo rm -rf /
sudo rm -rf ~
mkfs.*                          # format any filesystem
dd if=.* of=/dev/[a-z]+         # raw disk write
shred .*
wipefs .*
terraform destroy
DROP DATABASE .*                # SQL
kubectl delete namespace .*
```

### Tier 2 — Intercept + Confirm (Standard Approval Card)
Show impact, require one tap to confirm.

```
rm -rf [^\s]+                   # rm -rf with any path
rm -r[^\s]* .*/                 # rm -r on a directory
kubectl delete .*
docker rm -f .*
docker system prune
docker volume prune
git push --force
git push -f
git reset --hard
git clean -fd
truncate .*
pkill .*
kill -9 .*
killall .*
systemctl stop .*
systemctl disable .*
npm uninstall .*
pip uninstall .*
DROP TABLE .*                   # SQL
DELETE FROM .* WHERE            # SQL with WHERE
ALTER TABLE .* DROP .*          # SQL
```

### Tier 3 — Warning Banner (Proceed After 1s Dismissible Delay)
Show a yellow warning, auto-proceed after 1 second unless dismissed.

```
sudo (?!rm|mkfs|dd|shred).*    # sudo anything not in T1/T2
chmod 777 .*
chown -R root .*
git stash drop
git stash clear
npm run (build|deploy|prod)    # production scripts
```

### Implementation
```swift
enum SafetyTier {
  case tier1(reason: String, impact: ImpactSummary)
  case tier2(reason: String, impact: ImpactSummary)
  case tier3(reason: String)
  case safe
}

func classify(command: String) -> SafetyTier {
  // Check T1 patterns first, then T2, then T3
  // Returns .safe if no match — most commands
}
```

**Impact Summary** is generated by a pre-flight dry run where possible:
- `rm -rf ./node_modules` → run `find ./node_modules -maxdepth 0 -exec du -sh {} \; 2>/dev/null` to get size before showing the card
- `kubectl delete deployment hermes` → run `kubectl get deployment hermes -o json` to show replica count, image, age

User customization (V1.1): Settings → Safety → Custom Rules. Add regex + tier. Export/import rulesets as JSON.

---

## 4. CodeCorrect — Architecture Decision

**Decision: Four-layer stack. No ML in MVP. Optional Claude API on explicit request only.**

### Layer 1: History Completion (Zero Latency)
Fish-shell style. As you type, ghost-text the most recent history match in muted color. `→` or `tab` to accept. Implemented as a `UITextView` subclass that overlays a `CATextLayer` with the ghost text. History stored in SwiftData, max 10,000 entries, de-duplicated.

```
User types: git com
Ghost text:  git commit -m "feat: improve agent loop timing"  ← most recent match
```

### Layer 2: Bundled Typo Corrections (Zero Latency)
~600 common shell/git/docker/npm typos, compiled into a trie at build time. Checked on every space character typed. Silent correction with a subtle underline that taps to revert (like iOS autocorrect).

```
dokcer     → docker
git commti → git commit  
npx instal → npx install
kubcetl    → kubectl
tial       → tail
grpe       → grep
```

Source: aggregate from `thefuck` rules + common typos databases + manual additions. Shipped as a `.json` file compiled to a binary trie via a build script.

### Layer 3: Command Completion Engine (Near-Zero Latency)
Bundled man page summaries for 200 most common commands. As you type `git com`, shows dropdown:

```
▸ history   git commit -m "feat: improve agent loop timing"
▸ command   git commit
▸ command   git commit --amend  
▸ snippet   git commit -am "…"
```

Completions are pre-computed from man page parsing + common usage patterns. No network. Feels instant.

For dynamic completions (branch names, container names, file paths): runs a background SSH query on focus, caches results per session. `git checkout ` → `git branch --list` in background → offer branches as completions.

### Layer 4: Claude API (Explicit Request Only)
Never fires automatically. Only triggered by:
- User taps "Ask AI…" in the suggestion dropdown
- User types `⌘J`
- User types a `?` prefix: `? how do I find files modified in the last hour`

This sends context (current directory, recent history, server OS) + the question to Claude. Returns a command suggestion with brief explanation. Shown as a special "AI" type suggestion in the dropdown. User taps to accept — command is populated in input but NOT auto-sent. User reviews, hits send.

This keeps the AI as a power feature without making it a latency liability.

---

## 5. Renderer Extensibility — Protocol in Phase 1, No-Code Builder in Phase 2 (MVP)

**Decision: Protocol-based from day one. No-code custom renderer builder ships in MVP (Phase 2). JS sandbox in V2.**

### The Renderer Protocol (Phase 1)
```swift
protocol OutputRenderer {
  var id: String { get }
  var displayName: String { get }
  var badgeLabel: String { get }       // "CONTAINERS", "GIT STATUS", etc.
  var priority: Int { get }            // Higher = tried first in registry

  func canRender(command: String, output: String) -> Bool
  func parse(output: String) throws -> any RendererData
  func view(data: any RendererData) -> any View
}
```

All 20+ built-in renderers conform to this. Fully swappable. No special-casing anywhere in the engine.

### Phase 2 (MVP): No-Code Custom Renderer Builder
Ships alongside the core renderers in MVP — not post-launch. Implemented as a sheet in Settings → Renderers → New Renderer.

**Fields:**
| Field | Input Type | Example |
|---|---|---|
| Name | Text | "Kubernetes Pods" |
| Command pattern | Regex | `kubectl get pods.*` |
| Badge label | Text (max 16 chars) | "K8S PODS" |
| Output format | Picker | JSON / CSV / Table / Key-Value |
| Column map (tables) | Dynamic field list | NAME, READY, STATUS, RESTARTS |
| Display template | Visual picker | List / Table / Cards / KV Grid |

**Live preview pane:** user pastes a sample output, sees the rendered result in real time as they configure. This is the killer feature of the builder — instant feedback.

**Storage:** custom renderer definitions saved to SwiftData as `CustomRenderer` records. Synced via CloudKit alongside connections and workspaces. Users can share renderer definitions as `.mosaic-renderer` JSON files via Share Sheet.

**Renderer priority:** custom renderers are checked BEFORE built-in renderers. Users can override a built-in by matching the same command pattern.

**What the no-code builder covers:**
- Any tabular command output (`kubectl get pods`, `netstat`, custom scripts)  
- Any key-value output (`env`, config files)  
- Any JSON output (wrap in JSON tree automatically)  
- Any list output (one item per line)

**What it can't do** (requires JS renderer in V2):
- Output that requires complex parsing logic
- Renderers with interactive elements (buttons, toggles)
- Renderers that make additional network/shell calls

### V2: JavaScript Renderers
JavaScriptCore sandbox. Users write a renderer as a JS module:
```javascript
export default {
  id: "my-custom-renderer",
  displayName: "Kubernetes Pods",
  canRender: (command, output) => command.startsWith("kubectl get pods"),
  parse: (output) => {
    // parse output, return structured data
  },
  render: (data) => ({
    type: "table",
    columns: ["NAME", "READY", "STATUS", "RESTARTS"],
    rows: data.rows
  })
}
```

Sandboxed: no network access, no file system, pure data transformation only. Community marketplace where users publish and subscribe to renderer packs (think Raycast extensions).

---

## 6. AI Tab — Architecture and Security Model

**Decision: Dedicated SSH session #2, command preview before execution, approval card always applies.**

### Session Architecture
```
Manual Terminal Tab  →  SSH Session #1  →  Shell (full, unrestricted)
AI Tab               →  SSH Session #2  →  Shell (same server, same user)
```

Two separate sessions to the same server. They share the same filesystem, same environment, same user permissions. They do NOT share a shell process — this means AI actions can't accidentally send Ctrl+C to something the user is doing in the manual tab.

### Execution Flow
```
1. User types: "show me what's eating disk space in /var"
2. Claude API call:
   - Context: server OS, current directory, recent commands
   - Returns: { command: "du -sh /var/* | sort -rh | head -20", explanation: "..." }
3. Mosaic shows in thinking block:
   "Running: du -sh /var/* | sort -rh | head -20"
4. Command executes on SSH Session #2
5. Output → Rendering Engine → DiskUsageRenderer → native view
6. Native badge shows, tap for raw — identical to manual terminal
```

User never sees raw shell execution — they see the command string (transparent), the thinking block (honest), and the rendered output (native). The AI is never a black box.

### Safety Rules in AI Tab
- **All Tier 1 and Tier 2 commands trigger the approval card** — no exceptions, even if AI-generated
- **The AI cannot execute commands without showing the command string first** — minimum 800ms display before execution (enough time to read and cancel)
- **AI session has no persistent state** — each AI conversation starts fresh. The AI can't accumulate a shell history that leaks context
- **User can grant/revoke AI sudo permission** per connection in settings. Default: off.

### What the AI Has Access To
- The connected server (via SSH Session #2)
- Current working directory (synced from manual tab)
- Recent command history (last 20, for context)
- Server metadata (OS, hostname, uptime — fetched once on connect)

The AI does NOT have access to:
- Credentials or keys
- Other app data
- The manual tab's shell state (process groups, variables, etc.)

### Model Choice
Claude API (Anthropic). `claude-sonnet-4-6` — fast enough for interactive use, smart enough to generate correct shell commands, knows the entire Unix command landscape. System prompt includes server OS, shell type, and a strict instruction to return only executable commands (no markdown, no explanation in the command itself).

---

## Summary Table

| Question | Decision |
|---|---|
| Render trigger | Command prefix match + alias resolution + output heuristics fallback |
| Mosh | **Phase 1** via `mosh-apple` (Blink's open-source library) + SSH, both behind `TerminalConnection` protocol |
| Approval tiers | T1 hold-to-confirm, T2 tap-to-confirm, T3 auto-dismiss warning |
| CodeCorrect | History ghost-text + bundled trie + completion engine + Claude on explicit request |
| Extensibility | Protocol-based Phase 1, **no-code builder in Phase 2 (MVP)** with live preview, JS sandbox V2 |
| AI tab | Dedicated SSH session #2, command preview always shown, approval card always enforced |
