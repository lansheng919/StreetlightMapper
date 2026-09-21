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
                        }
                        .onDelete { offsets in
                            let sorted = store.sessions.sorted(by: { $0.createdAt > $1.createdAt })
                            offsets.forEach { store.deleteSession(id: sorted[$0].id) }
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
                Label("Sync", systemImage: "arrow.triangle.2.circlepath")
            }
        }
        .disabled(sync.isSyncing)
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
    let session: CaptureSession
    @EnvironmentObject private var store: SessionStore

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
        }
        .listStyle(.insetGrouped)
        .navigationTitle(session.poleID)
        .navigationBarTitleDisplayMode(.inline)
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
