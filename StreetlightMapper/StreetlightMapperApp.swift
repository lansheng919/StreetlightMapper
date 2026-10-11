import SwiftUI

@main
struct StreetlightMapperApp: App {

    // MARK: Services (shared across all views via environment)

    @StateObject private var store: SessionStore
    @StateObject private var connectivity: ConnectivityMonitor
    @StateObject private var mockServer: MockSAPServer
    @StateObject private var sync: SyncService
    @StateObject private var workflow: WorkflowViewModel

    // MARK: Init

    init() {
        let args = ProcessInfo.processInfo.arguments
        let uiTesting = args.contains("-UITesting")

        // UI tests run against a throw-away database and a fixed network state,
        // so they never touch real data and behave the same every time.
        let store: SessionStore
        let connectivity: ConnectivityMonitor
        var defaults = UserDefaults.standard
        if uiTesting {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("uitest-\(UUID().uuidString)", isDirectory: true)
            store = SessionStore(directory: dir)
            connectivity = ConnectivityMonitor(simulatedConnected: !args.contains("-UITestingOffline"))
            let suite = "uitest-\(UUID().uuidString)"
            defaults = UserDefaults(suiteName: suite) ?? .standard
            defaults.removePersistentDomain(forName: suite)
            if args.contains("-UITestingSeed") {
                store.addSession(Self.seedSession())
            }
            if args.contains("-UITestingSeedSynced") {
                var s = Self.seedSession()
                s.markSynced()
                store.addSession(s)
            }
        } else {
            store = SessionStore()
            connectivity = ConnectivityMonitor()
        }

        let sync     = SyncService(store: store, connectivity: connectivity, defaults: defaults)
        let workflow = WorkflowViewModel(store: store, sync: sync)

        _store        = StateObject(wrappedValue: store)
        _connectivity = StateObject(wrappedValue: connectivity)
        _sync         = StateObject(wrappedValue: sync)
        _workflow     = StateObject(wrappedValue: workflow)
        _mockServer   = StateObject(wrappedValue: MockSAPServer())
    }

    private static func seedSession() -> CaptureSession {
        var s = CaptureSession(poleID: "208125", poleConfidence: .high)
        s.addStreetLight(StreetLightEntry(sessionID: s.id, serialNumber: "E5000531", confidence: .high))
        s.addStreetLight(StreetLightEntry(sessionID: s.id, serialNumber: "E5000532", confidence: .manual))
        return s
    }

    // MARK: Scene

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(connectivity)
                .environmentObject(sync)
                .environmentObject(mockServer)
                .environmentObject(workflow)
                .onAppear {
                    // Start mock server on launch
                    mockServer.start(port: 8080)
                }
        }
    }
}
