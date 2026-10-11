import SwiftUI

// MARK: - Home (start page)
// Common field-app pattern: one obvious primary action, resume for unfinished work,
// a short "how it works" guide, live status, and recent items that can be tapped to edit.

struct HomeView: View {

    @EnvironmentObject private var workflow: WorkflowViewModel
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var sync: SyncService
    @EnvironmentObject private var connectivity: ConnectivityMonitor

    @State private var confirmDiscard = false
    @Binding var selectedTab: Int

    private var recent: [CaptureSession] {
        Array(store.sessions.sorted { $0.updatedAt > $1.updatedAt }.prefix(3))
    }

    private var unsyncedCount: Int {
        store.sessions.filter { $0.needsSync }.count
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    statusRow
                    if workflow.hasDraft && !workflow.isEditingExisting { resumeCard }
                    startButton
                    if unsyncedCount > 0 || !sync.lastSyncMessage.isEmpty { syncCard }
                    howItWorks
                    if !recent.isEmpty { recentSection }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .navigationTitle("Streetlight Mapper")
            .confirmationDialog("Discard the unfinished capture?",
                                isPresented: $confirmDiscard,
                                titleVisibility: .visible) {
                Button("Discard capture", role: .destructive) { workflow.discardDraft() }
                Button("Keep it", role: .cancel) {}
            } message: {
                Text("The Pole ID and street lights captured so far will be lost.")
            }
        }
    }

    // MARK: Status

    private var statusRow: some View {
        HStack(spacing: 10) {
            StatusChip(
                icon: connectivity.isConnected ? "wifi" : "wifi.slash",
                text: connectivity.isConnected ? "Online" : "Offline – saving locally",
                color: connectivity.isConnected ? .green : .orange
            )
            Spacer(minLength: 0)
        }
    }

    // MARK: Sync (separate action, done whenever the technician chooses)

    private var syncCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if unsyncedCount > 0 {
                Label("\(unsyncedCount) capture\(unsyncedCount == 1 ? "" : "s") saved on this phone, not yet synced",
                      systemImage: "arrow.up.circle")
                    .font(.subheadline.bold())
                    .foregroundColor(.blue)
                Button { sync.syncAll() } label: {
                    Text(sync.isSyncing ? "Syncing…" : "Sync All Now")
                }
                .buttonStyle(ActionButtonStyle(color: .blue))
                .disabled(sync.isSyncing || !connectivity.isConnected)
                .accessibilityIdentifier("home.syncAll")
                if !connectivity.isConnected {
                    Text("You are offline. Sync later when you have a connection.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            if !sync.lastSyncMessage.isEmpty {
                Text(sync.lastSyncMessage)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .accessibilityIdentifier("home.syncMessage")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(14)
    }

    // MARK: Resume

    private var resumeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Unfinished capture", systemImage: "clock.arrow.circlepath")
                .font(.subheadline.bold())
                .foregroundColor(.orange)

            if let s = workflow.session {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pole \(s.poleID)")
                        .font(.system(.headline, design: .monospaced))
                    Text("\(s.streetLights.count) street light\(s.streetLights.count == 1 ? "" : "s") captured")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 12) {
                Button("Resume") { workflow.resume() }
                    .buttonStyle(ActionButtonStyle(color: .orange))
                Button("Discard") { confirmDiscard = true }
                    .buttonStyle(ActionButtonStyle(color: Color(white: 0.3)))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.6), lineWidth: 1))
        .cornerRadius(14)
    }

    // MARK: Primary action

    private var startButton: some View {
        Button { workflow.startNew() } label: {
            HStack(spacing: 10) {
                Image(systemName: "camera.viewfinder")
                    .font(.title2)
                Text("Start New Capture")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .foregroundColor(.white)
            .background(Color.blue)
            .cornerRadius(14)
        }
        .accessibilityHint("Opens the camera to scan a Pole ID")
    }

    // MARK: How it works

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How it works")
                .font(.headline)

            StepRow(icon: "number.square", title: "1. Scan the Pole ID",
                    detail: "Point the camera at the pole label. A green frame means it was read with high confidence and the photo is taken for you.")
            StepRow(icon: "qrcode.viewfinder", title: "2. Scan each street light",
                    detail: "Scan the QR code on every light on that pole. Add as many as you need.")
            StepRow(icon: "checkmark.seal", title: "3. Check and save",
                    detail: "Review what was captured, fix anything that needed a manual check, then save. Syncing is a separate step you can do now or later.")

            Label("Yellow means check the value. You can correct it by hand before the photo is saved.",
                  systemImage: "info.circle")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(14)
    }

    // MARK: Recent

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent captures")
                    .font(.headline)
                Spacer()
                Button("See all") { selectedTab = 1 }
                    .font(.subheadline)
            }

            VStack(spacing: 0) {
                ForEach(Array(recent.enumerated()), id: \.element.id) { idx, session in
                    Button { workflow.edit(session) } label: {
                        HStack {
                            SessionRowView(session: session)
                            Image(systemName: "chevron.right")
                                .font(.footnote.bold())
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if idx < recent.count - 1 { Divider().padding(.leading, 16) }
                }
            }
            .background(Color(.secondarySystemBackground))
            .cornerRadius(14)

            Text("Tap a capture to review or correct it.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Small components

private struct StatusChip: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.bold())
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
}

private struct StepRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(Color.blue.opacity(0.2)).frame(width: 36, height: 36)
                Image(systemName: icon).foregroundColor(.blue)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                Text(detail)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
