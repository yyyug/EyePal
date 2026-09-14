import SwiftUI

struct FaceRecognitionView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @StateObject private var viewModel = FaceRecognitionViewModel()

    var body: some View {
        ZStack(alignment: .bottom) {
            CameraPreviewView(session: viewModel.camera.session)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                if case .unauthorized = viewModel.cameraState {
                    Text(NSLocalizedString("face.cameraUnauthorized", comment: ""))
                        .font(.headline)
                        .foregroundStyle(.red)
                } else if case .failed(let msg) = viewModel.cameraState {
                    Text(NSLocalizedString("face.cameraFailed", comment: "") + " \(msg)")
                        .font(.headline)
                        .foregroundStyle(.red)
                } else if let sampleProgress = viewModel.sampleProgress {
                    Text(sampleProgress)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if viewModel.enrollment.state != .idle {
                    Text(viewModel.enrollment.statusText)
                        .font(.headline)
                } else {
                    Text(viewModel.statusText)
                        .font(.headline)
                }

                if let recognizedName = viewModel.recognizedName {
                    Text(recognizedName)
                        .font(.largeTitle.weight(.bold))
                }

                enrollmentControls
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding()
        }
        .navigationTitle(NSLocalizedString("feature.faceRecognition", comment: ""))
        .alert(NSLocalizedString("face.recognitionError", comment: ""), isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if (!$0) { viewModel.errorMessage = nil } }), actions: {
            Button(NSLocalizedString("common.ok", comment: "")) {
                viewModel.errorMessage = nil
            }
        }, message: {
            Text(viewModel.errorMessage ?? "")
        })
        .onAppear {
            viewModel.bind(settings: settingsStore)
            viewModel.start()
        }
        .onDisappear {
            viewModel.stop()
        }
        .accessibilityAction(named: .magicTap) {
            viewModel.enrollment.trigger()
        }
    }

    @ViewBuilder
    private var enrollmentControls: some View {
        switch viewModel.enrollment.state {
        case .idle:
            Button(action: { viewModel.enrollment.trigger() }) {
                Label(viewModel.enrollment.engageLabel, systemImage: "waveform.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(true)
            .accessibilityLabel(viewModel.enrollment.engageLabel)
            .accessibilityHint(NSLocalizedString("face.saveDisabledHint", comment: ""))
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
}

#Preview {
    FaceRecognitionView()
        .environmentObject(SettingsStore())
}