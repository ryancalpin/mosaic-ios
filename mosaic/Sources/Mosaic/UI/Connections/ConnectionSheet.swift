import SwiftUI
import SwiftData

// MARK: - ConnectionSheet
//
// Modal sheet for managing saved connections and adding new ones.
// Tapping a saved host opens it in a new tab.

struct ConnectionSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Connection.sortOrder) private var connections: [Connection]

    @State private var showNewForm = false
    @State private var connectError: String? = nil

    let onConnect: (Connection) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.mosaicBg.ignoresSafeArea()

                if connections.isEmpty && !showNewForm {
                    emptyState
                } else {
                    connectionList
                }
            }
            .navigationTitle("Connect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.mosaicTextSec)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showNewForm = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundColor(.mosaicAccent)
                    }
                }
            }
            .sheet(isPresented: $showNewForm) {
                NewConnectionForm { newConn in
                    context.insert(newConn)
                    try? context.save()
                }
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
        .preferredColorScheme(.dark)
    }

    // MARK: - Subviews

    private var connectionList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if showNewForm {
                    NewConnectionForm(inlineMode: true, onCancel: { showNewForm = false }) { newConn in
                        context.insert(newConn)
                        try? context.save()
                        showNewForm = false
                    }
                    .padding(14)
                }

                ForEach(connections) { conn in
                    ConnectionCard(connection: conn) {
                        onConnect(conn)
                        dismiss()
                    }
                }
            }
            .padding(14)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "server.rack")
                .font(.system(size: 44))
                .foregroundColor(.mosaicTextSec)
            Text("No saved servers")
                .font(.custom("JetBrains Mono", size: 14))
                .foregroundColor(.mosaicTextSec)
            Button("Add a server") {
                showNewForm = true
            }
            .font(.custom("JetBrains Mono", size: 12).weight(.bold))
            .foregroundColor(.mosaicAccent)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.mosaicAccent.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - ConnectionCard

struct ConnectionCard: View {
    let connection: Connection
    let onConnect: () -> Void

    var body: some View {
        Button(action: onConnect) {
            HStack(spacing: 12) {
                // Protocol dot
                Circle()
                    .fill(connection.transportProtocol == .mosh ? Color.mosaicPurple : Color.mosaicBlue)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 3) {
                    Text(connection.name)
                        .font(.custom("JetBrains Mono", size: 12).weight(.semibold))
                        .foregroundColor(.mosaicTextPri)
                    Text("\(connection.username)@\(connection.hostname):\(connection.port)")
                        .font(.custom("JetBrains Mono", size: 9.5))
                        .foregroundColor(.mosaicTextSec)
                }

                Spacer()

                ProtocolBadge(transport: connection.transportProtocol, isRoaming: false)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(.mosaicTextMut)
            }
            .padding(12)
            .background(Color.mosaicSurface1)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.mosaicBorder, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - NewConnectionForm

struct NewConnectionForm: View {
    var inlineMode: Bool = false   // true when embedded directly (not in its own sheet)
    var onCancel: (() -> Void)? = nil   // inline mode only: called when user taps Cancel
    let onSave: (Connection) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name       = ""
    @State private var hostname   = ""
    @State private var port       = "22"
    @State private var username   = ""
    @State private var password   = ""
    @State private var privateKey = ""
    @State private var transport  = TransportProtocol.ssh
    @State private var useKeyAuth = false

    private var canSave: Bool {
        !name.isEmpty && !hostname.isEmpty && !username.isEmpty
    }

    var body: some View {
        if inlineMode {
            formContent
        } else {
            NavigationStack {
                formContent
                    .navigationTitle("New Server")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Cancel") { dismiss() }
                                .foregroundColor(.mosaicTextSec)
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Save") { save() }
                                .font(.custom("JetBrains Mono", size: 12).weight(.bold))
                                .foregroundColor(canSave ? .mosaicAccent : .mosaicTextMut)
                                .disabled(!canSave)
                        }
                    }
            }
            .preferredColorScheme(.dark)
        }
    }

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
                            .foregroundColor(.mosaicTextPri)

                        if useKeyAuth {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("PRIVATE KEY")
                                    .font(.custom("JetBrains Mono", size: 8).weight(.bold))
                                    .foregroundColor(.mosaicTextSec)
                                TextEditor(text: $privateKey)
                                    .font(.custom("JetBrains Mono", size: 10))
                                    .foregroundColor(.mosaicTextPri)
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
                                .foregroundColor(canSave ? .black : .mosaicTextMut)
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

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.custom("JetBrains Mono", size: 8).weight(.bold))
                .kerning(0.4)
                .foregroundColor(.mosaicTextSec)
            VStack(spacing: 8) {
                content()
            }
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
                .foregroundColor(.mosaicTextSec)
                .frame(width: 90, alignment: .leading)
            TextField(placeholder, text: text)
                .font(.custom("JetBrains Mono", size: 11))
                .foregroundColor(.mosaicTextPri)
                .tint(.mosaicAccent)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
    }

    private func secureField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
                .font(.custom("JetBrains Mono", size: 11))
                .foregroundColor(.mosaicTextSec)
                .frame(width: 90, alignment: .leading)
            SecureField("", text: text)
                .font(.custom("JetBrains Mono", size: 11))
                .foregroundColor(.mosaicTextPri)
                .tint(.mosaicAccent)
                .textContentType(.password)
        }
    }

    private func save() {
        let conn = Connection(
            name:      name,
            hostname:  hostname,
            port:      Int(port) ?? 22,
            username:  username,
            transport: transport
        )

        if useKeyAuth {
            if !privateKey.isEmpty {
                KeychainHelper.savePrivateKey(privateKey, connectionID: conn.id.uuidString)
            }
            if !password.isEmpty {
                KeychainHelper.savePassword(password, connectionID: conn.id.uuidString)
            }
        } else if !password.isEmpty {
            KeychainHelper.savePassword(password, connectionID: conn.id.uuidString)
        }

        onSave(conn)
        // inlineMode: parent controls teardown via showNewForm = false in onSave closure.
        // Calling dismiss() here would close the parent ConnectionSheet entirely.
        if !inlineMode { dismiss() }
    }
}
