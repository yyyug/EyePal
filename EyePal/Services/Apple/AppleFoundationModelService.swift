import Foundation
import UIKit
#if canImport(FoundationModels)
import FoundationModels
#endif

enum AppleFoundationModelError: LocalizedError {
    case unsupportedSystem
    case imageEncodingFailed
    case emptyResponse
    case engineFailure(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSystem:
            return NSLocalizedString("apple.error.unsupportedOS", comment: "")
        case .imageEncodingFailed:
            return NSLocalizedString("apple.error.imageEncoding", comment: "")
        case .emptyResponse:
            return NSLocalizedString("apple.error.emptyResponse", comment: "")
        case .engineFailure(let message):
            return message
        }
    }
}

/// Recognition backed by Apple's on-device Foundation Model (Apple Intelligence).
/// Requires iOS 27 or later, which adds image understanding to the framework.
final class AppleFoundationModelService {

    static let shared = AppleFoundationModelService()

    /// Long edge used before handing the image to the model. Apple's guidance is
    /// to shrink large camera frames so the image tokens stay within the context
    /// window and latency stays low.
    private static let maximumImageDimension: CGFloat = 1600

    private init() {}

    var isSupported: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 27.0, *) {
            return true
        }
        #endif
        return false
    }

    func generateCaption(image: UIImage, length: QuickCaptionLength) async throws -> String {
        try await run(prompt: length.onDevicePrompt, image: image)
    }

    func queryImage(
        image: UIImage,
        question: String,
        enforceSingleSentenceResponse: Bool
    ) async throws -> String {
        let prompt = enforceSingleSentenceResponse
            ? question + " Respond with one sentence."
            : question
        return try await run(prompt: prompt, image: image)
    }

    private func run(prompt: String, image: UIImage) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 27.0, *) {
            guard let cgImage = preparedCGImage(from: image) else {
                throw AppleFoundationModelError.imageEncodingFailed
            }

            let session = LanguageModelSession()
            do {
                let response = try await session.respond {
                    prompt
                    Attachment(cgImage)
                }
                let trimmed = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    throw AppleFoundationModelError.emptyResponse
                }
                return trimmed
            } catch let error as AppleFoundationModelError {
                throw error
            } catch {
                throw AppleFoundationModelError.engineFailure(error.localizedDescription)
            }
        }
        #endif
        throw AppleFoundationModelError.unsupportedSystem
    }

    private func preparedCGImage(from image: UIImage) -> CGImage? {
        let longestEdge = max(image.size.width, image.size.height)
        guard longestEdge > 0 else { return nil }

        let scale = min(1, Self.maximumImageDimension / longestEdge)
        let targetSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let prepared = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return prepared.cgImage
    }
}
