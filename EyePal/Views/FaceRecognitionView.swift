import SwiftUI

struct FaceRecognitionView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @StateObject private var viewModel = FaceRecognitionViewModel()
    @State private var suggestedName = ""

    var body: some View {
        NavigationStack {
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
                    } else {
                        Text(viewModel.statusText)
                            .font(.headline)
                    }

                    if let recognizedName = viewModel.recognizedName {
                        Text(recognizedName)
                            .font(.largeTitle.weight(.bold))
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding()
            }
            .navigationTitle(NSLocalizedString("feature.faceRecognition", comment: ""))
            .sheet(item: $viewModel.pendingSuggestion) { suggestion in
                NavigationStack {
                    Form {
                        if let jpegData = suggestion.jpegData, let uiImage = UIImage(data: jpegData) {
                            Section {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }

                        Section(NSLocalizedString("face.newFace", comment: "")) {
                            TextField(NSLocalizedString("face.personName", comment: ""), text: $suggestedName)
                                .textInputAutocapitalization(.words)
                                .submitLabel(.done)
                                .onSubmit {
                                    saveSuggestedFace()
                                }
                        }
                    }
                    .navigationTitle(NSLocalizedString("face.addPerson", comment: ""))
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(NSLocalizedString("face.notNow", comment: "")) {
                                suggestedName = ""
                                viewModel.dismissSuggestion()
                            }
                        }

                        ToolbarItem(placement: .confirmationAction) {
                            Button(NSLocalizedString("common.save", comment: "")) {
                                saveSuggestedFace()
                            }
                            .disabled(suggestedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
            .alert(NSLocalizedString("face.recognitionError", comment: ""), isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if (!$0) { viewModel.errorMessage = nil } }), actions: {
                Button(NSLocalizedString("common.ok", comment: "")) {
                    viewModel.errorMessage = nil
                }
            }, message: {
                Text(viewModel.errorMessage ?? "")
            })
        }
        .onAppear {
            viewModel.bind(settings: settingsStore)
            viewModel.start()
        }
        .onDisappear {
            viewModel.stop()
        }
    }

    private func saveSuggestedFace() {
        let trimmedName = suggestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        viewModel.saveSuggestion(named: trimmedName)
        suggestedName = ""
    }
}

#Preview {
    FaceRecognitionView()
        .environmentObject(SettingsStore())
}
