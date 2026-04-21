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
                    newConn.sortOrder = (connections.map(\.sortOrder).max() ?? -1) + 1
                    context.insert(newConn)
                    do {
                        try context.save()
                    } catch {
                        connectError = error.localizedDescription
                    }
                }
                .environment(AppSettings.shared)
            }
            .sheet(item: $editingConnection) { conn in
                ConnectionFormView(connection: conn) { _ in
                    do {
                        try context.save()
                    } catch {
                        connectError = error.localizedDescription
                    }
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
        do {
            try context.save()
        } catch {
            connectError = error.localizedDescription
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var sorted = connections
        sorted.move(fromOffsets: source, toOffset: destination)
        for (index, conn) in sorted.enumerated() where conn.sortOrder != index {
            conn.sortOrder = index
        }
        do {
            try context.save()
        } catch {
            connectError = error.localizedDescription
        }
    }
}

// MARK: - ConnectionCard

@MainActor
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
