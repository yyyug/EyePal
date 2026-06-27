import AVFoundation
import Foundation

@MainActor
final class FaceRecognitionViewModel: ObservableObject {
    @Published var statusText = "Point the camera at a face."
    @Published var recognizedName: String?
    @Published var pendingSuggestion: FaceSuggestion?
    @Published var errorMessage: String?
    @Published var sampleProgress: String?

    let camera = CameraPipeline()

    private let recognitionService = FaceRecognitionService()
    private let announcer = AccessibilityAnnouncementCenter()
    private weak var settingsStore: SettingsStore?

    init() {
        camera.onSampleBuffer = { [weak self] sampleBuffer in
            self?.handle(sampleBuffer: sampleBuffer)
        }
    }

    func bind(settings: SettingsStore) {
        settingsStore = settings
        recognitionService.recognitionThreshold = max(Float(settings.faceMatchThreshold), 0.90)
        recognitionService.minimumTopMatchMargin = max(Float(settings.faceMatchMargin), 0.01)
    }

    func start() {
        statusText = "Loading saved faces."

        Task {
            do {
                _ = try await recognitionService.loadProfiles()
                statusText = "Starting face recognition."
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
                statusText = "\(name) was saved with multiple samples for on-device recognition."
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

    private func handle(sampleBuffer: CMSampleBuffer) {
        recognitionService.process(sampleBuffer: sampleBuffer) { [weak self] match, suggestion in
            guard let self else { return }

            if let match {
                pendingSuggestion = nil
                recognizedName = match.name
                statusText = "Recognized \(match.name)."
                sampleProgress = nil
                settingsStore?.appendFaceLog("Matched: \(match.name) \(String(format: "%.3f", match.confidence))")
                announcer.announce(match.name, minimumInterval: settingsStore?.faceSpeechCooldown ?? 2.5)
            } else {
                recognizedName = nil
                statusText = "Scanning for known faces."
                if let embedding = result.embedding {
                    settingsStore?.appendFaceLog("No match. Embedding dim=\(embedding.count), profiles=\(self.recognitionService.getProfiles().count)")
                } else {
                    settingsStore?.appendFaceLog("ERROR: embedding is nil - model may not be loaded")
                }
            }

            if let suggestion, pendingSuggestion == nil, settingsStore?.suggestUnknownFaces ?? true {
                pendingSuggestion = suggestion
                sampleProgress = nil
                camera.stop()
                announcer.announce("Unknown face detected. A few samples were captured, and you can add this person.", minimumInterval: 3)
            }
        } onSampleCollected: { [weak self] current, target in
            Task { @MainActor in
                self?.sampleProgress = "Capturing samples... \(current)/\(target)"
                self?.settingsStore?.appendFaceLog("Sample collected: \(current)/\(target)")
            }
        } onLog: { [weak self] message in
            self?.settingsStore?.appendFaceLog(message)
        }
    }
}
