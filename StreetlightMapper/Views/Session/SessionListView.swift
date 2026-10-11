import SwiftUI

// MARK: - All Sessions List

struct SessionListView: View {

    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var sync: SyncService
    @EnvironmentObject private var connectivity: ConnectivityMonitor

    var body: some View {
        NavigationView {
            Group {
                if store.sessions.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(store.sessions.sorted(by: { $0.createdAt > $1.createdAt })) { session in
                            NavigationLink(destination: SessionDetailView(session: session)) {
                                SessionRowView(session: session)
                            }
                            .deleteDisabled(!session.canDelete)
                        }
                        .onDelete { offsets in
                            // Only captures the server has never received can be deleted.
                            let sorted = store.sessions.sorted(by: { $0.createdAt > $1.createdAt })
                            offsets.map { sorted[$0] }.filter { $0.canDelete }
                                .forEach { store.deleteSession(id: $0.id) }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Captured Sessions")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    syncButton
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    connectivityIndicator
                }
            }
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.and.pencil.and.ellipsis")
                .font(.system(size: 52))
                .foregroundColor(.secondary)
            Text("No sessions yet")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Start a new capture workflow to record a Pole ↔ Street Light association.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
        }
    }

    // MARK: Toolbar items

    private var syncButton: some View {
        Button(action: { sync.syncAll() }) {
            if sync.isSyncing {
                ProgressView()
            } else {
                Label("Sync All", systemImage: "arrow.triangle.2.circlepath")
            }
        }
        .disabled(sync.isSyncing || store.pendingSessions().isEmpty)
        .accessibilityIdentifier("history.syncAll")
    }

    private var connectivityIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(connectivity.isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(connectivity.isConnected ? "Online" : "Offline")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Session Row

struct SessionRowView: View {
    let session: CaptureSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.poleID)
                    .font(.headline)
                Spacer()
                SyncStatusBadge(status: session.syncStatus)
            }
            HStack(spacing: 8) {
                ConfidenceBadge(confidence: session.poleConfidence)
                Text("\(session.streetLights.count) street light(s)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(session.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Sync Status Badge

struct SyncStatusBadge: View {
    let status: SyncStatus

    var body: some View {
        Text(status.displayLabel)
            .font(.caption2.bold())
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch status {
        case .pending:  return .orange
        case .syncing:  return .blue
        case .synced:   return .green
        case .failed:   return .red
        }
    }
}

// MARK: - Session Detail

struct SessionDetailView: View {
    let initialSession: CaptureSession
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var workflow: WorkflowViewModel
    @EnvironmentObject private var sync: SyncService
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    @Environment(\.presentationMode) private var presentation
    @State private var confirmDelete = false

    init(session: CaptureSession) {
        self.initialSession = session
    }

    /// Always show the stored copy so edits appear immediately.
    private var session: CaptureSession {
        store.sessions.first(where: { $0.id == initialSession.id }) ?? initialSession
    }

    var body: some View {
        List {
            Section(header: Text("Pole")) {
                LabeledDetailRow(title: "Pole ID", value: session.poleID)
                LabeledDetailRow(title: "Confidence", value: session.poleConfidence.displayLabel)
                LabeledDetailRow(title: "Sync", value: session.syncStatus.displayLabel)
                LabeledDetailRow(title: "Captured", value: session.createdAt.formatted())
            }

            Section(header: Text("Street Lights (\(session.streetLights.count))")) {
                ForEach(session.streetLights) { light in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(light.serialNumber)
                            .font(.system(.body, design: .monospaced))
                        HStack {
                            ConfidenceBadge(confidence: light.confidence)
                            Text(light.capturedAt.formatted(date: .omitted, time: .shortened))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Section(footer: Text(actionsFooter)) {
                if session.needsSync {
                    Button { sync.sync(sessionID: session.id) } label: {
                        Label(sync.isSyncing ? "Syncing…" : "Sync This Capture", systemImage: "arrow.up.circle")
                    }
                    .disabled(sync.isSyncing || !connectivity.isConnected)
                    .accessibilityIdentifier("detail.sync")
                }
                if session.canDelete {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Delete Capture", systemImage: "trash")
                    }
                    .accessibilityIdentifier("detail.delete")
                }
            }
        }
        .listStyle(.insetGrouped)
        .alert("Delete this capture?",
            isPresented: $confirmDelete) {
            Button("Yes, Delete", role: .destructive) {
                store.deleteSession(id: session.id)
                presentation.wrappedValue.dismiss()
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("The Pole ID, street lights and photos will be removed from this phone. This cannot be undone.")
        }
        .navigationTitle(session.poleID)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") { workflow.edit(session) }
            }
        }
    }

    private var actionsFooter: String {
        if session.lastSyncedAt != nil { return "Already sent to the server, so it can't be deleted here." }
        return session.needsSync ? "Saved on this phone only. Sync it when you are ready, or delete it." : ""
    }
}

private struct LabeledDetailRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title).foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
                .multilineTextAlignment(.trailing)
        }
    }
}
