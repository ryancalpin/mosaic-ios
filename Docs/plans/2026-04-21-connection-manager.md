# Connection Manager UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the add-only connection modal with a full CRUD connection manager — edit existing servers, delete with Keychain cleanup, drag-to-reorder, and correct theme support.

**Architecture:** Extract `NewConnectionForm` into a new `ConnectionFormView` that handles both create and edit by accepting an optional `Connection` (nil = create, non-nil = edit, pre-populated from SwiftData + Keychain). Convert `ConnectionSheet`'s `LazyVStack` to a `List` to gain `.swipeActions` and `.onMove` for free. `sortOrder` on the `Connection` model is already present and used by `@Query` — reordering just updates each item's index.

**Tech Stack:** Swift 5.9, SwiftUI, SwiftData, `KeychainHelper`, `@Observable` AppSettings

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `Sources/Mosaic/UI/Connections/ConnectionFormView.swift` | Create + edit form; replaces `NewConnectionForm` |
| Modify | `Sources/Mosaic/UI/Connections/ConnectionSheet.swift` | List with swipe-delete, swipe-edit, drag-reorder; remove `NewConnectionForm`; theme fix |
| Modify | `Sources/Mosaic/UI/RootView.swift` | Inject `AppSettings` into the ConnectionSheet presentation |

---

### Task 1: ConnectionFormView — unified create/edit form

**Files:**
- Create: `Sources/Mosaic/UI/Connections/ConnectionFormView.swift`

This replaces `NewConnectionForm`. When `connection` is non-nil it pre-populates all fields from the model and Keychain, and mutates the existing object on save instead of creating a new one.

- [ ] **Step 1: Create the file**

```swift
// Sources/Mosaic/UI/Connections/ConnectionFormView.swift
import SwiftUI

// MARK: - ConnectionFormView
//
// Unified create/edit form for Connection models.
// connection == nil  → create new Connection and call onSave(newConn)
// connection != nil  → mutate existing Connection in-place and call onSave(existingConn)
// Credentials are read from / written to Keychain, never SwiftData.

@MainActor
struct ConnectionFormView: View {
    let connection: Connection?
    var inlineMode: Bool = false
    var onCancel: (() -> Void)? = nil
    let onSave: (Connection) -> Void

    @Environment(\.dismiss)        private var dismiss
    @Environment(AppSettings.self) private var settings

    @State private var name: String
    @State private var hostname: String
    @State private var port: String
    @State private var username: String
    @State private var password: String
    @State private var privateKey: String
    @State private var transport: TransportProtocol
    @State private var useKeyAuth: Bool

    init(
        connection: Connection? = nil,
        inlineMode: Bool = false,
        onCancel: (() -> Void)? = nil,
        onSave: @escaping (Connection) -> Void
    ) {
        self.connection = connection
        self.inlineMode = inlineMode
        self.onCancel = onCancel
        self.onSave = onSave

        let id = connection?.id.uuidString ?? ""
        let existingKey  = id.isEmpty ? "" : (KeychainHelper.loadPrivateKey(connectionID: id) ?? "")
        let existingPwd  = id.isEmpty ? "" : (KeychainHelper.loadPassword(connectionID: id) ?? "")

        _name       = State(initialValue: connection?.name ?? "")
        _hostname   = State(initialValue: connection?.hostname ?? "")
        _port       = State(initialValue: connection.map { String($0.port) } ?? "22")
        _username   = State(initialValue: connection?.username ?? "")
        _transport  = State(initialValue: connection?.transportProtocol ?? .ssh)
        _useKeyAuth = State(initialValue: !existingKey.isEmpty)
        _privateKey = State(initialValue: existingKey)
        _password   = State(initialValue: existingPwd)
    }

    private var isEditing: Bool { connection != nil }

    private var canSave: Bool {
        !name.isEmpty && !hostname.isEmpty && !username.isEmpty && Int(port) != nil
    }

    // MARK: - Body

    var body: some View {
        if inlineMode {
            formContent
        } else {
            NavigationStack {
                formContent
                    .navigationTitle(isEditing ? "Edit Server" : "New Server")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Cancel") { dismiss() }
                                .foregroundStyle(Color.mosaicTextSec)
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Save") { save() }
                                .font(.custom("JetBrains Mono", size: 12).weight(.bold))
                                .foregroundStyle(canSave ? Color.mosaicAccent : Color.mosaicTextMut)
                                .disabled(!canSave)
                        }
                    }
            }
            .preferredColorScheme(settings.theme.colorScheme)
        }
    }

    // MARK: - Form content

    private var formContent: some View {
        ZStack {
            Color.mosaicBg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    group("Server") {
                        field("Name",     text: $name,     placeholder: "prod-01")
                        field("Hostname", text: $hostname, placeholder: "192.168.1.1")
                        field("Port",     text: $port,     placeholder: "22")
                            .keyboardType(.numberPad)
                        field("Username", text: $username, placeholder: "ryan")
                    }

                    group("Protocol") {
                        Picker("Transport", selection: $transport) {
                            ForEach(TransportProtocol.allCases, id: \.self) { t in
                                Text(t.rawValue).tag(t)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    group("Authentication") {
                        Toggle("Use SSH key", isOn: $useKeyAuth)
                            .tint(.mosaicAccent)
                            .font(.custom("JetBrains Mono", size: 12))
                            .foregroundStyle(Color.mosaicTextPri)

                        if useKeyAuth {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("PRIVATE KEY")
                                    .font(.custom("JetBrains Mono", size: 8).weight(.bold))
                                    .foregroundStyle(Color.mosaicTextSec)
                                TextEditor(text: $privateKey)
                                    .font(.custom("JetBrains Mono", size: 10))
                                    .foregroundStyle(Color.mosaicTextPri)
                                    .frame(height: 100)
                                    .background(Color.mosaicSurface2)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            field("Passphrase (optional)", text: $password, placeholder: "")
                                .textContentType(.password)
                        } else {
                            secureField("Password", text: $password)
                        }
                    }

                    if inlineMode {
                        HStack(spacing: 10) {
                            Button("Cancel") { onCancel?() }
                                .buttonStyle(MosaicSecondaryButtonStyle())
                            Button("Save") { save() }
                                .font(.custom("JetBrains Mono", size: 10).weight(.bold))
                                .foregroundStyle(canSave ? Color.black : Color.mosaicTextMut)
                                .frame(maxWidth: .infinity, minHeight: 38)
                                .background(canSave ? Color.mosaicAccent : Color.mosaicSurface2)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .disabled(!canSave)
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: - Form helpers

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.custom("JetBrains Mono", size: 8).weight(.bold))
                .kerning(0.4)
                .foregroundStyle(Color.mosaicTextSec)
            VStack(spacing: 8) { content() }
                .padding(12)
                .background(Color.mosaicSurface1)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.mosaicBorder, lineWidth: 0.5))
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(label)
                .font(.custom("JetBrains Mono", size: 11))
                .foregroundStyle(Color.mosaicTextSec)
                .frame(width: 90, alignment: .leading)
            TextField(placeholder, text: text)
                .font(.custom("JetBrains Mono", size: 11))
                .foregroundStyle(Color.mosaicTextPri)
                .tint(.mosaicAccent)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
    }

    private func secureField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
                .font(.custom("JetBrains Mono", size: 11))
                .foregroundStyle(Color.mosaicTextSec)
                .frame(width: 90, alignment: .leading)
            SecureField("", text: text)
                .font(.custom("JetBrains Mono", size: 11))
                .foregroundStyle(Color.mosaicTextPri)
                .tint(.mosaicAccent)
                .textContentType(.password)
        }
    }

    // MARK: - Save

    private func save() {
        if let existing = connection {
            // Mutate existing model in-place; SwiftData tracks the change automatically
            existing.name      = name
            existing.hostname  = hostname
            existing.port      = Int(port) ?? 22
            existing.username  = username
            existing.transport = transport.rawValue
            KeychainHelper.deleteCredentials(connectionID: existing.id.uuidString)
            persistCredentials(to: existing.id.uuidString)
            onSave(existing)
        } else {
            let conn = Connection(
                name: name, hostname: hostname,
                port: Int(port) ?? 22, username: username, transport: transport
            )
            persistCredentials(to: conn.id.uuidString)
            onSave(conn)
        }
        if !inlineMode { dismiss() }
    }

    private func persistCredentials(to id: String) {
        if useKeyAuth {
            if !privateKey.isEmpty { KeychainHelper.savePrivateKey(privateKey, connectionID: id) }
            if !password.isEmpty   { KeychainHelper.savePassword(password,    connectionID: id) }
        } else if !password.isEmpty {
            KeychainHelper.savePassword(password, connectionID: id)
        }
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
git add Sources/Mosaic/UI/Connections/ConnectionFormView.swift
git commit -m "feat: ConnectionFormView — unified create/edit form with Keychain pre-population"
```

---

### Task 2: Rewrite ConnectionSheet — List with swipe-delete, swipe-edit, drag-reorder, theme fix

**Files:**
- Modify: `Sources/Mosaic/UI/Connections/ConnectionSheet.swift`

Replace the entire file. This drops `NewConnectionForm` (now `ConnectionFormView`) and `LazyVStack` in favour of `List` which gives `.swipeActions` and `.onMove` for free.

- [ ] **Step 1: Replace the entire file**

```swift
// Sources/Mosaic/UI/Connections/ConnectionSheet.swift
import SwiftUI
import SwiftData

// MARK: - ConnectionSheet
//
// Full connection manager: connect, add, edit, delete, reorder.
// Presented modally from RootView when the user taps + or "Connect".

@MainActor
struct ConnectionSheet: View {
    @Environment(\.modelContext)   private var context
    @Environment(\.dismiss)        private var dismiss
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Connection.sortOrder) private var connections: [Connection]

    @State private var showAddForm       = false
    @State private var editingConnection: Connection? = nil
    @State private var connectError: String? = nil

    let onConnect: (Connection) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.mosaicBg.ignoresSafeArea()

                if connections.isEmpty {
                    emptyState
                } else {
                    connectionList
                }
            }
            .navigationTitle("Servers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.mosaicTextSec)
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    EditButton()
                        .foregroundStyle(Color.mosaicAccent)
                        .font(.custom("JetBrains Mono", size: 12))
                    Button {
                        showAddForm = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(Color.mosaicAccent)
                    }
                }
            }
            .sheet(isPresented: $showAddForm) {
                ConnectionFormView { newConn in
                    newConn.sortOrder = connections.count
                    context.insert(newConn)
                    try? context.save()
                }
                .environment(AppSettings.shared)
            }
            .sheet(item: $editingConnection) { conn in
                ConnectionFormView(connection: conn) { _ in
                    try? context.save()
                }
                .environment(AppSettings.shared)
            }
            .alert("Connection Error", isPresented: Binding(
                get: { connectError != nil },
                set: { if !$0 { connectError = nil } }
            )) {
                Button("OK") { connectError = nil }
            } message: {
                Text(connectError ?? "")
            }
        }
        .preferredColorScheme(settings.theme.colorScheme)
    }

    // MARK: - List

    private var connectionList: some View {
        List {
            ForEach(connections) { conn in
                ConnectionCard(connection: conn) {
                    onConnect(conn)
                    dismiss()
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14))
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        delete(conn)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button {
                        editingConnection = conn
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.mosaicAccent)
                }
            }
            .onMove(perform: move)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "server.rack")
                .font(.system(size: 44))
                .foregroundStyle(Color.mosaicTextSec)
            Text("No saved servers")
                .font(.custom("JetBrains Mono", size: 14))
                .foregroundStyle(Color.mosaicTextSec)
            Button("Add a server") { showAddForm = true }
                .font(.custom("JetBrains Mono", size: 12).weight(.bold))
                .foregroundStyle(Color.mosaicAccent)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.mosaicAccent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Helpers

    private func delete(_ conn: Connection) {
        KeychainHelper.deleteCredentials(connectionID: conn.id.uuidString)
        context.delete(conn)
        try? context.save()
    }

    private func move(from source: IndexSet, to destination: Int) {
        // `connections` is already sorted by sortOrder from @Query.
        // Remapping indices after the move keeps sortOrder contiguous.
        var sorted = connections
        sorted.move(fromOffsets: source, toOffset: destination)
        for (index, conn) in sorted.enumerated() {
            conn.sortOrder = index
        }
        try? context.save()
    }
}

// MARK: - ConnectionCard

struct ConnectionCard: View {
    let connection: Connection
    let onConnect: () -> Void

    var body: some View {
        Button(action: onConnect) {
            HStack(spacing: 12) {
                Circle()
                    .fill(connection.transportProtocol == .mosh ? Color.mosaicPurple : Color.mosaicBlue)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 3) {
                    Text(connection.name)
                        .font(.custom("JetBrains Mono", size: 12).weight(.semibold))
                        .foregroundStyle(Color.mosaicTextPri)
                    Text("\(connection.username)@\(connection.hostname):\(connection.port)")
                        .font(.custom("JetBrains Mono", size: 9.5))
                        .foregroundStyle(Color.mosaicTextSec)
                }

                Spacer()

                ProtocolBadge(transport: connection.transportProtocol, isRoaming: false)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.mosaicTextMut)
            }
            .padding(12)
            .background(Color.mosaicSurface1)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.mosaicBorder, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild build -scheme Mosaic -destination 'generic/platform=iOS Simulator' 2>&1 | grep -E 'error:|BUILD'
```

Expected: `** BUILD SUCCEEDED **`

If you see `error: cannot find 'NewConnectionForm'` — that type was only used inside `ConnectionSheet.swift` itself and is now gone. Any other reference is unexpected; search with `grep -r "NewConnectionForm" Sources/` and remove it.

- [ ] **Step 3: Commit**

```bash
git add Sources/Mosaic/UI/Connections/ConnectionSheet.swift
git commit -m "feat: ConnectionSheet — List with swipe-edit/delete, drag-reorder, theme support"
```

---

### Task 3: Inject AppSettings into ConnectionSheet presentation in RootView

**Files:**
- Modify: `Sources/Mosaic/UI/RootView.swift`

SwiftUI sheets don't inherit the parent's environment. `ConnectionSheet` reads `@Environment(AppSettings.self)` so the sheet must inject it.

- [ ] **Step 1: Add `.environment(AppSettings.shared)` to the ConnectionSheet sheet**

Find this block in `Sources/Mosaic/UI/RootView.swift`:

```swift
.sheet(isPresented: $showConnectionSheet) {
    ConnectionSheet { connection in
        Task {
            if let err = await manager.openSessionThrowing(for: connection) {
                connectionError = (err as any Error).localizedDescription
            }
        }
    }
}
```

Replace with:

```swift
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
```

- [ ] **Step 2: Build**

```bash
xcodebuild build -scheme Mosaic -destination 'generic/platform=iOS Simulator' 2>&1 | grep -E 'error:|BUILD'
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Sources/Mosaic/UI/RootView.swift
git commit -m "fix: inject AppSettings into ConnectionSheet so theme applies correctly"
```

---

### Task 4: Build, run, visual verify

- [ ] **Step 1: Boot simulator and run**

Use XcodeBuildMCP. Simulator ID: `913B454F-493C-46DC-B2B4-63348DA39843` (iPhone 17 Pro), bundle ID: `com.ryncalpin.mosaic`.

```bash
# Build and install
xcodebuild build -scheme Mosaic -destination 'id=913B454F-493C-46DC-B2B4-63348DA39843' 2>&1 | tail -5
```

- [ ] **Step 2: Verify — Add a server**

1. Tap "Connect to a server" on the empty state → ConnectionSheet opens
2. Tap `+` → ConnectionFormView opens with "New Server" title
3. Fill in: Name="test", Hostname="localhost", Port="22", Username="ryan", password "test"
4. Tap Save → card appears in the list ✓

- [ ] **Step 3: Verify — Edit a server**

1. Swipe right on the card → "Edit" action appears in teal ✓
2. Tap Edit → ConnectionFormView opens with "Edit Server" title, pre-populated fields ✓
3. Change the Name → tap Save → card updates ✓

- [ ] **Step 4: Verify — Delete a server**

1. Swipe left on a card → red "Delete" button appears ✓
2. Tap Delete → card removed ✓

- [ ] **Step 5: Verify — Reorder**

1. Tap "Edit" button in the toolbar → drag handles appear on rows ✓
2. Drag a row to a new position → order persists after tapping "Done" ✓

- [ ] **Step 6: Verify — Theme**

1. Open Settings (gear icon) → switch to Light theme → dismiss
2. Open Servers sheet → sheet uses light colors ✓

- [ ] **Step 7: Commit any fixes needed**

```bash
git add -p
git commit -m "fix: connection manager visual verification corrections"
```

---

## Self-Review

### Spec Coverage

| Requirement | Task |
|---|---|
| Edit existing connection (all fields) | Task 1 (`ConnectionFormView` edit mode) |
| Edit loads Keychain credentials | Task 1 (`loadPrivateKey` / `loadPassword` in init) |
| Delete with Keychain cleanup | Task 2 (`delete()` calls `KeychainHelper.deleteCredentials`) |
| Drag-to-reorder with persistence | Task 2 (`move()` updates `sortOrder`, `context.save()`) |
| Swipe-to-delete | Task 2 (`.swipeActions(edge: .trailing)`) |
| Swipe-to-edit | Task 2 (`.swipeActions(edge: .leading)`) |
| Theme-aware ConnectionSheet | Task 2 (`@Environment(AppSettings.self)` + `preferredColorScheme`) |
| Theme-aware ConnectionFormView | Task 1 (`@Environment(AppSettings.self)` + `preferredColorScheme`) |
| AppSettings injected into sheet | Task 3 (`.environment(AppSettings.shared)` in RootView) |

### No Placeholders ✓

### Type Consistency

- `ConnectionFormView(connection: Connection?, ...)` — defined Task 1, used Task 2 in `showAddForm` sheet (no `connection`) and `editingConnection` sheet (with `connection`) ✓
- `Connection.sortOrder: Int` — exists in `Sources/Mosaic/Models/Connection.swift`, set in `move()` ✓
- `KeychainHelper.deleteCredentials(connectionID:)` — exists in `Sources/Mosaic/Core/KeychainHelper.swift` ✓
- `KeychainHelper.loadPrivateKey(connectionID:)` / `loadPassword(connectionID:)` — both exist ✓
- `AppSettings.shared` — singleton defined in `Sources/Mosaic/Settings/AppSettings.swift` ✓
