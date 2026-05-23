import Foundation
import UIKit

@MainActor
final class DetailsDescriptionViewModel: ObservableObject {
    private static let helperInstruction = "Take a photo to describe the scene."
    private static let defaultDescriptionPrompt = "For a blind user, if visible text is present, read it exactly. If no text is visible, do not mention text detection. Then describe people, objects, layout, and orientation cues. Be concise and specific. Do not use markdown or double asterisks."

    @Published var statusText = helperInstruction
    @Published var descriptionText = ""
    @Published var followUpQuestion = ""
    @Published var isProcessing = false
    @Published var errorMessage: String?
    @Published var capturedPreview: UIImage?

    let camera = CameraPipeline()

    private let descriptionService = OpenAIDetailsDescriptionService()
    private let announcer = AccessibilityAnnouncementCenter()
    private var conversation: [DetailsDescriptionTurn] = []
    private var imageData: Data?
    private var latestCapturedImage: UIImage?
    private var latestPrompt = defaultDescriptionPrompt
    private var openAIStore: OpenAISubscriptionStore?

    func bind(openAIStore: OpenAISubscriptionStore) {
        self.openAIStore = openAIStore
    }

    func start() {
        statusText = Self.helperInstruction
        camera.start()
    }

    func stop() {
        camera.stop()
    }

    func capturePhoto() {
        capturePhotoWithPrompt(Self.defaultDescriptionPrompt)
    }

    func capturePresetPhoto(_ preset: QuickQueryPreset) {
        capturePhotoWithPrompt(preset.prompt)
    }

    func capturePhotoWithPrompt(_ prompt: String) {
        let cleaned = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalPrompt = cleaned.isEmpty ? Self.defaultDescriptionPrompt : cleaned
        capturePhoto(usingPrompt: finalPrompt)
    }

    private func capturePhoto(usingPrompt prompt: String) {
        capturePhoto(usingPrompt: prompt, sourceImage: nil, useFullResolution: false)
    }

    func resendCapturedPhotoInFullResolution() {
        guard !isProcessing else { return }
        guard let latestCapturedImage else { return }
        capturePhoto(usingPrompt: latestPrompt, sourceImage: latestCapturedImage, useFullResolution: true)
    }

    private func capturePhoto(usingPrompt prompt: String, sourceImage: UIImage?, useFullResolution: Bool) {
        guard !isProcessing else { return }
        guard let openAIStore else {
            errorMessage = OpenAISubscriptionError.notSignedIn.localizedDescription
            return
        }
        guard openAIStore.isSignedIn else {
            errorMessage = OpenAISubscriptionError.notSignedIn.localizedDescription
            return
        }
        guard let image = sourceImage ?? camera.currentFrameImage() else {
            statusText = "No camera frame is ready yet."
            return
        }

        isProcessing = true
        statusText = "Describing the photo."
        latestCapturedImage = image
        latestPrompt = prompt
        capturedPreview = makePreviewImage(from: image)

        Task {
            do {
                let preparedImageData = try descriptionService.prepareImageData(
                    from: image,
                    maximumDimension: useFullResolution ? nil : 640,
                    compressionQuality: useFullResolution ? 0.82 : 0.72
                )
                imageData = preparedImageData
                conversation = [
                    DetailsDescriptionTurn(
                        role: .user,
                        text: prompt
                    )
                ]

                let response = try await descriptionService.generateResponse(
                    imageData: preparedImageData,
                    conversation: conversation,
                    store: openAIStore
                )

                conversation.append(DetailsDescriptionTurn(role: .assistant, text: response))
                descriptionText = response
                statusText = "Photo details are ready."
                announcer.announce(response, minimumInterval: 0.25)
                isProcessing = false
            } catch {
                errorMessage = error.localizedDescription
                statusText = "Could not describe the photo."
                isProcessing = false
            }
        }
    }

    func submitFollowUp() {
        guard !isProcessing else { return }
        guard let openAIStore else {
            errorMessage = OpenAISubscriptionError.notSignedIn.localizedDescription
            return
        }
        guard let imageData else {
            errorMessage = OpenAIDetailsDescriptionError.missingImage.localizedDescription
            return
        }

        let question = followUpQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }

        isProcessing = true
        statusText = "Asking a follow-up question."
        conversation.append(DetailsDescriptionTurn(role: .user, text: question))
        followUpQuestion = ""

        Task {
            do {
                let response = try await descriptionService.generateResponse(
                    imageData: imageData,
                    conversation: conversation,
                    store: openAIStore
                )

                conversation.append(DetailsDescriptionTurn(role: .assistant, text: response))
                descriptionText = response
                statusText = "Follow-up answer is ready."
                announcer.announce(response, minimumInterval: 0.25)
                isProcessing = false
            } catch {
                errorMessage = error.localizedDescription
                statusText = "Could not answer the follow-up question."
                isProcessing = false
            }
        }
    }

    func retake() {
        isProcessing = false
        descriptionText = ""
        followUpQuestion = ""
        conversation = []
        imageData = nil
        capturedPreview = nil
        errorMessage = nil
        statusText = Self.helperInstruction
        camera.start()
    }

    private func makePreviewImage(from image: UIImage) -> UIImage {
        let maximumDimension: CGFloat = 280
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
