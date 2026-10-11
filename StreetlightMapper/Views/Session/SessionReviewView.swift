import SwiftUI

// MARK: - Session Review Screen
// Shows the Pole ID, all captured street lights and their confidence status.
// Technicians can correct values, remove lights, add more, and save.
// Used both at the end of a new capture and when editing a saved one.

struct SessionReviewView: View {

    @EnvironmentObject private var workflow: WorkflowViewModel
    @EnvironmentObject private var store: SessionStore

    private enum EditTarget: Identifiable {
        case pole
        case light(UUID)
        var id: String {
            switch self {
            case .pole: return "pole"
            case .light(let id): return id.uuidString
            }
        }
    }

    @State private var editTarget: EditTarget?
    @State private var confirmClose = false

    private var hasUnsavedEdits: Bool {
        guard workflow.isEditingExisting, let current = workflow.session,
              let original = store.sessions.first(where: { $0.id == current.id }) else { return false }
        return !workflow.isSaved && original != current
    }

    var body: some View {
        NavigationView {
            List {
                if workflow.isSaved { savedBanner }
                poleSection
                streetLightSection
                actionsSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle(workflow.isEditingExisting ? "Edit Capture" : "Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(workflow.isSaved ? "Done" : "Close") { close() }
                }
            }
            .sheet(item: $editTarget) { target in
                editSheet(for: target)
            }
            .confirmationDialog("Discard your changes?",
                                isPresented: $confirmClose,
                                titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { workflow.exit() }
                Button("Keep editing", role: .cancel) {}
            }
        }
    }

    private func close() {
        if hasUnsavedEdits { confirmClose = true } else { workflow.exit() }
    }

    // MARK: Saved banner

    private var savedBanner: some View {
        Section {
            Label("Saved. It will upload as soon as you are online.", systemImage: "checkmark.seal.fill")
                .foregroundColor(.green)
        }
    }

    // MARK: Pole Section

    private var poleSection: some View {
        Section(header: Text("Pole ID")) {
            if let s = workflow.session {
                Button { editTarget = .pole } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(s.poleID)
                                .font(.system(.title3, design: .monospaced).bold())
                                .foregroundColor(.primary)
                            ConfidenceBadge(confidence: s.poleConfidence)
                        }
                        Spacer()
                        if !workflow.isSaved {
                            Image(systemName: "pencil").foregroundColor(.blue)
                        }
                    }
                }
                .disabled(workflow.isSaved)

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
        Section(header: streetLightHeader,
                footer: Text(workflow.isSaved ? "" : "Tap a serial number to correct it. Swipe left to remove a light.")) {
            if let lights = workflow.session?.streetLights, !lights.isEmpty {
                ForEach(Array(lights.enumerated()), id: \.element.id) { idx, light in
                    Button { editTarget = .light(light.id) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Light \(idx + 1)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(light.serialNumber)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.primary)
                            }
                            Spacer()
                            ConfidenceBadge(confidence: light.confidence)
                            if !workflow.isSaved {
                                Image(systemName: "pencil").foregroundColor(.blue)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .disabled(workflow.isSaved)
                }
                .onDelete(perform: workflow.isSaved ? nil : { workflow.deleteStreetLights(at: $0) })
            } else {
                Text("No street lights yet. Add at least one to save.")
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
            if workflow.isSaved {
                Button { workflow.startNew() } label: {
                    Label("Capture Another Pole", systemImage: "camera.viewfinder")
                }
            } else {
                Button { workflow.addAnotherStreetLight() } label: {
                    Label("Add a Street Light", systemImage: "plus.circle")
                }

                Button { workflow.saveSession() } label: {
                    Label(workflow.isEditingExisting ? "Save Changes" : "Save",
                          systemImage: "square.and.arrow.down")
                        .bold()
                }
                .disabled(workflow.session?.streetLights.isEmpty != false)
            }
        }
    }

    // MARK: Edit sheet

    @ViewBuilder
    private func editSheet(for target: EditTarget) -> some View {
        switch target {
        case .pole:
            ValueEditSheet(
                title: "Edit Pole ID",
                hint: "5 to 10 digits",
                initial: workflow.session?.poleID ?? "",
                isNumeric: true,
                validate: PoleIDExtractor.isValid
            ) { workflow.updatePoleID($0) }
        case .light(let id):
            ValueEditSheet(
                title: "Edit Serial Number",
                hint: "Serial number",
                initial: workflow.session?.streetLights.first(where: { $0.id == id })?.serialNumber ?? "",
                isNumeric: false,
                validate: { !$0.isEmpty }
            ) { workflow.updateSerial(lightID: id, value: $0) }
        }
    }
}

// MARK: - Edit sheet

private struct ValueEditSheet: View {
    let title: String
    let hint: String
    let initial: String
    let isNumeric: Bool
    let validate: (String) -> Bool
    let onSave: (String) -> Void

    @Environment(\.presentationMode) private var presentation
    @State private var text = ""

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationView {
            Form {
                Section(footer: Text("Corrected values are marked as MANUAL.")) {
                    TextField(hint, text: $text)
                        .keyboardType(isNumeric ? .numberPad : .default)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                }
                if !trimmed.isEmpty && !validate(trimmed) {
                    Text("Doesn't look right: \(hint.lowercased()).")
                        .font(.footnote)
                        .foregroundColor(.orange)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { presentation.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave(trimmed)
                        presentation.wrappedValue.dismiss()
                    }
                    .disabled(!validate(trimmed))
                }
            }
            .onAppear { text = initial }
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
