import SwiftUI

// MARK: - Session Review Screen
// Shows the Pole ID, all captured street lights, confidence status,
// and provides Save / Add-Another / Reset actions.

struct SessionReviewView: View {

    @EnvironmentObject private var workflow: WorkflowViewModel
    @EnvironmentObject private var store: SessionStore

    var body: some View {
        NavigationView {
            List {
                poleSection
                streetLightSection
                actionsSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: Pole Section

    private var poleSection: some View {
        Section(header: Text("Pole ID")) {
            if let s = workflow.session {
                LabeledRow(title: "Pole ID", value: s.poleID)
                LabeledRow(title: "Capture quality",
                           value: s.poleConfidence.displayLabel,
                           accent: colorFor(s.poleConfidence))
                if let path = s.polePotoPath,
                   let url = store.photoURL(relativePath: path),
                   let img = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: 160)
                        .clipped()
                        .cornerRadius(8)
                }
            }
        }
    }

    // MARK: Street Lights Section

    private var streetLightSection: some View {
        Section(header: streetLightHeader) {
            if let lights = workflow.session?.streetLights, !lights.isEmpty {
                ForEach(Array(lights.enumerated()), id: \.element.id) { idx, light in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("SL \(idx + 1)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            ConfidenceBadge(confidence: light.confidence)
                        }
                        Text(light.serialNumber)
                            .font(.system(.body, design: .monospaced))
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Text("No street lights captured yet")
                    .foregroundColor(.secondary)
            }
        }
    }

    private var streetLightHeader: some View {
        HStack {
            Text("Street Lights")
            Spacer()
            let count = workflow.session?.streetLights.count ?? 0
            Text("\(count) captured")
                .font(.caption)
                .foregroundColor(.blue)
        }
    }

    // MARK: Actions Section

    private var actionsSection: some View {
        Section {
            Button(action: { workflow.addAnotherStreetLight() }) {
                Label("Add Another Street Light", systemImage: "plus.circle")
            }

            Button(action: {
                workflow.saveSession()
            }) {
                Label(workflow.isSaved ? "Saved ✓" : "Save & Submit",
                      systemImage: workflow.isSaved ? "checkmark.seal.fill" : "square.and.arrow.up")
                    .foregroundColor(workflow.isSaved ? .green : .blue)
            }
            .disabled(workflow.isSaved || workflow.session?.streetLights.isEmpty == true)

            Button(role: .destructive, action: { workflow.reset() }) {
                Label("Start New Capture", systemImage: "arrow.counterclockwise")
            }
        }
    }

    // MARK: Helpers

    private func colorFor(_ confidence: Confidence) -> Color {
        switch confidence {
        case .high:   return .green
        case .low:    return .orange
        case .manual: return .blue
        }
    }
}

// MARK: - Labeled Row

private struct LabeledRow: View {
    let title: String
    let value: String
    var accent: Color = .primary

    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(accent)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Confidence Badge

struct ConfidenceBadge: View {
    let confidence: Confidence

    var body: some View {
        Text(label)
            .font(.caption2.bold())
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color)
            .clipShape(Capsule())
    }

    private var label: String {
        switch confidence {
        case .high:   return "AUTO"
        case .low:    return "VERIFIED"
        case .manual: return "MANUAL"
        }
    }

    private var color: Color {
        switch confidence {
        case .high:   return .green
        case .low:    return .orange
        case .manual: return .blue
        }
    }
}
