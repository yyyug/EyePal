import AVFoundation
import Combine
import CoreImage
import Foundation
import UIKit
import Vision

@MainActor
final class VisionViewModel: ObservableObject {
    @Published var statusText = NSLocalizedString("vision.statusIdle", comment: "")
    @Published var lastResult: String?
    @Published var quickIsOn = false
    @Published var textIsOn = false
    @Published var facesIsOn = false
    @Published var isQuickProcessing = false
    @Published var isDetailsProcessing = false
    @Published var cameraState: CameraPipeline.State = .idle
    @Published var errorMessage: String?

    let camera = CameraPipeline()
    let enrollment: FaceEnrollmentCoordinator

    private let quickService = QuickRecognitionService()
    private let gemmaModelManager = GemmaModelManager.shared
    private lazy var gemmaService = GemmaTextRecognitionService(modelManager: gemmaModelManager)
    private let detailsDescriptionService = OpenAIDetailsDescriptionService()
    private let textRecognitionService = TextRecognitionService()
    private let paddleTextRecognitionService = PaddleTextRecognitionService()
    private let faceRecognitionService = FaceRecognitionService()
    private let faceStore = FaceStore()
    private let facePlayer = FaceAudioPlayer()
    private let announcer = AccessibilityAnnouncementCenter()
    private weak var settingsStore: SettingsStore?
    private var openAIStore: OpenAISubscriptionStore?
    private var cancellables = Set<AnyCancellable>()

    private var continuousQuickTask: Task<Void, Never>?
    private var frameCounter = 0
    private var isFaceProcessing = false
    private var isTextProcessing = false
    private var lastSpokenFaceID: UUID?
    private let faceRouteFrame = 0
    private let textRouteFrame = 1

    private static let ciContext = CIContext()
    private let stabilityInterval: TimeInterval = 0.6
    private let minimumStableRepeats = 2
    private let meaningfulChangeThreshold = 0.85
    private var pendingAnnouncementText = ""
    private var pendingAnnouncementSpokenText = ""
    private var pendingAnnouncementLanguage = "Unknown"
    private var pendingAnnouncementDate = Date.distantPast
    private var pendingAnnouncementCount = 0
    private var lastSpokenNormalizedText = ""

    init() {
        enrollment = FaceEnrollmentCoordinator(recognitionService: faceRecognitionService)
        enrollment.onAnnounce = { [weak self] text in
            self?.announcer.announce(text, minimumInterval: 0)
            self?.lastResult = text
        }
        camera.onSampleBuffer = { [weak self] sampleBuffer in
            self?.handle(sampleBuffer: sampleBuffer)
        }
        camera.$state.sink { [weak self] newState in
            Task { @MainActor in
                self?.cameraState = newState
            }
        }.store(in: &cancellables)
    }

    func bind(settings: SettingsStore) {
        settingsStore = settings
        faceRecognitionService.recognitionThreshold = max(Float(settings.faceMatchThreshold), 0.30)
        faceRecognitionService.minimumTopMatchMargin = max(Float(settings.faceMatchMargin), 0.01)
        faceRecognitionService.onLog = { [weak self] msg in
            self?.settingsStore?.appendFaceLog(msg)
        }
    }

    func bind(openAIStore: OpenAISubscriptionStore) {
        self.openAIStore = openAIStore
    }

    func start() {
        // Start the camera first so a slow profile load can never leave the
        // Vision tab without frames.
        statusText = NSLocalizedString("vision.statusStarting", comment: "")
        camera.start()
        Task {
            do {
                _ = try await faceRecognitionService.loadProfiles()
                faceRecognitionService.loadEmbeddingEngine()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func stop() {
        enrollment.shutDown()
        facePlayer.stop()
        stopContinuousQuick()
        camera.stop()
    }

    func resume() {
        enrollment.reset()
        facePlayer.stop()
        stopContinuousQuick()
        statusText = NSLocalizedString("vision.statusStarting", comment: "")
        camera.start()
        Task {
            do {
                _ = try await faceRecognitionService.loadProfiles()
            } catch { }
        }
    }

    // MARK: - Quick recognition

    func performQuick() {
        guard !isQuickProcessing else { return }
        Task { await captureQuick() }
    }

    func toggleQuick() {
        quickIsOn.toggle()
        if quickIsOn {
            startContinuousQuick()
        } else {
            stopContinuousQuick()
        }
    }

    private func startContinuousQuick() {
        guard continuousQuickTask == nil else { return }
        let interval = QuickContinuousCaptureInterval(
            rawValue: settingsStore?.quickContinuousCaptureInterval ?? QuickContinuousCaptureInterval.defaultInterval.rawValue
        ) ?? .defaultInterval
        statusText = NSLocalizedString("vision.quickContinuousOn", comment: "")
        continuousQuickTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.captureQuick()
                try? await Task.sleep(nanoseconds: UInt64(interval.timeInterval * 1_000_000_000))
            }
        }
    }

    private func stopContinuousQuick() {
        continuousQuickTask?.cancel()
        continuousQuickTask = nil
    }

    /// Called when a capture finds no camera frame. Kicks the session to
    /// recover from an interruption instead of leaving a dead-end message,
    /// and surfaces the blocked-permission case honestly.
    private func noteMissingFrame() {
        if cameraState == .unauthorized {
            statusText = NSLocalizedString("vision.cameraUnauthorized", comment: "")
        } else {
            camera.start()
            statusText = NSLocalizedString("vision.statusStarting", comment: "")
        }
    }

    private func captureQuick() async {
        guard let settingsStore else {
            errorMessage = "Quick Recognition settings are unavailable."
            return
        }
        guard let image = camera.currentFrameImage() else {
            noteMissingFrame()
            return
        }

        let provider = QuickModelProvider(rawValue: settingsStore.quickModelProvider) ?? .gemma
        let selectedKind = GemmaModelKind(rawValue: settingsStore.quickGemmaModelKind) ?? .e2b
        let useGemmaOffline = provider == .gemma && gemmaService.canRun(selectedKind: selectedKind)
        let apiKey = settingsStore.quickMoondreamAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !useGemmaOffline, apiKey.isEmpty {
            errorMessage = QuickRecognitionError.missingAPIKey.localizedDescription
            return
        }

        isQuickProcessing = true
        do {
            let response: String
            if useGemmaOffline {
                response = try await gemmaService.generateCaption(
                    image: image,
                    length: .short,
                    kind: selectedKind
                )
            } else {
                let imageDataURL = try quickService.prepareImageDataURL(
                    from: image,
                    maximumDimension: 320,
                    compressionQuality: 0.5
                )
                response = try await quickService.generateCaption(
                    imageDataURL: imageDataURL,
                    length: .short,
                    apiKey: apiKey
                )
            }
            let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                presentResult(trimmed, statusKey: quickIsOn ? "vision.quickContinuousOn" : "vision.quickReady")
            } else {
                statusText = NSLocalizedString("vision.quickNoResult", comment: "")
            }
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
            statusText = NSLocalizedString("vision.quickFailed", comment: "")
        }
        isQuickProcessing = false
    }

    // MARK: - Details description

    func performDetails() {
        guard !isDetailsProcessing else { return }
        guard let openAIStore else {
            errorMessage = OpenAISubscriptionError.notSignedIn.localizedDescription
            presentResult(NSLocalizedString("vision.detailsSignInRequired", comment: ""), statusKey: "vision.detailsReady")
            return
        }
        guard openAIStore.isSignedIn else {
            errorMessage = OpenAISubscriptionError.notSignedIn.localizedDescription
            presentResult(NSLocalizedString("vision.detailsSignInRequired", comment: ""), statusKey: "vision.detailsReady")
            return
        }
        guard let image = camera.currentFrameImage() else {
            noteMissingFrame()
            return
        }

        isDetailsProcessing = true
        statusText = NSLocalizedString("vision.detailsAnalyzing", comment: "")
        let prompt = "For a blind user, if visible text is present, read it exactly. If no text is visible, do not mention text detection. Then describe people, objects, layout, and orientation cues. Be concise and specific. Do not use markdown or double asterisks."
        Task {
            do {
                let preparedImageData = try detailsDescriptionService.prepareImageData(
                    from: image,
                    maximumDimension: 640,
                    compressionQuality: 0.72
                )
                let conversation = [DetailsDescriptionTurn(role: .user, text: prompt)]
                let response = try await detailsDescriptionService.generateResponse(
                    imageData: preparedImageData,
                    conversation: conversation,
                    store: openAIStore
                )
                presentResult(response, statusKey: "vision.detailsReady")
            } catch {
                errorMessage = error.localizedDescription
                statusText = NSLocalizedString("vision.detailsFailed", comment: "")
            }
            isDetailsProcessing = false
        }
    }

    // MARK: - Live modes and frame routing

    func toggleText() {
        textIsOn.toggle()
        if !textIsOn {
            cancelTextStability()
        }
        updateStatusText()
    }

    func toggleFaces() {
        facesIsOn.toggle()
        if !facesIsOn {
            enrollment.reset()
            lastSpokenFaceID = nil
        }
        updateStatusText()
    }

    var isAnyLiveModeOn: Bool { quickIsOn || textIsOn || facesIsOn }

    private func updateStatusText() {
        if isAnyLiveModeOn {
            statusText = NSLocalizedString("vision.statusLiveOn", comment: "")
        } else {
            statusText = NSLocalizedString("vision.statusIdle", comment: "")
        }
    }

    private func handle(sampleBuffer: CMSampleBuffer) {
        guard facesIsOn || textIsOn else { return }
        frameCounter &+= 1

        if facesIsOn, !isFaceProcessing, (frameCounter & 1) == faceRouteFrame {
            isFaceProcessing = true
            faceRecognitionService.process(sampleBuffer: sampleBuffer) { [weak self] match, suggestion in
                Task { @MainActor in
                    self?.isFaceProcessing = false
                    self?.handleFaceResult(match, suggestion: suggestion)
                }
            } onSampleCollected: { [weak self] current, target in
                self?.statusText = NSLocalizedString("face.capturing", comment: "") + " \(current)/\(target)"
            } onLog: { [weak self] message in
                self?.settingsStore?.appendFaceLog(message)
            }
        }

        if textIsOn, !isTextProcessing, (frameCounter & 1) == textRouteFrame {
            isTextProcessing = true
            runLiveTextRecognition(sampleBuffer: sampleBuffer) { [weak self] observation in
                Task { @MainActor in
                    self?.isTextProcessing = false
                    self?.handleTextObservation(observation)
                }
            }
        }
    }

    // MARK: - Face handling

    private func handleFaceResult(_ match: FaceMatch?, suggestion: FaceSuggestion?) {
        if let match {
            lastSpokenFaceID = match.id
            statusText = NSLocalizedString("face.recognized", comment: "") + " \(match.name)."
            let spokenText = match.spokenText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !spokenText.isEmpty {
                presentResult(spokenText, statusKey: "vision.statusLiveOn", announce: true)
                return
            }
            if let filename = match.voiceNoteFilename {
                Task { @MainActor in
                    let url = await self.faceStore.recordingURL(for: filename)
                    self.facePlayer.play(url: url)
                }
                return
            }
            presentResult(NSLocalizedString("face.unlabeled", comment: ""), statusKey: "vision.statusLiveOn", announce: true)
        } else {
            lastSpokenFaceID = nil
            if facesIsOn {
                statusText = NSLocalizedString("face.scanning", comment: "")
            }
        }

        if let suggestion, enrollment.state == .idle, settingsStore?.suggestUnknownFaces ?? true {
            enrollment.begin(with: suggestion)
        }
    }

    // MARK: - Live text handling

    private func runLiveTextRecognition(
        sampleBuffer: CMSampleBuffer,
        completion: @escaping @MainActor (TextRecognitionObservation?) -> Void
    ) {
        guard let image = image(from: sampleBuffer) else {
            Task { @MainActor in completion(nil) }
            return
        }
        if settingsStore?.ocrEngine == OCREngineChoice.paddle.rawValue {
            paddleTextRecognitionService.process(image: image, completion: completion)
        } else {
            textRecognitionService.process(image: image, completion: completion)
        }
    }

    private func image(from sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let pixelW = CVPixelBufferGetWidth(pixelBuffer)
        let pixelH = CVPixelBufferGetHeight(pixelBuffer)
        let isPortraitBuffer = pixelH > pixelW
        let uprightCI = CIImage(cvPixelBuffer: pixelBuffer)
            .oriented(isPortraitBuffer ? .up : .right)
        guard let cgImage = Self.ciContext.createCGImage(uprightCI, from: uprightCI.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }

    private func handleTextObservation(_ observation: TextRecognitionObservation?) {
        guard let observation else {
            if textIsOn {
                statusText = NSLocalizedString("vision.statusLiveOn", comment: "")
            }
            return
        }
        statusText = NSLocalizedString("vision.statusLiveOn", comment: "")
        let normalizedText = normalizeForAnnouncement(observation.text)
        guard !normalizedText.isEmpty else { return }

        let now = Date()
        if pendingAnnouncementText.isEmpty {
            pendingAnnouncementText = normalizedText
            pendingAnnouncementSpokenText = observation.text
            pendingAnnouncementLanguage = observation.languageCode ?? "Unknown"
            pendingAnnouncementDate = now
            pendingAnnouncementCount = 1
            return
        }

        let candidateSimilarity = similarity(between: normalizedText, and: pendingAnnouncementText)
        if candidateSimilarity >= meaningfulChangeThreshold {
            pendingAnnouncementCount += 1
            pendingAnnouncementSpokenText = preferredAnnouncementText(current: pendingAnnouncementSpokenText, replacement: observation.text)
            pendingAnnouncementLanguage = observation.languageCode ?? pendingAnnouncementLanguage
        } else {
            pendingAnnouncementText = normalizedText
            pendingAnnouncementSpokenText = observation.text
            pendingAnnouncementLanguage = observation.languageCode ?? "Unknown"
            pendingAnnouncementDate = now
            pendingAnnouncementCount = 1
            return
        }

        let isStable = pendingAnnouncementCount >= minimumStableRepeats
            || now.timeIntervalSince(pendingAnnouncementDate) >= stabilityInterval
        guard isStable else { return }

        guard lastSpokenNormalizedText.isEmpty
            || similarity(between: pendingAnnouncementText, and: lastSpokenNormalizedText) < meaningfulChangeThreshold else {
            return
        }

        lastSpokenNormalizedText = pendingAnnouncementText
        presentResult(pendingAnnouncementSpokenText, statusKey: "vision.statusLiveOn", announce: true)
    }

    private func cancelTextStability() {
        pendingAnnouncementText = ""
        pendingAnnouncementSpokenText = ""
        pendingAnnouncementLanguage = "Unknown"
        pendingAnnouncementCount = 0
        lastSpokenNormalizedText = ""
    }

    private func normalizeForAnnouncement(_ text: String) -> String {
        text
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func preferredAnnouncementText(current: String, replacement: String) -> String {
        replacement.count >= current.count ? replacement : current
    }

    private func similarity(between lhs: String, and rhs: String) -> Double {
        let left = String(lhs.prefix(280))
        let right = String(rhs.prefix(280))

        guard !left.isEmpty || !right.isEmpty else { return 1 }
        guard !left.isEmpty, !right.isEmpty else { return 0 }

        let distance = levenshteinDistance(Array(left), Array(right))
        return 1 - (Double(distance) / Double(max(left.count, right.count)))
    }

    private func levenshteinDistance(_ lhs: [Character], _ rhs: [Character]) -> Int {
        guard !lhs.isEmpty else { return rhs.count }
        guard !rhs.isEmpty else { return lhs.count }

        var previous = Array(0...rhs.count)

        for (leftIndex, leftCharacter) in lhs.enumerated() {
            var current = [leftIndex + 1]
            current.reserveCapacity(rhs.count + 1)

            for (rightIndex, rightCharacter) in rhs.enumerated() {
                let insertion = current[rightIndex] + 1
                let deletion = previous[rightIndex + 1] + 1
                let substitution = previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
                current.append(min(insertion, deletion, substitution))
            }

            previous = current
        }

        return previous[rhs.count]
    }

    // MARK: - Result surfacing

    private func presentResult(_ text: String, statusKey: String, announce: Bool = true, statusKeyArgs: [CVarArg] = []) {
        lastResult = text
        statusText = String(format: NSLocalizedString(statusKey, comment: ""), statusKeyArgs)
        if announce {
            announcer.announce(text, minimumInterval: 0)
        }
    }
}