import SwiftUI
#if canImport(Translation)
import Translation
#endif

struct QuickRecognitionView: View {
    private enum ActionChoice: Hashable {
        case takePhoto
        case preset(RecognitionButtonSlot)
    }

    @EnvironmentObject private var settingsStore: SettingsStore
    @StateObject private var viewModel = QuickRecognitionViewModel()
    @State private var selectedActionIndex = 0

    private var quickPresetEntries: [(slot: RecognitionButtonSlot, preset: QuickQueryPreset)] {
        RecognitionButtonSlot.allCases
            .map { slot in (slot: slot, preset: settingsStore.quickPreset(for: slot)) }
            .sorted { lhs, rhs in
                let lhsIsProduct = lhs.preset.title.caseInsensitiveCompare("Product") == .orderedSame
                let rhsIsProduct = rhs.preset.title.caseInsensitiveCompare("Product") == .orderedSame
                if lhsIsProduct != rhsIsProduct {
                    return lhsIsProduct
                }
                return lhs.slot.rawValue < rhs.slot.rawValue
            }
    }

    private var actionChoices: [ActionChoice] {
        [.takePhoto] + quickPresetEntries.map { .preset($0.slot) }
    }

    private var selectedActionControlStyle: RecognitionActionControlStyle {
        RecognitionActionControlStyle(rawValue: settingsStore.quickActionControlStyle) ?? .onScreenButtons
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                CameraPreviewView(session: viewModel.camera.session)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 12) {
                    if settingsStore.quickMoondreamAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Add your Moondream API key in Settings > Quick Recognition.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    resultPanel

                    VStack(spacing: 12) {
                        controlPanel

                        Button {
                            if viewModel.isContinuousCapture {
                                viewModel.stopContinuousMode()
                            } else {
                                viewModel.startContinuousMode()
                            }
                        } label: {
                            Label(
                                viewModel.isContinuousCapture ? "Stop" : "Continuous",
                                systemImage: viewModel.isContinuousCapture ? "stop.circle" : "play.circle"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isProcessing && !viewModel.isContinuousCapture)
                        .accessibilitySortPriority(1)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding()

                translationView
            }
            .navigationTitle("Quick Recognition")
            .alert(
                "Quick Recognition Error",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                )
            ) {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        .onAppear {
            viewModel.bind(settings: settingsStore)
            viewModel.start()
            selectedActionIndex = min(selectedActionIndex, max(actionChoices.count - 1, 0))
        }
        .onDisappear {
            viewModel.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: .eyePalRequestQuickCapture)) { _ in
            viewModel.takePhoto()
        }
        .onChange(of: quickPresetEntries.map { $0.slot.rawValue }) { _ in
            selectedActionIndex = min(selectedActionIndex, max(actionChoices.count - 1, 0))
        }
    }

    @ViewBuilder
    private var resultPanel: some View {
        if viewModel.capturedPreview != nil || !viewModel.responseText.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if let capturedPreview = viewModel.capturedPreview {
                    Button {
                        viewModel.resendCapturedPhotoInFullResolution()
                    } label: {
                        Image(uiImage: capturedPreview)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Captured image, tap to resend in full resolution")
                    .disabled(viewModel.isProcessing)
                }

                if !viewModel.responseText.isEmpty {
                    TextEditor(text: .constant(viewModel.responseText))
                        .frame(minHeight: 120, maxHeight: 180)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityLabel("Quick recognition result")
                        .accessibilitySortPriority(2)
                }
            }
        }
    }

    @ViewBuilder
    private var controlPanel: some View {
        switch selectedActionControlStyle {
        case .onScreenButtons:
            quickButtonGrid
        case .singleAdjustableControl:
            adjustableActionButton
        }
    }

    private var quickButtonGrid: some View {
        VStack(spacing: 12) {
            Button {
                viewModel.takePhoto()
            } label: {
                Label(viewModel.isProcessing ? "Working..." : "Take Photo", systemImage: "camera")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isProcessing || viewModel.isContinuousCapture)
            .accessibilitySortPriority(5)

            HStack(spacing: 12) {
                ForEach(quickPresetEntries, id: \.slot) { entry in
                    quickPresetButton(
                        title: entry.preset.title,
                        systemImage: entry.preset.systemImageName
                    ) {
                        viewModel.takePresetPhoto(entry.preset)
                    }
                    .accessibilitySortPriority(
                        entry.preset.title.caseInsensitiveCompare("Product") == .orderedSame ? 4 : 3
                    )
                }
            }
        }
    }

    private var adjustableActionButton: some View {
        Button {
            performSelectedAction()
        } label: {
            Label(
                viewModel.isProcessing ? "Working..." : selectedActionTitle,
                systemImage: selectedActionSymbol
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.isProcessing || viewModel.isContinuousCapture)
        .accessibilityLabel("Capture action")
        .accessibilityValue(selectedActionTitle)
        .accessibilityHint("Swipe up or down to choose an action. Double tap to run the selected action.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                selectedActionIndex = min(selectedActionIndex + 1, actionChoices.count - 1)
            case .decrement:
                selectedActionIndex = max(selectedActionIndex - 1, 0)
            @unknown default:
                break
            }
        }
        .accessibilitySortPriority(5)
    }

    private var selectedAction: ActionChoice {
        guard !actionChoices.isEmpty else { return .takePhoto }
        let clampedIndex = min(max(selectedActionIndex, 0), actionChoices.count - 1)
        return actionChoices[clampedIndex]
    }

    private var selectedActionTitle: String {
        switch selectedAction {
        case .takePhoto:
            return "Take Photo"
        case .preset(let slot):
            return settingsStore.quickPreset(for: slot).title
        }
    }

    private var selectedActionSymbol: String {
        switch selectedAction {
        case .takePhoto:
            return "camera"
        case .preset(let slot):
            return settingsStore.quickPreset(for: slot).systemImageName
        }
    }

    private func performSelectedAction() {
        switch selectedAction {
        case .takePhoto:
            viewModel.takePhoto()
        case .preset(let slot):
            viewModel.takePresetPhoto(settingsStore.quickPreset(for: slot))
        }
    }

    @ViewBuilder
    private func quickPresetButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title3)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
        }
        .buttonStyle(.bordered)
        .disabled(viewModel.isProcessing || viewModel.isContinuousCapture)
    }

    @ViewBuilder
    private var translationView: some View {
        #if canImport(Translation)
        if #available(iOS 18.0, *), let request = viewModel.translationRequest {
            let configuration = TranslationSession.Configuration(
                source: Locale.Language(identifier: "en-US"),
                target: Locale.Language(identifier: request.targetLanguageIdentifier)
            )
            Color.clear
                .frame(width: 0, height: 0)
                .translationTask(configuration) { session in
                    do {
                        let response = try await session.translate(request.sourceText)
                        await MainActor.run {
                            guard viewModel.translationRequest?.id == request.id else { return }
                            viewModel.applyTranslatedResponse(
                                response.targetText,
                                fallbackText: request.sourceText
                            )
                        }
                    } catch {
                        await MainActor.run {
                            guard viewModel.translationRequest?.id == request.id else { return }
                            viewModel.applyTranslatedResponse(
                                request.sourceText,
                                fallbackText: request.sourceText
                            )
                        }
                    }
                }
        } else {
            EmptyView()
        }
        #else
        EmptyView()
        #endif
    }
}

#Preview {
    QuickRecognitionView()
        .environmentObject(SettingsStore())
}
