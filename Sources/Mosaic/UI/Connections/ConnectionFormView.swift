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
        guard !name.isEmpty, !hostname.isEmpty, !username.isEmpty,
              let p = Int(port), (1...65535).contains(p) else { return false }
        return useKeyAuth ? !privateKey.isEmpty : !password.isEmpty
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
                                    .scrollContentBackground(.hidden)
                                    .background(Color.mosaicSurface2)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            field("Passphrase", text: $password, placeholder: "optional")
                                .textContentType(.password)
                                .submitLabel(.done)
                        } else {
                            secureField("Password", text: $password)
                                .submitLabel(.done)
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
