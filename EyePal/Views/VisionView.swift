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

private enum VisionSettingsDestination: String, Identifiable {
    case quickRecognition
    case detailsRecognition
    case readText
    case faces

    var id: String { rawValue }
}

struct VisionView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var openAIStore: OpenAISubscriptionStore
    @StateObject private var viewModel = VisionViewModel()
    @State private var pushedFeature: AppFeature?
    @State private var pushedSettings: VisionSettingsDestination?
    @State private var readTextAutoCapture = false
    @State private var showSavedFaces = false
    @State private var showNameDialog = false
    @State private var faceNameInput = ""

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
        .navigationDestination(item: $pushedSettings) { destination in
            settingsDestinationView(for: destination)
        }
        .alert(NSLocalizedString("common.error", comment: ""), isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if (!$0) { viewModel.errorMessage = nil } }), actions: {
            Button(NSLocalizedString("common.ok", comment: "")) {
                viewModel.errorMessage = nil
            }
        }, message: {
            Text(viewModel.errorMessage ?? "")
        })
        .alert(NSLocalizedString("face.addPerson", comment: ""), isPresented: $showNameDialog) {
            TextField(NSLocalizedString("face.personName", comment: ""), text: $faceNameInput)
            Button(NSLocalizedString("common.save", comment: "")) {
                let name = faceNameInput
                faceNameInput = ""
                viewModel.enrollment.saveWithTextName(name)
            }
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {
                faceNameInput = ""
            }
        } message: {
            Text(NSLocalizedString("face.nameMessage", comment: ""))
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
        .accessibilityAction(.magicTap) {
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
                return [
                    VisionMenuItem(title: viewModel.quickIsOn
                                   ? NSLocalizedString("vision.disableContinuous", comment: "")
                                   : NSLocalizedString("vision.enableContinuous", comment: ""),
                                   systemImage: viewModel.quickIsOn ? "pause.circle" : "play.circle", role: .standard) {
                        viewModel.toggleQuick()
                    },
                    VisionMenuItem(title: NSLocalizedString("vision.showFeaturePage", comment: ""), systemImage: "app.dashed", role: .standard) {
                        showFullScreen(to: .quickRecognition)
                    },
                    VisionMenuItem(title: NSLocalizedString("vision.settings", comment: ""), systemImage: "gearshape", role: .standard) {
                        pushedSettings = .quickRecognition
                    }
                ]
            }

            modeButton(NSLocalizedString("vision.details", comment: ""), systemImage: "sparkles", isOn: false) {
                viewModel.performDetails()
            } menu: {
                return [
                    VisionMenuItem(title: NSLocalizedString("vision.showFeaturePage", comment: ""), systemImage: "app.dashed", role: .standard) {
                        showFullScreen(to: .detailsRecognition)
                    },
                    VisionMenuItem(title: NSLocalizedString("vision.settings", comment: ""), systemImage: "gearshape", role: .standard) {
                        pushedSettings = .detailsRecognition
                    }
                ]
            }

            modeButton(NSLocalizedString("vision.text", comment: ""), systemImage: "text.viewfinder", isOn: viewModel.textIsOn) {
                viewModel.toggleText()
            } menu: {
                return [
                    VisionMenuItem(title: NSLocalizedString("read.takePicture", comment: ""), systemImage: "camera", role: .standard) {
                        showFullScreen(to: .readText, autoCapture: true)
                    },
                    VisionMenuItem(title: NSLocalizedString("vision.showFeaturePage", comment: ""), systemImage: "app.dashed", role: .standard) {
                        showFullScreen(to: .readText)
                    },
                    VisionMenuItem(title: NSLocalizedString("vision.settings", comment: ""), systemImage: "gearshape", role: .standard) {
                        pushedSettings = .readText
                    }
                ]
            }

            modeButton(NSLocalizedString("vision.faces", comment: ""), systemImage: "face.smiling", isOn: viewModel.facesIsOn) {
                viewModel.toggleFaces()
            } menu: {
                return [
                    VisionMenuItem(title: NSLocalizedString("vision.showFeaturePage", comment: ""), systemImage: "app.dashed", role: .standard) {
                        showFullScreen(to: .faces)
                    },
                    VisionMenuItem(title: NSLocalizedString("vision.savedFaces", comment: ""), systemImage: "person.text.rectangle", role: .standard) {
                        showSavedFaces = true
                    },
                    VisionMenuItem(title: NSLocalizedString("vision.settings", comment: ""), systemImage: "gearshape", role: .standard) {
                        pushedSettings = .faces
                    }
                ]
            }
        }
    }

    private func showFullScreen(to feature: AppFeature, autoCapture: Bool = false) {
        readTextAutoCapture = autoCapture
        pushedFeature = feature
    }

    @ViewBuilder
    private func settingsDestinationView(for destination: VisionSettingsDestination) -> some View {
        switch destination {
        case .quickRecognition:
            QuickRecognitionSettingsView()
                .environmentObject(settingsStore)
        case .detailsRecognition:
            DetailsDescriptionSettingsView()
                .environmentObject(settingsStore)
                .environmentObject(openAIStore)
        case .readText:
            ReadTextRecognitionSettingsView()
                .environmentObject(settingsStore)
        case .faces:
            FaceRecognitionSettingsView()
                .environmentObject(settingsStore)
        }
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
                            : "")
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
            if case .unauthorized = viewModel.cameraState {
                Text(NSLocalizedString("vision.cameraUnauthorized", comment: ""))
                    .font(.footnote)
                    .foregroundStyle(.red)
                Button(NSLocalizedString("settings.openSystemSettings", comment: "")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.footnote.weight(.semibold))
            } else if case .failed(let message) = viewModel.cameraState {
                Text(NSLocalizedString("vision.cameraFailed", comment: "") + " \(message)")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

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
            .contextMenu {
                Button {
                    faceNameInput = ""
                    showNameDialog = true
                } label: {
                    Label(NSLocalizedString("face.nameWithText", comment: ""), systemImage: "text.cursor")
                }
            }
            .accessibilityAction(named: Text(NSLocalizedString("face.nameWithText", comment: ""))) {
                faceNameInput = ""
                showNameDialog = true
            }
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
            ReadTextView(autoCaptureOnAppear: readTextAutoCapture)
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