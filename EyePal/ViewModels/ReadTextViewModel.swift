import AVFoundation
import Foundation
import UIKit
import Vision

@MainActor
final class ReadTextViewModel: ObservableObject {
    struct CapturedTextResult: Identifiable {
        let id = UUID()
        let text: String
        let language: String
    }

    @Published var recognizedText = "Point the camera at printed text."
    @Published var detectedLanguage = "Unknown"
    @Published var cameraStateDescription = "Preparing camera..."
    @Published var capturedResult: CapturedTextResult?
    @Published var isCapturingPhoto = false
    @Published var isDocumentDetectionEnabled = false

    let camera = CameraPipeline()

    private let textRecognitionService = TextRecognitionService()
    private let paddleTextRecognitionService = PaddleTextRecognitionService()
    private let announcer = AccessibilityAnnouncementCenter()
    private weak var settingsStore: SettingsStore?
    private let stabilityInterval: TimeInterval = 0.6
    private let minimumStableRepeats = 2
    private let meaningfulChangeThreshold = 0.85

    private var pendingAnnouncementText = ""
    private var pendingAnnouncementSpokenText = ""
    private var pendingAnnouncementLanguage = "Unknown"
    private var pendingAnnouncementDate = Date.distantPast
    private var pendingAnnouncementCount = 0
    private var lastSpokenNormalizedText = ""
    private var isPresentingCapturedResult = false
    private var isProcessingFrame = false
    private let documentQueue = DispatchQueue(label: "com.eyepals.readtext.document-detection")
    private var isProcessingDocumentFrame = false
    private var consecutiveRectangleDetections = 0
    private var nextAutoCaptureAllowedAt = Date.distantPast
    private let requiredRectangleDetections = 3
    private let autoCaptureCooldown: TimeInterval = 2.0

    init() {
        camera.onSampleBuffer = { [weak self] sampleBuffer in
            self?.handle(sampleBuffer: sampleBuffer)
        }
    }

    func bind(settings: SettingsStore) {
        settingsStore = settings
    }

    func start() {
        guard !isPresentingCapturedResult else { return }
        cameraStateDescription = "Starting live text reader."
        camera.start()
    }

    func stop() {
        camera.stop()
    }

    func toggleDocumentDetection() {
        isDocumentDetectionEnabled.toggle()
        if isDocumentDetectionEnabled {
            cameraStateDescription = "Document detection on. Auto-capture is enabled."
        } else {
            cameraStateDescription = "Document detection off."
            consecutiveRectangleDetections = 0
        }
    }

    private var usePaddleOCR: Bool {
        settingsStore?.ocrEngine == OCREngineChoice.paddle.rawValue
    }

    private func image(from sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = CIContext().createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .right)
    }

    func capturePhoto() {
        capturePhoto(triggeredAutomatically: false)
    }

    private func capturePhoto(triggeredAutomatically: Bool) {
        guard !isCapturingPhoto else { return }
        guard let image = camera.currentFrameImage() else {
            cameraStateDescription = "No camera frame is ready yet."
            return
        }

        isCapturingPhoto = true
        isPresentingCapturedResult = true
        camera.stop()
        cameraStateDescription = triggeredAutomatically ? "Document detected. Capturing photo." : "Reading captured photo."

        runRecognition(image: image) { [weak self] observation in
            self?.handlePhotoObservation(observation)
        }
    }

    private func handlePhotoObservation(_ observation: TextRecognitionObservation?) {
        let text = observation?.text.trimmingCharacters(in: .whitespacesAndNewlines)
        capturedResult = CapturedTextResult(
            text: text?.isEmpty == false ? text! : "No text was found in this photo.",
            language: observation?.languageCode ?? "Unknown"
        )
        isCapturingPhoto = false
        cameraStateDescription = "Captured text is ready."
        consecutiveRectangleDetections = 0
        nextAutoCaptureAllowedAt = Date().addingTimeInterval(autoCaptureCooldown)
    }

    private func runRecognition(
        image: UIImage,
        completion: @escaping @MainActor (TextRecognitionObservation?) -> Void
    ) {
        if usePaddleOCR {
            paddleTextRecognitionService.process(image: image, completion: completion)
        } else {
            textRecognitionService.process(image: image, completion: completion)
        }
    }

    private func runLiveRecognition(
        sampleBuffer: CMSampleBuffer,
        completion: @escaping @MainActor (TextRecognitionObservation?) -> Void
    ) {
        if usePaddleOCR {
            guard let image = image(from: sampleBuffer) else {
                Task { @MainActor in completion(nil) }
                return
            }
            paddleTextRecognitionService.process(image: image, completion: completion)
        } else {
            textRecognitionService.process(sampleBuffer: sampleBuffer, completion: completion)
        }
    }

    func dismissCapturedResult() {
        capturedResult = nil
        isPresentingCapturedResult = false
        pendingAnnouncementText = ""
        pendingAnnouncementSpokenText = ""
        pendingAnnouncementCount = 0
        cameraStateDescription = "Starting live text reader."
        camera.start()
    }

    private func handle(sampleBuffer: CMSampleBuffer) {
        guard !isPresentingCapturedResult else { return }

        if isDocumentDetectionEnabled {
            processDocumentDetection(sampleBuffer: sampleBuffer)
        }

        guard !isProcessingFrame else { return }
        isProcessingFrame = true

        runLiveRecognition(sampleBuffer: sampleBuffer) { [weak self] observation in
            self?.isProcessingFrame = false
            guard let self, let observation else { return }

            self.recognizedText = observation.text
            self.detectedLanguage = observation.languageCode ?? "Unknown"
            self.cameraStateDescription = "Reading live text."
            self.handleLiveObservation(observation)
        }
    }

    private func handleLiveObservation(_ observation: TextRecognitionObservation) {
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
        detectedLanguage = pendingAnnouncementLanguage
        announcer.announce(pendingAnnouncementSpokenText, minimumInterval: settingsStore?.readTextSpeechCooldown ?? 2.5)
    }

    private func processDocumentDetection(sampleBuffer: CMSampleBuffer) {
        guard !isCapturingPhoto, !isPresentingCapturedResult else { return }
        guard Date() >= nextAutoCaptureAllowedAt else { return }

        documentQueue.async { [weak self] in
            guard let self else { return }
            guard !self.isProcessingDocumentFrame else { return }
            self.isProcessingDocumentFrame = true

            let request = VNDetectRectanglesRequest()
            request.maximumObservations = 1
            request.minimumConfidence = 0.65
            request.minimumAspectRatio = 0.4
            request.minimumSize = 0.2
            request.quadratureTolerance = 20

            do {
                let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .right)
                try handler.perform([request])
                let hasRectangle = !(request.results ?? []).isEmpty

                Task { @MainActor in
                    self.handleDocumentDetectionResult(hasRectangle)
                }
            } catch {
                Task { @MainActor in
                    self.consecutiveRectangleDetections = 0
                }
            }

            self.isProcessingDocumentFrame = false
        }
    }

    @MainActor
    private func handleDocumentDetectionResult(_ hasRectangle: Bool) {
        guard isDocumentDetectionEnabled else {
            consecutiveRectangleDetections = 0
            return
        }

        if hasRectangle {
            consecutiveRectangleDetections += 1
            if consecutiveRectangleDetections >= requiredRectangleDetections {
                capturePhoto(triggeredAutomatically: true)
            }
        } else {
            consecutiveRectangleDetections = 0
        }
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
}
