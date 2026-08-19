import AVFoundation
import Combine
import Foundation

@MainActor
final class FaceRecognitionViewModel: ObservableObject {
    @Published var statusText = NSLocalizedString("face.pointCamera", comment: "")
    @Published var recognizedName: String?
    @Published var pendingSuggestion: FaceSuggestion?
    @Published var errorMessage: String?
    @Published var sampleProgress: String?
    @Published var cameraState: CameraPipeline.State = .idle

    let camera = CameraPipeline()

    private let recognitionService = FaceRecognitionService()
    private let announcer = AccessibilityAnnouncementCenter()
    private weak var settingsStore: SettingsStore?
    private var cancellables = Set<AnyCancellable>()

    init() {
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
        camera.stop()
    }

    func saveSuggestion(named name: String) {
        guard let pendingSuggestion else { return }

        Task {
            do {
                _ = try await recognitionService.saveFace(name: name, suggestion: pendingSuggestion)
                self.pendingSuggestion = nil
                statusText = "\(name) " + NSLocalizedString("face.savedWithSamples", comment: "")
                announcer.announce(statusText, minimumInterval: 0)
                camera.start()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func dismissSuggestion() {
        pendingSuggestion = nil
        camera.start()
    }

    private var lastLogName: String?
    private var lastLogTime: Date = .distantPast

    private func handle(sampleBuffer: CMSampleBuffer) {
        recognitionService.process(sampleBuffer: sampleBuffer) { [weak self] match, suggestion in
            guard let self else { return }

            if let match {
                pendingSuggestion = nil
                recognizedName = match.name
                statusText = NSLocalizedString("face.recognized", comment: "") + " \(match.name)."
                sampleProgress = nil
                let now = Date()
                if match.name != lastLogName || now.timeIntervalSince(lastLogTime) >= 3.0 {
                    settingsStore?.appendFaceLog("Matched: \(match.name) \(String(format: "%.3f", match.confidence))")
                    lastLogName = match.name
                    lastLogTime = now
                }
                announcer.announce(match.name, minimumInterval: settingsStore?.faceSpeechCooldown ?? 2.5)
            } else {
                recognizedName = nil
                statusText = NSLocalizedString("face.scanning", comment: "")
            }

            if let suggestion, pendingSuggestion == nil, settingsStore?.suggestUnknownFaces ?? true {
                pendingSuggestion = suggestion
                sampleProgress = nil
                camera.stop()
                announcer.announce(NSLocalizedString("face.unknownDetected", comment: ""), minimumInterval: 3)
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
}
