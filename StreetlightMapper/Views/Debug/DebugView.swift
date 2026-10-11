import SwiftUI

// MARK: - Debug / SAP Integration Test View
// Lets a tester inspect the mock server, trigger manual sync,
// and send a sample payload — without a live SAP environment.

struct DebugView: View {

    @EnvironmentObject private var mockServer: MockSAPServer
    @EnvironmentObject private var sync: SyncService
    @EnvironmentObject private var store: SessionStore

    @State private var curlOutput = ""
    @State private var showCopied = false

    var body: some View {
        NavigationView {
            List {
                serverSection
                endpointsSection
                receivedSection
                syncSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Integration Test")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: Server Section

    private var serverSection: some View {
        Section(header: Text("Mock SAP Server")) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Status")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text(mockServer.isRunning ? "Running ✓" : "Stopped")
                        .font(.headline)
                        .foregroundColor(mockServer.isRunning ? .green : .red)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { mockServer.isRunning },
                    set: { on in on ? mockServer.start() : mockServer.stop() }
                ))
            }

            if mockServer.isRunning {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Base URL")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("http://localhost:\(mockServer.port)/api/v1")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(.blue)
                        .contextMenu {
                            Button("Copy URL") {
                                UIPasteboard.general.string = "http://localhost:\(mockServer.port)/api/v1"
                                showCopied = true
                            }
                        }
                }
            }
        }
    }

    // MARK: Endpoints Section

    private var endpointsSection: some View {
        Section(header: Text("Available Endpoints")) {
            ForEach(endpoints, id: \.0) { (method, path, description) in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(method)
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(methodColor(method))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        Text(path)
                            .font(.system(.caption, design: .monospaced))
                    }
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private let endpoints: [(String, String, String)] = [
        ("GET",  "/api/v1/health",          "Health check — returns {\"status\":\"ok\"}"),
        ("GET",  "/api/v1/sessions",        "List all received sessions"),
        ("GET",  "/api/v1/sessions/:id",    "Fetch a single session by ID"),
        ("POST", "/api/v1/sessions",        "Accept a session payload (used by sync)")
    ]

    private func methodColor(_ method: String) -> Color {
        switch method {
        case "GET":  return .blue
        case "POST": return .green
        default:     return .gray
        }
    }

    // MARK: Received Sessions

    private var receivedSection: some View {
        Section(header: HStack {
            Text("Received by Mock Server")
            Spacer()
            Text("\(mockServer.receivedSessions.count)")
                .font(.caption)
                .foregroundColor(.blue)
        }) {
            if mockServer.receivedSessions.isEmpty {
                Text("None yet — trigger a sync to send data")
                    .foregroundColor(.secondary)
                    .font(.caption)
            } else {
                ForEach(mockServer.receivedSessions, id: \.sessionId) { dto in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dto.poleId)
                            .font(.system(.body, design: .monospaced))
                        Text("\(dto.streetLights.count) street light(s) · \(dto.confidence ?? "–")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Sync Section

    private var syncSection: some View {
        Section(header: Text("Sync")) {
            HStack {
                Text("Pending")
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(store.pendingSessions().count)")
            }

            Toggle(isOn: $sync.autoSyncEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-sync when online")
                    Text("Off: you sync manually from Home or History.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .accessibilityIdentifier("debug.autoSync")

            Button(action: { sync.syncAll() }) {
                Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(sync.isSyncing)

            if !sync.lastSyncMessage.isEmpty {
                Text(sync.lastSyncMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Helper extension for DTO display

private extension SessionDTO {
    var confidence: String? { poleConfidence }
}
