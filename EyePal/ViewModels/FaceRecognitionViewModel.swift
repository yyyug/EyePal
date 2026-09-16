import AVFoundation
import Combine
import Foundation

@MainActor
final class FaceRecognitionViewModel: ObservableObject {
    @Published var statusText = NSLocalizedString("face.pointCamera", comment: "")
    @Published var recognizedName: String?
    @Published var errorMessage: String?
    @Published var sampleProgress: String?
    @Published var cameraState: CameraPipeline.State = .idle

    let camera = CameraPipeline()
    let enrollment: FaceEnrollmentCoordinator

    private let recognitionService = FaceRecognitionService()
    private let faceStore = FaceStore()
    private let announcer = AccessibilityAnnouncementCenter()
    private let player = FaceAudioPlayer()
    private weak var settingsStore: SettingsStore?
    private var cancellables = Set<AnyCancellable>()

    private var lastSpokenFaceID: UUID?

    init() {
        enrollment = FaceEnrollmentCoordinator(recognitionService: recognitionService)
        enrollment.onAnnounce = { [weak self] text in
            self?.announcer.announce(text, minimumInterval: 0)
        }
        camera.onSampleBuffer = { [weak self] sampleBuffer in
            self?.handle(sampleBuffer: sampleBuffer)
        }
        camera.$state.sink { [weak self] newState in
            Task { @MainActor in
                guard let self else { return }
                self.cameraState = newState
                // Clear the "Starting camera…" text once the camera is live.
                if case .running = newState, self.enrollment.state == .idle {
                    self.statusText = NSLocalizedString("face.scanning", comment: "")
                }
            }
        }.store(in: &cancellables)
    }

    func bind(settings: SettingsStore) {
        settingsStore = settings
        recognitionService.recognitionThreshold = max(Float(settings.faceMatchThreshold), 0.30)
        recognitionService.minimumTopMatchMargin = max(Float(settings.faceMatchMargin), 0.01)
        recognitionService.onLog = { [weak self] msg in
            self?.settingsStore?.appendFaceLog(msg)
        }
    }

    func start() {
        statusText = NSLocalizedString("face.loadingFaces", comment: "")

        Task {
            do {
                _ = try await recognitionService.loadProfiles()
                recognitionService.loadEmbeddingEngine()
                statusText = NSLocalizedString("face.starting", comment: "")
                camera.start()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func stop() {
        enrollment.shutDown()
        player.stop()
        camera.stop()
    }

    private var lastLogName: String?
    private var lastLogTime: Date = .distantPast

    private func handle(sampleBuffer: CMSampleBuffer) {
        recognitionService.process(sampleBuffer: sampleBuffer) { [weak self] match, suggestion in
            guard let self else { return }

            if let match {
                self.handleMatch(match)
            } else {
                self.lastSpokenFaceID = nil
                self.recognizedName = nil
                self.statusText = NSLocalizedString("face.scanning", comment: "")
            }

            if let suggestion, self.enrollment.state == .idle,
               self.settingsStore?.suggestUnknownFaces ?? true {
                self.sampleProgress = nil
                self.enrollment.begin(with: suggestion)
            }
        } onSampleCollected: { [weak self] current, target in
            Task { @MainActor in
                self?.sampleProgress = NSLocalizedString("face.capturing", comment: "") + " \(current)/\(target)"
                self?.settingsStore?.appendFaceLog("Sample collected: \(current)/\(target)")
            }
        } onLog: { [weak self] message in
            self?.settingsStore?.appendFaceLog(message)
        }
    }

    private func handleMatch(_ match: FaceMatch) {
        recognizedName = match.name
        statusText = NSLocalizedString("face.recognized", comment: "") + " \(match.name)."
        sampleProgress = nil

        let now = Date()
        if match.name != lastLogName || now.timeIntervalSince(lastLogTime) >= 3.0 {
            settingsStore?.appendFaceLog("Matched: \(match.name) \(String(format: "%.3f", match.confidence))")
            lastLogName = match.name
            lastLogTime = now
        }

        guard lastSpokenFaceID != match.id else { return }
        lastSpokenFaceID = match.id

        let spokenText = match.spokenText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !spokenText.isEmpty {
            announcer.announce(spokenText, minimumInterval: 0)
            return
        }
        if let filename = match.voiceNoteFilename {
            Task { @MainActor in
                let url = await self.faceStore.recordingURL(for: filename)
                self.player.play(url: url)
            }
            return
        }
        announcer.announce(match.name, minimumInterval: 0)
    }
}