# CodeCorrect Smart Input Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement CodeCorrect — a three-layer smart input system (history ghost-text, bundled typo correction, and a completion dropdown) that makes Mosaic's terminal input bar feel as fast and intelligent as a modern shell.

**Architecture:** `CommandHistory` is a SwiftData model that persists every sent command; `HistoryMatcher` queries it to produce fish-shell-style ghost-text rendered via a `UIViewRepresentable` (`GhostTextField`). `TypoCorrector` loads a bundled JSON map at startup and silently fixes common shell misspellings on every space keystroke. A `CompletionDropdownView` floats above the input bar, fed by a combined stream of history matches and a static bundled command list from `completions.json`. All three layers wire into the existing `SmartInputBar`.

**Tech Stack:** SwiftUI, SwiftData (ModelContext), UIKit (UITextField + CATextLayer for ghost overlay), JSON resources bundled in the app target

---

## Task 1 — CommandHistory SwiftData Model

**Files:**
- Create: `Sources/Mosaic/Models/CommandHistory.swift`
- Modify: `Sources/Mosaic/App/MosaicApp.swift` — add `CommandHistory` to `ModelContainer`

### Steps

- [ ] Create `Sources/Mosaic/Models/CommandHistory.swift` with the following content exactly:

```swift
import SwiftData
import Foundation

@Model
final class CommandHistory {
    var command: String
    var timestamp: Date
    var sessionHostname: String

    init(command: String, sessionHostname: String) {
        self.command = command
        self.timestamp = Date()
        self.sessionHostname = sessionHostname
    }
}
```

- [ ] In `Sources/Mosaic/App/MosaicApp.swift`, update the `ModelContainer` init to include `CommandHistory`:

```swift
// Before:
container = try ModelContainer(for: Connection.self, configurations: config)

// After:
container = try ModelContainer(for: Connection.self, CommandHistory.self, configurations: config)
```

- [ ] Build:

```bash
xcodebuild build \
  -scheme Mosaic \
  -destination 'generic/platform=iOS Simulator' \
  -quiet
```

Confirm `** BUILD SUCCEEDED **`.

- [ ] Commit: `feat: add CommandHistory SwiftData model`

---

## Task 2 — HistoryMatcher

**Files:**
- Create: `Sources/Mosaic/UI/Input/HistoryMatcher.swift`

### Steps

- [ ] Create `Sources/Mosaic/UI/Input/HistoryMatcher.swift`:

```swift
import SwiftData
import Foundation

@MainActor
final class HistoryMatcher {
    private let context: ModelContext

    init(context: ModelContext) { self.context = context }

    /// Returns the ghost-text suffix (the part after `input`) for the best history match.
    func ghostSuffix(for input: String) -> String? {
        guard !input.isEmpty else { return nil }
        let descriptor = FetchDescriptor<CommandHistory>(
            sortBy: [SortDescriptor(\CommandHistory.timestamp, order: .reverse)]
        )
        guard let all = try? context.fetch(descriptor) else { return nil }
        // Deduplicate by command string, preserving recency order
        var seen = Set<String>()
        let unique = all.filter { seen.insert($0.command).inserted }
        guard let match = unique.first(where: {
            $0.command.hasPrefix(input) && $0.command != input
        }) else { return nil }
        return String(match.command.dropFirst(input.count))
    }

    /// Returns the top-N distinct history entries whose command has the given prefix.
    func historyMatches(for input: String, limit: Int = 3) -> [String] {
        guard !input.isEmpty else { return [] }
        let descriptor = FetchDescriptor<CommandHistory>(
            sortBy: [SortDescriptor(\CommandHistory.timestamp, order: .reverse)]
        )
        guard let all = try? context.fetch(descriptor) else { return [] }
        var seen = Set<String>()
        return all
            .filter { seen.insert($0.command).inserted }
            .filter { $0.command.hasPrefix(input) && $0.command != input }
            .prefix(limit)
            .map(\.command)
    }

    /// Persists a sent command, deduplicating and trimming to 10,000 entries.
    func save(command: String, hostname: String) {
        // Remove existing duplicate so the new entry lands at the top
        let dedupeDescriptor = FetchDescriptor<CommandHistory>(
            predicate: #Predicate { $0.command == command }
        )
        if let existing = try? context.fetch(dedupeDescriptor) {
            existing.forEach { context.delete($0) }
        }
        context.insert(CommandHistory(command: command, sessionHostname: hostname))
        // Trim to 10,000 oldest entries
        let allDesc = FetchDescriptor<CommandHistory>(
            sortBy: [SortDescriptor(\CommandHistory.timestamp, order: .forward)]
        )
        if let all = try? context.fetch(allDesc), all.count > 10_000 {
            all.prefix(all.count - 10_000).forEach { context.delete($0) }
        }
        try? context.save()
    }
}
```

- [ ] Build and confirm `** BUILD SUCCEEDED **`.

- [ ] Commit: `feat: add HistoryMatcher for ghost-text and completion history queries`

---

## Task 3 — TypoCorrector + typos.json Resource

**Files:**
- Create: `Resources/typos.json`
- Create: `Sources/Mosaic/UI/Input/TypoCorrector.swift`

### Steps

- [ ] Create `Resources/typos.json` with the bundled typo map. Add the file to the Xcode project target so it is included in the app bundle:

```json
{
  "dokcer": "docker",
  "gti": "git",
  "giit": "git",
  "git statsu": "git status",
  "git commti": "git commit",
  "git pusj": "git push",
  "npx instll": "npx install",
  "kubcetl": "kubectl",
  "tial": "tail",
  "grpe": "grep",
  "pythno": "python",
  "pythohn": "python",
  "sl": "ls",
  "dc": "cd",
  "maek": "make",
  "mak": "make",
  "cta": "cat",
  "les": "less",
  "vom": "vim",
  "suod": "sudo",
  "sduo": "sudo",
  "apt-gt": "apt-get",
  "aptget": "apt-get",
  "chmdo": "chmod",
  "chown -r": "chown -R",
  "rm -Rf": "rm -rf",
  "tial -f": "tail -f",
  "tail -F": "tail -f",
  "grep -ri": "grep -ri",
  "ssh -l": "ssh -l",
  "psuh": "push",
  "pul": "pull",
  "branhc": "branch",
  "stsh": "stash",
  "statsu": "status",
  "comit": "commit",
  "mereg": "merge",
  "rebsae": "rebase",
  "chekcout": "checkout",
  "swithc": "switch",
  "difff": "diff",
  "lgo": "log",
  "cloen": "clone",
  "fecth": "fetch",
  "rmdir": "rmdir",
  "mkidr": "mkdir",
  "chnage": "change",
  "clea": "clear",
  "histroy": "history",
  "whihc": "which",
  "echi": "echo",
  "exoprt": "export",
  "soruce": "source",
  "aliase": "alias",
  "unalisa": "unalias",
  "killl": "kill",
  "pkill -f": "pkill -f",
  "ps auwx": "ps aux",
  "ps awux": "ps aux",
  "curl -XGET": "curl -X GET",
  "curl -XPOST": "curl -X POST",
  "curl -XPUT": "curl -X PUT",
  "curl -XDELETE": "curl -X DELETE",
  "npmi": "npm install",
  "npmr": "npm run",
  "noed": "node",
  "pyhton": "python",
  "pyhton3": "python3",
  "pytnon": "python",
  "runy": "ruby",
  "bundel": "bundle",
  "rspec --forat": "rspec --format",
  "carog": "cargo",
  "rustc ": "rustc",
  "gorun": "go run",
  "gobuild": "go build",
  "mvne": "mvn",
  "gradlew buld": "gradlew build",
  "dokcer-compose": "docker-compose",
  "kubectl get pod": "kubectl get pods",
  "kubect": "kubectl",
  "helml": "helm",
  "terrafrm": "terraform",
  "anisble": "ansible",
  "vagrat": "vagrant",
  "vargant": "vagrant",
  "cehf": "chef",
  "puppe": "puppet",
  "nignx": "nginx",
  "apche": "apache",
  "mysqld": "mysqld",
  "psql -U": "psql -U",
  "redsi": "redis",
  "mongod ": "mongod",
  "cleasr": "clear",
  "exti": "exit",
  "quti": "quit"
}
```

- [ ] Create `Sources/Mosaic/UI/Input/TypoCorrector.swift`:

```swift
import Foundation

/// Loads typos.json at startup and silently corrects common shell misspellings.
/// Call `correct(_:)` after every space character typed.
final class TypoCorrector {
    static let shared = TypoCorrector()
    private var map: [String: String] = [:]

    private init() {
        guard
            let url = Bundle.main.url(forResource: "typos", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        map = dict
    }

    /// Returns a corrected string if a typo was found, otherwise nil.
    /// Should be called after the user types a space character.
    func correct(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // Check the full trimmed input against the typo map first (handles multi-word typos)
        for (typo, fix) in map {
            if trimmed.lowercased() == typo.lowercased() {
                let corrected = input.replacingOccurrences(of: typo, with: fix, options: .caseInsensitive)
                return corrected == input ? nil : corrected
            }
        }

        // Check only the last word (single-word typos)
        let words = trimmed.components(separatedBy: " ")
        guard let lastWord = words.last, !lastWord.isEmpty else { return nil }
        guard let fix = map[lastWord.lowercased()] else { return nil }

        var prefix = words.dropLast().joined(separator: " ")
        if !prefix.isEmpty { prefix += " " }
        let corrected = prefix + fix + (input.hasSuffix(" ") ? " " : "")
        return corrected == input ? nil : corrected
    }
}
```

> **Xcode project step:** In Xcode, drag `Resources/typos.json` into the project navigator and ensure it is added to the app target's "Copy Bundle Resources" build phase. Alternatively, update `project.yml` to include the file under `resources`.

- [ ] Build and confirm `** BUILD SUCCEEDED **`.

- [ ] Commit: `feat: add TypoCorrector and typos.json resource`

---

## Task 4 — completions.json Resource

**Files:**
- Create: `Resources/completions.json`

### Steps

- [ ] Create `Resources/completions.json` with the static bundled command list. Each entry has a `command` string and a `type` of `"command"` or `"snippet"`:

```json
[
  {"command": "git status", "type": "command"},
  {"command": "git add -A", "type": "command"},
  {"command": "git add .", "type": "command"},
  {"command": "git commit -m \"\"", "type": "snippet"},
  {"command": "git commit --amend", "type": "command"},
  {"command": "git push", "type": "command"},
  {"command": "git push --force-with-lease", "type": "command"},
  {"command": "git pull", "type": "command"},
  {"command": "git pull --rebase", "type": "command"},
  {"command": "git fetch --all", "type": "command"},
  {"command": "git branch", "type": "command"},
  {"command": "git branch -a", "type": "command"},
  {"command": "git checkout -b ", "type": "snippet"},
  {"command": "git switch -c ", "type": "snippet"},
  {"command": "git stash", "type": "command"},
  {"command": "git stash pop", "type": "command"},
  {"command": "git log --oneline -20", "type": "command"},
  {"command": "git diff", "type": "command"},
  {"command": "git diff --staged", "type": "command"},
  {"command": "git merge ", "type": "snippet"},
  {"command": "git rebase ", "type": "snippet"},
  {"command": "git rebase -i HEAD~", "type": "snippet"},
  {"command": "git reset --soft HEAD~1", "type": "command"},
  {"command": "git clean -fd", "type": "command"},
  {"command": "docker ps", "type": "command"},
  {"command": "docker ps -a", "type": "command"},
  {"command": "docker images", "type": "command"},
  {"command": "docker logs -f ", "type": "snippet"},
  {"command": "docker exec -it  /bin/bash", "type": "snippet"},
  {"command": "docker stop ", "type": "snippet"},
  {"command": "docker rm ", "type": "snippet"},
  {"command": "docker rmi ", "type": "snippet"},
  {"command": "docker-compose up -d", "type": "command"},
  {"command": "docker-compose down", "type": "command"},
  {"command": "docker-compose logs -f", "type": "command"},
  {"command": "docker build -t  .", "type": "snippet"},
  {"command": "docker pull ", "type": "snippet"},
  {"command": "kubectl get pods", "type": "command"},
  {"command": "kubectl get pods -n ", "type": "snippet"},
  {"command": "kubectl get services", "type": "command"},
  {"command": "kubectl get deployments", "type": "command"},
  {"command": "kubectl logs -f ", "type": "snippet"},
  {"command": "kubectl exec -it  -- /bin/bash", "type": "snippet"},
  {"command": "kubectl apply -f ", "type": "snippet"},
  {"command": "kubectl delete pod ", "type": "snippet"},
  {"command": "kubectl describe pod ", "type": "snippet"},
  {"command": "ls -la", "type": "command"},
  {"command": "ls -lah", "type": "command"},
  {"command": "cd ..", "type": "command"},
  {"command": "cd ~", "type": "command"},
  {"command": "pwd", "type": "command"},
  {"command": "mkdir -p ", "type": "snippet"},
  {"command": "rm -rf ", "type": "snippet"},
  {"command": "cp -r ", "type": "snippet"},
  {"command": "mv ", "type": "snippet"},
  {"command": "cat ", "type": "snippet"},
  {"command": "tail -f ", "type": "snippet"},
  {"command": "tail -n 100 ", "type": "snippet"},
  {"command": "grep -r  .", "type": "snippet"},
  {"command": "grep -rn  .", "type": "snippet"},
  {"command": "find . -name ", "type": "snippet"},
  {"command": "find . -type f -name ", "type": "snippet"},
  {"command": "chmod +x ", "type": "snippet"},
  {"command": "chmod 755 ", "type": "snippet"},
  {"command": "chown -R  .", "type": "snippet"},
  {"command": "ps aux | grep ", "type": "snippet"},
  {"command": "kill -9 ", "type": "snippet"},
  {"command": "ssh ", "type": "snippet"},
  {"command": "scp -r  :", "type": "snippet"},
  {"command": "rsync -avz  :", "type": "snippet"},
  {"command": "curl -s ", "type": "snippet"},
  {"command": "curl -X POST -H 'Content-Type: application/json' -d '' ", "type": "snippet"},
  {"command": "wget ", "type": "snippet"},
  {"command": "npm install", "type": "command"},
  {"command": "npm run dev", "type": "command"},
  {"command": "npm run build", "type": "command"},
  {"command": "npm run test", "type": "command"},
  {"command": "npx ", "type": "snippet"},
  {"command": "yarn install", "type": "command"},
  {"command": "yarn dev", "type": "command"},
  {"command": "pip install ", "type": "snippet"},
  {"command": "pip install -r requirements.txt", "type": "command"},
  {"command": "python3 ", "type": "snippet"},
  {"command": "python3 -m venv venv", "type": "command"},
  {"command": "source venv/bin/activate", "type": "command"},
  {"command": "cargo build", "type": "command"},
  {"command": "cargo run", "type": "command"},
  {"command": "cargo test", "type": "command"},
  {"command": "go build ./...", "type": "command"},
  {"command": "go run .", "type": "command"},
  {"command": "go test ./...", "type": "command"},
  {"command": "terraform init", "type": "command"},
  {"command": "terraform plan", "type": "command"},
  {"command": "terraform apply", "type": "command"},
  {"command": "terraform destroy", "type": "command"},
  {"command": "sudo systemctl restart ", "type": "snippet"},
  {"command": "sudo systemctl status ", "type": "snippet"},
  {"command": "sudo journalctl -fu ", "type": "snippet"},
  {"command": "history | grep ", "type": "snippet"},
  {"command": "htop", "type": "command"},
  {"command": "df -h", "type": "command"},
  {"command": "du -sh *", "type": "command"},
  {"command": "free -h", "type": "command"},
  {"command": "uname -a", "type": "command"},
  {"command": "env | grep ", "type": "snippet"},
  {"command": "export ", "type": "snippet"},
  {"command": "echo $PATH", "type": "command"},
  {"command": "which ", "type": "snippet"},
  {"command": "man ", "type": "snippet"},
  {"command": "vim ", "type": "snippet"},
  {"command": "nano ", "type": "snippet"},
  {"command": "clear", "type": "command"},
  {"command": "exit", "type": "command"}
]
```

> **Xcode project step:** Add `Resources/completions.json` to the app target's "Copy Bundle Resources" build phase (same as `typos.json`).

- [ ] Commit: `feat: add completions.json bundled command list`

---

## Task 5 — CompletionDropdownView

**Files:**
- Create: `Sources/Mosaic/UI/Input/CompletionDropdownView.swift`

### Steps

- [ ] Create `Sources/Mosaic/UI/Input/CompletionDropdownView.swift`:

```swift
import SwiftUI

// MARK: - Completion Item Model

struct CompletionItem: Identifiable, Equatable {
    enum Kind: String { case history, command, snippet }
    let id = UUID()
    let text: String
    let kind: Kind
}

// MARK: - CompletionDropdownView

/// Floating suggestion panel shown above SmartInputBar while the user types.
/// Presents up to 5 items: history matches first, then bundled command matches.
struct CompletionDropdownView: View {
    let items: [CompletionItem]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(items.prefix(5)) { item in
                CompletionRow(item: item)
                    .onTapGesture {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onSelect(item.text)
                    }
                if item != items.prefix(5).last {
                    Divider()
                        .background(Color.mosaicBorder)
                        .padding(.leading, 36)
                }
            }
        }
        .background(Color.mosaicSurface2)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.mosaicBorder, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: -4)
        .padding(.horizontal, 12)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

// MARK: - CompletionRow

private struct CompletionRow: View {
    let item: CompletionItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 12))
                .foregroundColor(iconColor)
                .frame(width: 16, height: 16)

            Text(item.text)
                .font(.custom("JetBrains Mono", size: 13))
                .foregroundColor(.mosaicTextPri)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private var iconName: String {
        switch item.kind {
        case .history: return "clock"
        case .command: return "terminal"
        case .snippet: return "doc.text"
        }
    }

    private var iconColor: Color {
        switch item.kind {
        case .history: return .mosaicTextSec
        case .command: return .mosaicAccent
        case .snippet: return .mosaicBlue
        }
    }
}
```

- [ ] Build and confirm `** BUILD SUCCEEDED **`.

- [ ] Commit: `feat: add CompletionDropdownView`

---

## Task 6 — GhostTextField (UIViewRepresentable)

**Files:**
- Create: `Sources/Mosaic/UI/Input/GhostTextField.swift`

### Steps

- [ ] Create `Sources/Mosaic/UI/Input/GhostTextField.swift`. This wraps `UITextField` to draw a `CATextLayer` ghost-text overlay, and intercepts right-arrow/tab to accept the ghost:

```swift
import SwiftUI
import UIKit

// MARK: - GhostTextField

/// UIViewRepresentable wrapping UITextField.
/// Displays a ghost-text overlay (muted) showing the history match suffix.
/// Right-arrow or Tab accepts the ghost text.
struct GhostTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String = "command"
    var fontSize: CGFloat = 14
    /// The suffix to show as ghost text. Computed externally by HistoryMatcher.
    var ghostSuffix: String?
    /// Called when the user accepts the ghost (right-arrow / Tab).
    var onAcceptGhost: (() -> Void)?
    var onSubmit: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> GhostUITextField {
        let field = GhostUITextField()
        field.delegate = context.coordinator
        field.font = UIFont(name: "JetBrains Mono", size: fontSize)
        field.textColor = UIColor(Color.mosaicTextPri)
        field.tintColor = UIColor(Color.mosaicAccent)
        field.backgroundColor = .clear
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.returnKeyType = .send
        field.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [
                .font: UIFont(name: "JetBrains Mono", size: fontSize) ?? .monospacedSystemFont(ofSize: fontSize, weight: .regular),
                .foregroundColor: UIColor(Color.mosaicTextSec.opacity(0.5))
            ]
        )
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ uiView: GhostUITextField, context: Context) {
        context.coordinator.parent = self
        if uiView.text != text { uiView.text = text }
        uiView.ghostSuffix = ghostSuffix
        uiView.font = UIFont(name: "JetBrains Mono", size: fontSize) ?? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        uiView.updateGhostLayer()
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: GhostTextField

        init(_ parent: GhostTextField) { self.parent = parent }

        @objc func textChanged(_ sender: UITextField) {
            parent.text = sender.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit?()
            return false
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            // Intercept Tab character to accept ghost
            if string == "\t" {
                parent.onAcceptGhost?()
                return false
            }
            return true
        }
    }
}

// MARK: - GhostUITextField

/// Custom UITextField that draws a CATextLayer ghost overlay to the right of the cursor.
final class GhostUITextField: UITextField {
    var ghostSuffix: String? {
        didSet { updateGhostLayer() }
    }

    private let ghostLayer = CATextLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupGhostLayer()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupGhostLayer() {
        ghostLayer.contentsScale = UIScreen.main.scale
        ghostLayer.isWrapped = false
        ghostLayer.truncationMode = .end
        ghostLayer.foregroundColor = UIColor(Color.mosaicTextSec).withAlphaComponent(0.45).cgColor
        layer.addSublayer(ghostLayer)
    }

    func updateGhostLayer() {
        guard let suffix = ghostSuffix, !suffix.isEmpty else {
            ghostLayer.string = nil
            ghostLayer.isHidden = true
            return
        }
        ghostLayer.isHidden = false

        let font = self.font ?? UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let ctFont = CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
        ghostLayer.font = ctFont
        ghostLayer.fontSize = font.pointSize
        ghostLayer.string = suffix

        // Position the ghost just after the last character (approximate via cursor rect)
        setNeedsLayout()
        layoutIfNeeded()
        let caretRect = caretRect(for: endOfDocument)
        let layerHeight = font.lineHeight + 2
        ghostLayer.frame = CGRect(
            x: caretRect.minX,
            y: (bounds.height - layerHeight) / 2,
            width: bounds.width - caretRect.minX,
            height: layerHeight
        )
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateGhostLayer()
    }

    // Handle right-arrow key (hardware keyboard) to accept ghost
    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(
                input: UIKeyCommand.inputRightArrow,
                modifierFlags: [],
                action: #selector(acceptGhost)
            )
        ]
    }

    @objc private func acceptGhost() {
        guard let suffix = ghostSuffix, !suffix.isEmpty else { return }
        let current = text ?? ""
        text = current + suffix
        sendActions(for: .editingChanged)
    }
}
```

- [ ] Build and confirm `** BUILD SUCCEEDED **`.

- [ ] Commit: `feat: add GhostTextField UIViewRepresentable with CATextLayer ghost overlay`

---

## Task 7 — CompletionProvider (aggregates sources)

**Files:**
- Create: `Sources/Mosaic/UI/Input/CompletionProvider.swift`

### Steps

- [ ] Create `Sources/Mosaic/UI/Input/CompletionProvider.swift`. This `@MainActor` `ObservableObject` holds the combined suggestion list and is the single source of truth for the dropdown:

```swift
import Foundation
import SwiftData
import Combine

struct BundledCompletion: Decodable {
    let command: String
    let type: String
}

@MainActor
final class CompletionProvider: ObservableObject {
    @Published var items: [CompletionItem] = []

    private var bundled: [BundledCompletion] = []
    private let matcher: HistoryMatcher

    init(matcher: HistoryMatcher) {
        self.matcher = matcher
        loadBundled()
    }

    private func loadBundled() {
        guard
            let url = Bundle.main.url(forResource: "completions", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([BundledCompletion].self, from: data)
        else { return }
        bundled = decoded
    }

    func update(for input: String) {
        guard !input.isEmpty else {
            items = []
            return
        }

        // History matches (up to 3)
        let historyItems = matcher.historyMatches(for: input, limit: 3).map {
            CompletionItem(text: $0, kind: .history)
        }

        // Bundled command matches (up to 5 total combined, fill remaining slots)
        let remaining = max(0, 5 - historyItems.count)
        let bundledItems = bundled
            .filter { $0.command.lowercased().hasPrefix(input.lowercased()) }
            .prefix(remaining)
            .map { CompletionItem(text: $0.command, kind: $0.type == "snippet" ? .snippet : .command) }

        let combined = historyItems + Array(bundledItems)

        // Deduplicate by text
        var seen = Set<String>()
        items = combined.filter { seen.insert($0.text).inserted }
    }
}
```

- [ ] Build and confirm `** BUILD SUCCEEDED **`.

- [ ] Commit: `feat: add CompletionProvider combining history and bundled completions`

---

## Task 8 — Wire Everything into SmartInputBar

**Files:**
- Modify: `Sources/Mosaic/UI/Input/SmartInputBar.swift`

### Steps

- [ ] Replace the entire contents of `Sources/Mosaic/UI/Input/SmartInputBar.swift` with the wired-up version below. Key changes:
  - Replace `TextField` with `GhostTextField`
  - Add `@StateObject private var completionProvider` fed by `HistoryMatcher`
  - Add `.onChange(of: text)` to call `TypoCorrector` on space and update completions
  - Show `CompletionDropdownView` as an overlay anchored above the input bar
  - Add `hostname` parameter (passed from the session) for `historyMatcher.save()`
  - CC pill now toggles a `@State var ccEnabled` bool with visual feedback
  - On send: call `historyMatcher.save()` and clear completions

```swift
import SwiftUI
import SwiftData

// MARK: - SmartInputBar

@MainActor
struct SmartInputBar: View {
    @Binding var text: String
    let hostname: String
    let onSend: (String) -> Void
    let onNeedsApproval: (String, SafetyTier) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.terminalFontSize) private var fontSize

    @FocusState private var isFocused: Bool
    @State private var ccEnabled: Bool = true
    @State private var ghostSuffix: String? = nil
    @State private var showTypoUnderline: Bool = false

    // Lazy-init via @StateObject trick: inject after modelContext is available
    @StateObject private var completionProvider = CompletionProvider.__placeholder()

    // Resolved on first appear
    @State private var historyMatcher: HistoryMatcher? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Completion dropdown — shown above the bar
            if !completionProvider.items.isEmpty {
                CompletionDropdownView(items: completionProvider.items) { selected in
                    text = selected
                    completionProvider.update(for: selected)
                    ghostSuffix = nil
                }
                .padding(.bottom, 4)
                .animation(.easeInOut(duration: 0.15), value: completionProvider.items.isEmpty)
            }

            Divider().background(Color.mosaicBorder)

            HStack(spacing: 10) {
                // CodeCorrect pill — now toggleable
                Button {
                    ccEnabled.toggle()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: ccEnabled ? "checkmark.circle.fill" : "checkmark.circle")
                            .font(.system(size: 10))
                        Text("CC")
                            .font(.custom("JetBrains Mono", size: 8).weight(.bold))
                            .kerning(0.4)
                    }
                    .foregroundColor(ccEnabled ? .mosaicAccent : .mosaicTextSec)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(ccEnabled ? Color.mosaicAccent.opacity(0.12) : Color.mosaicSurface2)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(ccEnabled ? Color.mosaicAccent.opacity(0.4) : Color.mosaicBorder, lineWidth: 0.5)
                    )
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.15), value: ccEnabled)

                // Ghost-text enabled input field
                GhostTextField(
                    text: $text,
                    placeholder: "command",
                    fontSize: fontSize,
                    ghostSuffix: ccEnabled ? ghostSuffix : nil,
                    onAcceptGhost: {
                        if let suffix = ghostSuffix, ccEnabled {
                            text += suffix
                            ghostSuffix = nil
                            completionProvider.update(for: text)
                        }
                    },
                    onSubmit: { submit() }
                )
                .underline(showTypoUnderline && ccEnabled, color: .mosaicYellow)

                // Mic (Phase 1: placeholder)
                Button {
                    // Phase 2: voice input
                } label: {
                    Image(systemName: "mic")
                        .font(.system(size: 15))
                        .foregroundColor(.mosaicTextSec)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Send button
                Button { submit() } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(text.isEmpty ? .mosaicTextMut : .black)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(text.isEmpty ? Color.mosaicSurface2 : Color.mosaicGreen)
                                .frame(width: 30, height: 30)
                        )
                }
                .buttonStyle(.plain)
                .disabled(text.isEmpty)
                .animation(.easeInOut(duration: 0.15), value: text.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.mosaicSurface1)
        }
        .onAppear {
            let matcher = HistoryMatcher(context: modelContext)
            historyMatcher = matcher
            completionProvider.setup(matcher: matcher)
        }
        .onChange(of: text) { _, newValue in
            guard ccEnabled else { return }

            // Update ghost suffix
            ghostSuffix = historyMatcher?.ghostSuffix(for: newValue)

            // Update completion dropdown
            completionProvider.update(for: newValue)

            // Typo correction — only fires when user just typed a space
            guard newValue.hasSuffix(" ") else { return }
            if let corrected = TypoCorrector.shared.correct(newValue), corrected != newValue {
                text = corrected
                // Brief yellow underline to signal correction (like iOS autocorrect)
                showTypoUnderline = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    showTypoUnderline = false
                }
            }
        }
    }

    private func submit() {
        let cmd = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // Save to history before clearing
        historyMatcher?.save(command: cmd, hostname: hostname)

        // Clear UI state
        ghostSuffix = nil
        completionProvider.items = []

        let tier = SafetyClassifier.shared.classify(cmd)
        switch tier {
        case .safe:
            onSend(cmd)
        case .tier1, .tier2, .tier3:
            onNeedsApproval(cmd, tier)
        }
        isFocused = true
    }
}
```

> **Note on `CompletionProvider.__placeholder()`:** `@StateObject` requires an initial value at declaration time, before `modelContext` is available. Use a lazy-setup pattern: add a static factory and a `setup(matcher:)` method to `CompletionProvider`:

```swift
// Add to CompletionProvider:
static func __placeholder() -> CompletionProvider {
    // Placeholder created before modelContext is available;
    // setup(matcher:) must be called in onAppear.
    final class _PlaceholderMatcher {
        // not used
    }
    // We need a real ModelContext — use a temporary in-memory container.
    // The real matcher is injected via setup(matcher:).
    return CompletionProvider(matcher: nil)
}

// Update init to accept optional:
private var _matcher: HistoryMatcher?

init(matcher: HistoryMatcher?) {
    self._matcher = matcher
    loadBundled()
}

func setup(matcher: HistoryMatcher) {
    self._matcher = matcher
}

// Update historyMatches call to use _matcher:
let historyItems = (_matcher?.historyMatches(for: input, limit: 3) ?? []).map {
    CompletionItem(text: $0, kind: .history)
}
```

- [ ] Update `CompletionProvider.swift` to apply the optional-matcher pattern (as shown above in the Note), so `SmartInputBar` compiles cleanly.

- [ ] Find all call sites of `SmartInputBar` in the project and add the new `hostname:` parameter, passing `session.connection.hostname` (or `""` if unavailable):

```bash
grep -r "SmartInputBar" /Users/ryancalpin/Documents/App\ Development/mosaic-ios/Sources --include="*.swift" -l
```

  Update each call site to include `hostname: session.connection.hostname` (or the appropriate hostname source for that context).

- [ ] Build:

```bash
xcodebuild build \
  -scheme Mosaic \
  -destination 'generic/platform=iOS Simulator' \
  -quiet
```

Confirm `** BUILD SUCCEEDED **`.

- [ ] Commit: `feat: wire CodeCorrect layers into SmartInputBar — ghost text, typo correction, completion dropdown`

---

## Task 9 — Xcode Project Integration

**Files:**
- Modify: `project.yml` (if XcodeGen is used) OR update Xcode project directly

### Steps

- [ ] Ensure `Resources/typos.json` and `Resources/completions.json` are listed in the app target's resource files in `project.yml`:

```yaml
# Under the app target resources section, add:
resources:
  - Resources/typos.json
  - Resources/completions.json
```

- [ ] Regenerate the Xcode project if using XcodeGen:

```bash
cd "/Users/ryancalpin/Documents/App Development/mosaic-ios" && xcodegen generate
```

- [ ] Build to confirm resources resolve at runtime:

```bash
xcodebuild build \
  -scheme Mosaic \
  -destination 'generic/platform=iOS Simulator' \
  -quiet
```

Confirm `** BUILD SUCCEEDED **`.

- [ ] Commit: `chore: register typos.json and completions.json as bundle resources`

---

## Task 10 — Verification

### Steps

- [ ] Run the full test suite:

```bash
xcodebuild test \
  -scheme Mosaic \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -quiet
```

Report pass count.

- [ ] Boot the simulator and launch the app:

```bash
xcrun simctl boot "iPhone 16" 2>/dev/null || true
xcodebuild build-for-testing \
  -scheme Mosaic \
  -destination 'platform=iOS Simulator,name=iPhone 16'
xcrun simctl launch booted <bundle-id>
```

- [ ] Take a simulator screenshot and verify:
  - The CC pill is visible in the input bar and toggles between muted (off) and teal-tinted (on)
  - Typing a few characters with CC on shows ghost-text in muted color
  - Pressing right-arrow or Tab accepts the ghost and appends the suffix
  - Typing a known typo (e.g. `gti `) silently corrects to `git ` with a brief yellow underline
  - Typing `docker p` shows the completion dropdown with at least `docker ps` as a suggestion
  - Tapping a completion fills the input field
  - The dropdown disappears after send

- [ ] Explicitly state: "Build passed, X/X tests pass, UI verified via screenshot"

- [ ] Final commit: `feat: CodeCorrect Phase 1 complete — ghost text, typo correction, completion dropdown`

---

## Summary

| Task | File(s) | Status |
|------|---------|--------|
| 1 | `CommandHistory.swift`, `MosaicApp.swift` | `- [ ]` |
| 2 | `HistoryMatcher.swift` | `- [ ]` |
| 3 | `TypoCorrector.swift`, `typos.json` | `- [ ]` |
| 4 | `completions.json` | `- [ ]` |
| 5 | `CompletionDropdownView.swift` | `- [ ]` |
| 6 | `GhostTextField.swift` | `- [ ]` |
| 7 | `CompletionProvider.swift` | `- [ ]` |
| 8 | `SmartInputBar.swift` (wired) | `- [ ]` |
| 9 | `project.yml` / Xcode resources | `- [ ]` |
| 10 | Verification | `- [ ]` |

**Total new files:** 7  
**Modified files:** 2 (`SmartInputBar.swift`, `MosaicApp.swift`)  
**Resource files:** 2 (`typos.json`, `completions.json`)
