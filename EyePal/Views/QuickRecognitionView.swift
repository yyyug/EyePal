import AVFoundation
import Speech
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
    @State private var showPromptEditor = false

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
        ZStack(alignment: .bottom) {
                CameraPreviewView(session: viewModel.camera.session)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 12) {
                    if viewModel.gemmaNeedsModelDownload {
                    Text(NSLocalizedString("quick.gemmaNotDownloaded", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button(NSLocalizedString("gemma.action.download", comment: "")) {
                        viewModel.downloadSelectedGemmaModel()
                    }
                    .font(.subheadline.weight(.semibold))
                } else if QuickModelProvider(rawValue: settingsStore.quickModelProvider) == .moondream,
                          settingsStore.quickMoondreamAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(NSLocalizedString("quick.apiKeyPrompt", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Link(NSLocalizedString("quick.signupLink", comment: ""), destination: URL(string: "https://moondream.ai/")!)
                        .font(.subheadline.weight(.semibold))
                } else if let appleMessage = viewModel.appleUnavailableMessage {
                    Text(appleMessage)
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
                                viewModel.isContinuousCapture ? NSLocalizedString("common.stop", comment: "") : NSLocalizedString("common.continuous", comment: ""),
                                systemImage: viewModel.isContinuousCapture ? "stop.circle" : "play.circle"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isProcessing && !viewModel.isContinuousCapture)
                        .contextMenu {
                            Button {
                                showPromptEditor = true
                            } label: {
                                Label(NSLocalizedString("quick.editPrompt", comment: ""), systemImage: "text.cursor")
                            }
                        }
                        .accessibilityAction(named: Text(NSLocalizedString("quick.editPrompt", comment: ""))) {
                            showPromptEditor = true
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding()

                translationView
            }
            .navigationTitle(NSLocalizedString("feature.quickRecognition", comment: ""))
            .alert(
                NSLocalizedString("quick.recognitionError", comment: ""),
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                )
            ) {
                Button(NSLocalizedString("common.ok", comment: "")) {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .sheet(isPresented: $showPromptEditor) {
                QuickPromptEditorView(initialText: settingsStore.quickTakePhotoCustomPrompt) { prompt in
                    settingsStore.quickTakePhotoCustomPrompt = prompt
                    if !viewModel.isContinuousCapture {
                        viewModel.startContinuousMode()
                    }
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
                    .accessibilityLabel(NSLocalizedString("common.capturedImageHint", comment: ""))
                    .disabled(viewModel.isProcessing)
                }

                if !viewModel.responseText.isEmpty {
                    ScrollView {
                        Text(viewModel.responseText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(minHeight: 120, maxHeight: 180)
                    .scrollContentBackground(.hidden)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityLabel(NSLocalizedString("quick.resultLabel", comment: ""))

                    HStack(spacing: 8) {
                        TextField(
                            NSLocalizedString("details.followUpQuestion", comment: ""),
                            text: $viewModel.followUpQuestion
                        )
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.send)
                        .onSubmit {
                            viewModel.submitFollowUp()
                        }
                        .accessibilityLabel(NSLocalizedString("details.followUpQuestion", comment: ""))

                        Button(NSLocalizedString("common.send", comment: "")) {
                            viewModel.submitFollowUp()
                        }
                        .buttonStyle(.bordered)
                        .disabled(
                            viewModel.isProcessing
                                || viewModel.followUpQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                    }
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
                Label(viewModel.isProcessing ? NSLocalizedString("common.working", comment: "") : NSLocalizedString("common.takePhoto", comment: ""), systemImage: "camera")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isProcessing || viewModel.isContinuousCapture)

            HStack(spacing: 12) {
                ForEach(quickPresetEntries, id: \.slot) { entry in
                    quickPresetButton(
                        title: entry.preset.localizedTitle,
                        systemImage: entry.preset.systemImageName
                    ) {
                        viewModel.takePresetPhoto(entry.preset)
                    }

                }
            }
        }
    }

    private var adjustableActionButton: some View {
        Button {
            performSelectedAction()
        } label: {
            Label(
                viewModel.isProcessing ? NSLocalizedString("common.working", comment: "") : selectedActionTitle,
                systemImage: selectedActionSymbol
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.isProcessing || viewModel.isContinuousCapture)
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
    }

    private var selectedAction: ActionChoice {
        guard !actionChoices.isEmpty else { return .takePhoto }
        let clampedIndex = min(max(selectedActionIndex, 0), actionChoices.count - 1)
        return actionChoices[clampedIndex]
    }

    private var selectedActionTitle: String {
        switch selectedAction {
        case .takePhoto:
            return NSLocalizedString("common.takePhoto", comment: "")
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

// MARK: - Prompt editor

/// A page to type or dictate the prompt that replaces the default description
/// prompt. Send starts the continuous capture; the microphone button runs
/// on-device dictation that stops automatically after a pause.
struct QuickPromptEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var dictation = DictationController()
    @State private var text: String
    let onSend: (String) -> Void

    init(initialText: String, onSend: @escaping (String) -> Void) {
        _text = State(initialValue: initialText)
        self.onSend = onSend
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 8) {
                        TextField(NSLocalizedString("quick.promptPlaceholder", comment: ""), text: $text, axis: .vertical)
                            .lineLimit(1...4)
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.send)
                            .onSubmit { send() }

                        Button {
                            send()
                        } label: {
                            Image(systemName: "paperplane.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel(NSLocalizedString("common.send", comment: ""))

                        Button {
                            dictation.toggle()
                        } label: {
                            Image(systemName: dictation.isRecording ? "mic.fill" : "mic")
                        }
                        .buttonStyle(.bordered)
                        .tint(dictation.isRecording ? .red : .accentColor)
                        .accessibilityLabel(NSLocalizedString(dictation.isRecording ? "quick.dictation.stop" : "quick.dictation.start", comment: ""))
                    }
                } footer: {
                    Text(NSLocalizedString("quick.editPromptMessage", comment: ""))
                }

                if let error = dictation.errorMessage {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("quick.editPrompt", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("common.cancel", comment: "")) {
                        dismiss()
                    }
                }
            }
        }
        .onChange(of: dictation.transcript) { newValue in
            guard !newValue.isEmpty else { return }
            text = newValue
        }
        .accessibilityAction(.magicTap) {
            dictation.toggle()
        }
        .onDisappear {
            dictation.stop()
        }
    }

    private func send() {
        onSend(text.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }
}

// MARK: - Dictation

/// On-device speech recognition that stops itself after a short silence.
@MainActor
final class DictationController: ObservableObject {
    @Published private(set) var isRecording = false
    @Published var transcript = ""
    @Published var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var hasTap = false
    private var lastVoiceDate = Date()
    private let silenceInterval: TimeInterval = 1.8
    private let voiceThreshold: Float = 0.02

    func toggle() {
        if isRecording { stop() } else { start() }
    }

    func start() {
        guard !isRecording else { return }
        errorMessage = nil
        transcript = ""

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                guard status == .authorized else {
                    self.errorMessage = NSLocalizedString("quick.dictation.noPermission", comment: "")
                    return
                }
                self.beginSession()
            }
        }
    }

    func stop() {
        silenceTimer?.invalidate()
        silenceTimer = nil

        if hasTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasTap = false
        }
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func beginSession() {
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current), recognizer.isAvailable else {
            errorMessage = NSLocalizedString("quick.dictation.unavailable", comment: "")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.channelCount > 0 else {
            errorMessage = NSLocalizedString("quick.dictation.unavailable", comment: "")
            return
        }
        if hasTap {
            inputNode.removeTap(onBus: 0)
            hasTap = false
        }
        let voiceThreshold = self.voiceThreshold
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            if DictationController.rmsLevel(buffer) > voiceThreshold {
                Task { @MainActor in self?.lastVoiceDate = Date() }
            }
        }
        hasTap = true

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            errorMessage = error.localizedDescription
            stop()
            return
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    self.lastVoiceDate = Date()
                }
                if error != nil || (result?.isFinal ?? false) {
                    self.stop()
                }
            }
        }

        isRecording = true
        lastVoiceDate = Date()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForSilence()
            }
        }
    }

    private func checkForSilence() {
        guard isRecording else { return }
        if Date().timeIntervalSince(lastVoiceDate) >= silenceInterval {
            stop()
        }
    }

    private static func rmsLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<frames {
            sum += channel[index] * channel[index]
        }
        return sqrt(sum / Float(frames))
    }
}
