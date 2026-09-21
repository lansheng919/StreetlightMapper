import SwiftUI

@main
struct StreetlightMapperApp: App {

    // MARK: Services (shared across all views via environment)

    @StateObject private var store       = SessionStore()
    @StateObject private var connectivity = ConnectivityMonitor()
    @StateObject private var mockServer  = MockSAPServer()

    // SyncService depends on store + connectivity — initialised lazily in body
    @StateObject private var sync: SyncService
    @StateObject private var workflow: WorkflowViewModel

    // MARK: Init

    init() {
        let store        = SessionStore()
        let connectivity = ConnectivityMonitor()
        let sync         = SyncService(store: store, connectivity: connectivity)
        let workflow     = WorkflowViewModel(store: store, sync: sync)

        _store        = StateObject(wrappedValue: store)
        _connectivity = StateObject(wrappedValue: connectivity)
        _sync         = StateObject(wrappedValue: sync)
        _workflow     = StateObject(wrappedValue: workflow)
        _mockServer   = StateObject(wrappedValue: MockSAPServer())
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
