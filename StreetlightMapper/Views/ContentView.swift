import SwiftUI

// MARK: - Root Content View
// Tabs: Home | History | Integration Test.
// The capture flow opens full screen from Home so the camera never starts unprompted.

struct ContentView: View {

    @EnvironmentObject private var workflow: WorkflowViewModel
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(selectedTab: $selectedTab)
                .tabItem { Label("Home", systemImage: "house") }
                .tag(0)

            SessionListView()
                .tabItem { Label("History", systemImage: "list.bullet.clipboard") }
                .tag(1)

            DebugView()
                .tabItem { Label("Integration", systemImage: "network") }
                .tag(2)
        }
        .fullScreenCover(isPresented: $workflow.isActive, onDismiss: workflow.cleanupAfterDismiss) {
            captureWorkflowView
                .environmentObject(workflow)
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
