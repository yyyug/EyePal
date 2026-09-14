import SwiftUI

private struct VisionMenuItem: Identifiable {
    enum Role: Equatable {
        case standard
        case cancel
    }

    let id = UUID()
    let title: String
    let systemImage: String
    let role: Role
    let action: () -> Void
}

struct VisionView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var openAIStore: OpenAISubscriptionStore
    @StateObject private var viewModel = VisionViewModel()
    @State private var pushedFeature: AppFeature?
    @State private var showSettings = false
    @State private var showSavedFaces = false

    var body: some View {
        ZStack(alignment: .bottom) {
            CameraPreviewView(session: viewModel.camera.session)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                modeButtons

                resultBox
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(NSLocalizedString("tab.vision", comment: ""))
        .navigationDestination(item: $pushedFeature) { feature in
            destinationView(for: feature)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    SettingsView()
                        .environmentObject(settingsStore)
                        .environmentObject(openAIStore)
                } label: {
                    Label(NSLocalizedString("tab.settings", comment: ""), systemImage: "gearshape")
                }
            }
        }
        .alert(NSLocalizedString("common.error", comment: ""), isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if (!$0) { viewModel.errorMessage = nil } }), actions: {
            Button(NSLocalizedString("common.ok", comment: "")) {
                viewModel.errorMessage = nil
            }
        }, message: {
            Text(viewModel.errorMessage ?? "")
        })
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
                    .environmentObject(settingsStore)
                    .environmentObject(openAIStore)
            }
        }
        .sheet(isPresented: $showSavedFaces) {
            NavigationStack {
                SavedFacesView()
                    .environmentObject(settingsStore)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eyePalRequestQuickCapture)) { _ in
            viewModel.performQuick()
        }
        .onReceive(NotificationCenter.default.publisher(for: .eyePalRequestDetailsCapture)) { _ in
            viewModel.performDetails()
        }
        .onAppear {
            viewModel.bind(settings: settingsStore)
            viewModel.bind(openAIStore: openAIStore)
            viewModel.start()
        }
        .onDisappear {
            viewModel.stop()
        }
        .accessibilityAction(named: .magicTap) {
            viewModel.enrollment.trigger()
        }
    }

    private var modeButtons: some View {
        HStack(spacing: 10) {
            modeButton(NSLocalizedString("vision.quick", comment: ""), systemImage: "bolt", isOn: viewModel.quickIsOn) {
                if viewModel.quickIsOn {
                    viewModel.toggleQuick()
                } else {
                    viewModel.performQuick()
                }
            } menu: {
                VisionMenuItem(title: viewModel.quickIsOn
                               ? NSLocalizedString("vision.disableContinuous", comment: "")
                               : NSLocalizedString("vision.enableContinuous", comment: ""),
                               systemImage: viewModel.quickIsOn ? "pause.circle" : "play.circle", role: .standard) {
                    viewModel.toggleQuick()
                }
                VisionMenuItem(title: NSLocalizedString("vision.showFeaturePage", comment: ""), systemImage: "app.dashed", role: .standard) {
                    showFullScreen(to: .quickRecognition)
                }
                settingsMenuItem(for: .quickRecognition)
            }

            modeButton(NSLocalizedString("vision.details", comment: ""), systemImage: "sparkles", isOn: viewModel.isDetailsProcessing) {
                viewModel.performDetails()
            } menu: {
                VisionMenuItem(title: NSLocalizedString("vision.showFeaturePage", comment: ""), systemImage: "app.dashed", role: .standard) {
                    showFullScreen(to: .detailsRecognition)
                }
                settingsMenuItem(for: .detailsRecognition)
            }

            modeButton(NSLocalizedString("vision.text", comment: ""), systemImage: "text.viewfinder", isOn: viewModel.textIsOn) {
                viewModel.toggleText()
            } menu: {
                VisionMenuItem(title: viewModel.textIsOn
                               ? NSLocalizedString("vision.disableContinuous", comment: "")
                               : NSLocalizedString("vision.enableContinuous", comment: ""),
                               systemImage: viewModel.textIsOn ? "pause.circle" : "play.circle", role: .standard) {
                    viewModel.toggleText()
                }
                VisionMenuItem(title: NSLocalizedString("vision.showFeaturePage", comment: ""), systemImage: "app.dashed", role: .standard) {
                    showFullScreen(to: .readText)
                }
                settingsMenuItem(for: .readText)
            }

            modeButton(NSLocalizedString("vision.faces", comment: ""), systemImage: "face.smiling", isOn: viewModel.facesIsOn) {
                viewModel.toggleFaces()
            } menu: {
                VisionMenuItem(title: viewModel.facesIsOn
                               ? NSLocalizedString("vision.disableContinuous", comment: "")
                               : NSLocalizedString("vision.enableContinuous", comment: ""),
                               systemImage: viewModel.facesIsOn ? "pause.circle" : "play.circle", role: .standard) {
                    viewModel.toggleFaces()
                }
                VisionMenuItem(title: NSLocalizedString("vision.showFeaturePage", comment: ""), systemImage: "app.dashed", role: .standard) {
                    showFullScreen(to: .faces)
                }
                VisionMenuItem(title: NSLocalizedString("vision.savedFaces", comment: ""), systemImage: "person.text.rectangle", role: .standard) {
                    showSavedFaces = true
                }
                settingsMenuItem(for: .faces)
            }
        }
    }

    @State private var showSettings = false

    private func settingsMenuItem(for feature: AppFeature) -> VisionMenuItem {
        VisionMenuItem(title: NSLocalizedString("vision.settings", comment: ""), systemImage: "gearshape", role: .standard) {
            showSettings = true
        }
    }

    private func showFullScreen(to feature: AppFeature) {
        pushedFeature = feature
    }

    private func modeButton(
        _ label: String,
        systemImage: String,
        isOn: Bool,
        primary: @escaping () -> Void,
        menu: () -> [VisionMenuItem]
    ) -> some View {
        let items = menu()

        return Button(action: primary) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title2)
                Text(label)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                isOn ? Color.accentColor.opacity(0.28) : Color.clear,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isOn ? Color.accentColor : Color.white.opacity(0.65), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            ForEach(items) { item in
                Button(role: item.role == .cancel ? .destructive : nil) {
                    item.action()
                } label: {
                    Label(item.title, systemImage: item.systemImage)
                }
            }
        }
        .accessibilityLabel(label)
        .accessibilityValue(isOn
                            ? NSLocalizedString("vision.selectedOn", comment: "")
                            : NSLocalizedString("vision.selectedOff", comment: ""))
        .accessibilityHint(NSLocalizedString("vision.buttonHint", comment: ""))
        .accessibilityActions {
            ForEach(items) { item in
                Button(item.title) {
                    item.action()
                }
            }
        }
    }

    @ViewBuilder
    private var resultBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let lastResult = viewModel.lastResult {
                Text(lastResult)
                    .font(.headline)
                    .textSelection(.enabled)
            }

            enrollmentControls

            Text(viewModel.statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private var enrollmentControls: some View {
        switch viewModel.enrollment.state {
        case .idle:
            EmptyView()
        case .pending:
            Button(action: { viewModel.enrollment.trigger() }) {
                Label(viewModel.enrollment.engageLabel, systemImage: "waveform.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.enrollment.isSaveButtonEnabled)
            .accessibilityHint(NSLocalizedString("face.saveHint", comment: ""))
        case .recording:
            Button(action: { viewModel.enrollment.trigger() }) {
                Label(viewModel.enrollment.engageLabel, systemImage: "stop.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.enrollment.isSaveButtonEnabled)

            Button(role: .destructive, action: { viewModel.enrollment.cancel() }) {
                Label(NSLocalizedString("common.cancel", comment: ""), systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        case .recorded:
            Button(action: { viewModel.enrollment.trigger() }) {
                Label(viewModel.enrollment.engageLabel, systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.enrollment.isSaveButtonEnabled)

            Button(action: { viewModel.enrollment.reRecord() }) {
                Label(NSLocalizedString("face.reRecord", comment: ""), systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(role: .destructive, action: { viewModel.enrollment.cancel() }) {
                Label(NSLocalizedString("common.cancel", comment: ""), systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private func destinationView(for feature: AppFeature) -> some View {
        switch feature {
        case .floorDetection:
            EmptyView()
        case .chat:
            EmptyView()
        case .quickRecognition:
            QuickRecognitionView()
        case .detailsRecognition:
            DetailsDescriptionView()
        case .readText:
            ReadTextView()
        case .faces:
            FaceRecognitionView()
        case .lyricPrompter:
            LyricPrompterView()
                .environmentObject(openAIStore)
        }
    }
}

#Preview {
    VisionView()
        .environmentObject(SettingsStore())
        .environmentObject(OpenAISubscriptionStore())
}