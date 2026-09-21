import SwiftUI

// MARK: - Root Content View
// Tab bar: New Capture | History | Integration Test

struct ContentView: View {

    @EnvironmentObject private var workflow: WorkflowViewModel
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 1 — active capture workflow
            captureWorkflowView
                .tabItem { Label("Capture", systemImage: "camera.viewfinder") }
                .tag(0)

            // Tab 2 — saved sessions
            SessionListView()
                .tabItem { Label("History", systemImage: "list.bullet.clipboard") }
                .tag(1)

            // Tab 3 — mock SAP integration / debug
            DebugView()
                .tabItem { Label("Integration", systemImage: "network") }
                .tag(2)
        }
        // After saving, jump to History automatically
        .onChange(of: workflow.isSaved) { saved in
            if saved { selectedTab = 1 }
        }
    }

    // MARK: Capture Workflow

    @ViewBuilder
    private var captureWorkflowView: some View {
        switch workflow.currentStep {
        case .capturePoloID:
            PoleIDCaptureView()
        case .captureStreetLight:
            StreetLightCaptureView()
        case .review:
            SessionReviewView()
        }
    }
}
