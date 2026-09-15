import Foundation

@MainActor
final class FaceEnrollmentCoordinator: ObservableObject {
    enum State: Equatable {
        case idle
        case pending
        case recording
        case recorded
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var isProcessingSave = false
    @Published private(set) var statusText = NSLocalizedString("face.pointCamera", comment: "")

    var engageLabel: String {
        switch state {
        case .idle, .pending:
            return NSLocalizedString("face.saveFace", comment: "")
        case .recording, .recorded:
            return NSLocalizedString("face.confirmSave", comment: "")
        }
    }

    var isSaveButtonEnabled: Bool { state != .idle && !isProcessingSave }

    var onAnnounce: ((String) -> Void)?
    var onSaved: ((String) -> Void)?

    private let recognitionService: FaceRecognitionService
    private let recorder = FaceAudioRecorder()
    private let faceStore = FaceStore()
    private var pendingFace: FaceSuggestion?
    private var pendingAudioData: Data?
    private var recordingTimer: Timer?
    private let recordingDuration: TimeInterval = 5

    init(recognitionService: FaceRecognitionService) {
        self.recognitionService = recognitionService
    }

    func begin(with suggestion: FaceSuggestion) {
        guard state == .idle, pendingFace == nil else { return }
        pendingFace = suggestion
        pendingAudioData = nil
        state = .pending
        statusText = NSLocalizedString("face.newFaceReady", comment: "")
        onAnnounce?(NSLocalizedString("face.newFaceHint", comment: ""))
    }

    func reset() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        if state == .recording {
            recorder.cancel()
        }
        pendingFace = nil
        pendingAudioData = nil
        state = .idle
        statusText = NSLocalizedString("face.pointCamera", comment: "")
    }

    func trigger() {
        switch state {
        case .idle:
            break
        case .pending:
            startRecording()
        case .recording, .recorded:
            completeSave(name: nil)
        }
    }

    /// Saves the pending face using a name typed by the user, without recording a
    /// voice note. An empty name saves the face as unnamed.
    func saveWithTextName(_ name: String) {
        guard state == .pending, pendingFace != nil else { return }
        completeSave(name: name)
    }

    func cancel() {
        reset()
        recognitionService.resetPendingEnrollment()
        statusText = NSLocalizedString("face.enrollmentCancelled", comment: "")
        onAnnounce?(statusText)
    }

    func reRecord() {
        guard state == .recorded || state == .recording else { return }
        recordingTimer?.invalidate()
        recordingTimer = nil
        if state == .recording {
            recorder.cancel()
        }
        pendingAudioData = nil
        startRecording()
    }

    func shutDown() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        if state == .recording {
            recorder.cancel()
        }
    }

    private func startRecording() {
        guard state == .pending, pendingFace != nil else { return }
        guard recorder.start() else {
            let msg = NSLocalizedString("face.micPermissionRequired", comment: "")
            statusText = msg
            onAnnounce?(msg)
            return
        }
        state = .recording
        statusText = NSLocalizedString("face.recordingPrompt", comment: "")
        onAnnounce?(NSLocalizedString("face.recordingStarted", comment: ""))
        recordingTimer = Timer.scheduledTimer(withTimeInterval: recordingDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.finishRecording()
            }
        }
    }

    private func finishRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        guard state == .recording, let url = recorder.stop() else { return }
        pendingAudioData = try? Data(contentsOf: url)
        state = .recorded
        statusText = NSLocalizedString("face.recordedPrompt", comment: "")
        onAnnounce?(NSLocalizedString("face.recordedReady", comment: ""))
    }

    private func completeSave(name: String?) {
        guard let pendingFace else { return }
        guard !isProcessingSave else { return }

        if state == .recording {
            recordingTimer?.invalidate()
            recordingTimer = nil
            if let url = recorder.stop() {
                pendingAudioData = try? Data(contentsOf: url)
            }
        }

        isProcessingSave = true
        let candidate = pendingFace
        let audioData = pendingAudioData

        Task {
            defer { isProcessingSave = false }
            do {
                if let saved = try await recognitionService.saveFace(
                    name: name,
                    suggestion: candidate,
                    voiceNoteData: audioData
                ) {
                    self.pendingFace = nil
                    self.pendingAudioData = nil
                    self.state = .idle
                    let text = "\(saved.name) " + NSLocalizedString("face.savedWithSamples", comment: "")
                    self.statusText = text
                    self.onSaved?(saved.name)
                    self.onAnnounce?(text)
                } else {
                    self.reset()
                    self.recognitionService.resetPendingEnrollment()
                    let blocked = NSLocalizedString("face.duplicateBlocked", comment: "")
                    self.statusText = blocked
                    self.onAnnounce?(blocked)
                }
            } catch {
                let failed = NSLocalizedString("face.saveFailed", comment: "")
                self.statusText = failed
                self.state = .idle
                self.pendingFace = nil
                self.onAnnounce?(failed)
            }
        }
    }
}