import Foundation
import UIKit
#if canImport(Translation)
import Translation
#endif

@MainActor
final class QuickRecognitionViewModel: ObservableObject {
    enum RequestKind {
        case caption(QuickCaptionLength)
        case query(QuickQueryPreset)
    }

    @Published var statusText = "Take a photo to quickly describe things"
    @Published var responseText = ""
    @Published var isProcessing = false
    @Published var isContinuousCapture = false
    @Published var errorMessage: String?
    @Published var capturedPreview: UIImage?
#if canImport(Translation)
    @Published var translationRequest: QuickTranslationRequest?
    #endif

    let camera = CameraPipeline()

    private let service = QuickRecognitionService()
    private let announcer = AccessibilityAnnouncementCenter()
    private weak var settingsStore: SettingsStore?
    private var continuousTask: Task<Void, Never>?
    private var latestCapturedImage: UIImage?
    private var latestRequestKind: RequestKind?

    func bind(settings: SettingsStore) {
        settingsStore = settings
    }

    func start() {
        statusText = "Take a photo to quickly describe things"
        camera.start()
    }

    func stop() {
        stopContinuousMode()
        camera.stop()
    }

    func takePhoto() {
        let length = QuickCaptionLength(rawValue: settingsStore?.quickCaptionLength ?? QuickCaptionLength.short.rawValue) ?? .short
        capture(.caption(length))
    }

    func takePresetPhoto(_ preset: QuickQueryPreset) {
        capture(.query(preset))
    }

    func startContinuousMode() {
        guard continuousTask == nil else { return }

        isContinuousCapture = true
        statusText = "Continuous mode is running."
        continuousTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.captureForContinuousMode()
                let interval = self.selectedContinuousInterval.timeInterval
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stopContinuousMode() {
        continuousTask?.cancel()
        continuousTask = nil
        isContinuousCapture = false
        if !isProcessing {
            statusText = "Quick Recognition is ready."
        }
    }

    func applyTranslatedResponse(_ translatedText: String, fallbackText: String) {
        let trimmed = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalText = trimmed.isEmpty ? fallbackText : trimmed
        presentResponse(finalText)
    }

    func resendCapturedPhotoInFullResolution() {
        guard !isProcessing else { return }
        guard let latestCapturedImage, let latestRequestKind else { return }

        Task {
            await performCapture(
                latestRequestKind,
                status: "Resending full-resolution image.",
                sourceImage: latestCapturedImage,
                useFullResolution: true
            )
        }
    }

    private func captureForContinuousMode() async {
        guard !isProcessing else { return }
        await performCapture(.caption(.short), status: "Analyzing scene.")
    }

    private func capture(_ request: RequestKind) {
        guard !isProcessing else { return }

        Task {
            await performCapture(request, status: "Analyzing scene.")
        }
    }

    private func performCapture(
        _ request: RequestKind,
        status: String,
        sourceImage: UIImage? = nil,
        useFullResolution: Bool = false
    ) async {
        guard let settingsStore else {
            errorMessage = "Quick Recognition settings are unavailable."
            return
        }

        let apiKey = settingsStore.quickMoondreamAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            errorMessage = QuickRecognitionError.missingAPIKey.localizedDescription
            return
        }

        guard let image = sourceImage ?? camera.currentFrameImage() else {
            statusText = "No camera frame is ready yet."
            return
        }

        latestCapturedImage = image
        latestRequestKind = request
        capturedPreview = makePreviewImage(from: image)

        isProcessing = true
        statusText = status
        #if canImport(Translation)
        translationRequest = nil
        #endif

        do {
            let imageDataURL = try service.prepareImageDataURL(
                from: image,
                maximumDimension: useFullResolution ? nil : 320,
                compressionQuality: useFullResolution ? 0.8 : 0.5
            )
            let response: String

            switch request {
            case .caption(let length):
                response = try await service.generateCaption(
                    imageDataURL: imageDataURL,
                    length: length,
                    apiKey: apiKey
                )
            case .query(let preset):
                response = try await service.queryImage(
                    imageDataURL: imageDataURL,
                    question: preset.prompt,
                    enforceSingleSentenceResponse: false,
                    apiKey: apiKey
                )
            }

            handleRecognitionSuccess(response)
        } catch is CancellationError {
            isProcessing = false
        } catch {
            errorMessage = error.localizedDescription
            statusText = "Quick Recognition failed."
            isProcessing = false
        }
    }

    private func handleRecognitionSuccess(_ response: String) {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusText = "Quick Recognition returned no result."
            isProcessing = false
            return
        }

        #if canImport(Translation)
        if #available(iOS 18.0, *),
           QuickTranslationSupport.shouldAttemptTranslation(
               for: trimmed,
               isTranslationEnabled: settingsStore?.quickCaptionTranslationEnabled ?? false,
               targetLanguageIdentifier: settingsStore?.quickCaptionTranslationTargetLanguage
           ),
           let targetLanguageIdentifier = settingsStore?.quickCaptionTranslationTargetLanguage,
           !targetLanguageIdentifier.isEmpty {
            translationRequest = QuickTranslationRequest(
                sourceText: trimmed,
                targetLanguageIdentifier: targetLanguageIdentifier
            )
            return
        }
        #endif

        presentResponse(trimmed)
    }

    private func presentResponse(_ response: String) {
        responseText = response
        statusText = isContinuousCapture ? "Continuous mode is running." : "Quick Recognition result is ready."
        announcer.announce(response, minimumInterval: 0)
        isProcessing = false
        #if canImport(Translation)
        translationRequest = nil
        #endif
    }

    private var selectedContinuousInterval: QuickContinuousCaptureInterval {
        QuickContinuousCaptureInterval(
            rawValue: settingsStore?.quickContinuousCaptureInterval ?? QuickContinuousCaptureInterval.defaultInterval.rawValue
        ) ?? .defaultInterval
    }

    private func makePreviewImage(from image: UIImage) -> UIImage {
        let maximumDimension: CGFloat = 260
        let originalSize = image.size
        guard originalSize.width > 0, originalSize.height > 0 else { return image }

        let scale = min(1, maximumDimension / max(originalSize.width, originalSize.height))
        let targetSize = CGSize(width: originalSize.width * scale, height: originalSize.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

#if canImport(Translation)
struct QuickTranslationRequest: Equatable {
    let id = UUID()
    let sourceText: String
    let targetLanguageIdentifier: String
}
#endif
