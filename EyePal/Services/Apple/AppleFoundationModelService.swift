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

#if canImport(FoundationModels)
/// Description shapes handed to the model as a schema.
///
/// The requested amount of detail is expressed by the schema rather than by
/// asking the model to be verbose in prose: the framework fills these types
/// using constrained sampling, so the shape decides how much comes back. This
/// is the only reliable way to get a long answer, because
/// `GenerationOptions.maximumResponseTokens` is an upper bound only and Apple
/// warns that enforcing a tight limit yields malformed or truncated text.
@available(iOS 27.0, *)
@Generable(description: "A one-sentence spoken description of a photograph for a blind person")
struct AppleSceneSummary {
    @Guide(description: "The scene and its single most important element")
    var summary: String
}

@available(iOS 27.0, *)
@Generable(description: "A three-sentence spoken description of a photograph for a blind person")
struct AppleSceneOverview {
    @Guide(description: "The overall scene")
    var overview: String

    @Guide(description: "One notable element, person or surface per sentence, and where it is", .minimumCount(2))
    var notableElements: [String]
}

@available(iOS 27.0, *)
@Generable(description: "A detailed spoken description of a photograph for a blind person")
struct AppleSceneDescription {
    @Guide(description: "The overall scene")
    var overview: String

    @Guide(description: "One notable element, person or surface per sentence, naming its color", .minimumCount(3))
    var notableElements: [String]

    @Guide(description: "One positional fact per sentence, using clock positions or left and right", .minimumCount(1))
    var spatialLayout: [String]

    @Guide(description: "Text visible in the image, or a note that there is none", .minimumCount(1))
    var visibleText: [String]

    @Guide(description: "Something the viewer should watch out for, or a note that there is none", .minimumCount(1))
    var cautions: [String]
}
#endif

#if canImport(FoundationModels)
/// Owns the long-lived session and its bookkeeping.
///
/// This lives in its own availability-annotated type because the app still
/// deploys back to iOS 17 while `LanguageModelSession` needs iOS 26, and a
/// stored property cannot itself be marked potentially unavailable.
@available(iOS 27.0, *)
private final class AppleSessionHolder {
    let session: LanguageModelSession
    var requests = 0
    var hasPrewarmed = false

    init(instructions: String) {
        session = LanguageModelSession(instructions: instructions)
    }
}
#endif

/// Recognition backed by Apple's on-device Foundation Model (Apple Intelligence).
/// Requires iOS 27 or later, which is where `Attachment` and image understanding
/// entered the framework.
@MainActor
final class AppleFoundationModelService {

    static let shared = AppleFoundationModelService()

    /// Long edge used before handing the image to the model. Apple's guidance is
    /// to shrink large camera frames so the image tokens stay within the context
    /// window and latency stays low.
    private static let maximumImageDimension: CGFloat = 1600

    /// How many requests share one session.
    ///
    /// A session is reused so the loaded model assets and the prompt-prefix cache
    /// survive between captures, but its transcript has to be dropped regularly:
    /// every request adds an image to the context and `respond` throws
    /// `contextSizeExceeded` once the window fills up. Images are far too large
    /// to keep many of them around, so the session is rotated on this counter
    /// rather than growing until it fails.
    private static let requestsPerSession = 4

    #if canImport(FoundationModels)
    private var sessionHolder: AnyObject?
    #endif

    private init() {}

    var isSupported: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 27.0, *) {
            return true
        }
        #endif
        return false
    }

    /// Loads the model into memory ahead of the first capture.
    ///
    /// Apple documents `prewarm` for precisely this: the first request of a
    /// session pays to load the model assets, and every later one reuses them,
    /// which is why the first capture of a visit feels slower than the rest.
    /// Call it when the view appears so the load overlaps with the user aiming
    /// the camera. It is safe to call more than once.
    func prewarmIfNeeded() {
        #if canImport(FoundationModels)
        if #available(iOS 27.0, *) {
            let holder = currentHolder()
            guard !holder.hasPrewarmed else { return }
            holder.hasPrewarmed = true
            holder.session.prewarm()
        }
        #endif
    }

    func generateCaption(image: UIImage, length: QuickCaptionLength) async throws -> String {
        let prompt = length.appleFoundationPrompt
        #if canImport(FoundationModels)
        if #available(iOS 27.0, *) {
            guard let cgImage = preparedCGImage(from: image) else {
                throw AppleFoundationModelError.imageEncodingFailed
            }
            let session = currentHolder().session
            let imagePrompt = Prompt {
                prompt
                Attachment(cgImage)
            }

            do {
                switch length {
                case .short:
                    let result = try await session.respond(
                        to: imagePrompt,
                        generating: AppleSceneSummary.self
                    )
                    return try requireText(compose([result.content.summary]))
                case .normal:
                    let result = try await session.respond(
                        to: imagePrompt,
                        generating: AppleSceneOverview.self
                    )
                    return try requireText(
                        compose([result.content.overview] + result.content.notableElements)
                    )
                case .long:
                    let result = try await session.respond(
                        to: imagePrompt,
                        generating: AppleSceneDescription.self
                    )
                    let description = result.content
                    return try requireText(compose(
                        [description.overview]
                            + description.notableElements
                            + description.spatialLayout
                            + description.visibleText
                            + description.cautions
                    ))
                }
            } catch let error as AppleFoundationModelError {
                throw error
            } catch {
                // Guided generation fails when the context window is too full to
                // satisfy the schema. A plain description is a poor answer but a
                // far better one than none, so fall back to it.
                let response = try await session.respond {
                    prompt
                    Attachment(cgImage)
                }
                return try requireText(
                    response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        }
        #endif
        throw AppleFoundationModelError.unsupportedSystem
    }

    func queryImage(
        image: UIImage,
        question: String,
        enforceSingleSentenceResponse: Bool
    ) async throws -> String {
        var prompt = question
        if enforceSingleSentenceResponse {
            prompt += QuickPromptLanguage.isChinese ? " 請用一句話回答。" : " Respond with one sentence."
        }
        #if canImport(FoundationModels)
        if #available(iOS 27.0, *) {
            guard let cgImage = preparedCGImage(from: image) else {
                throw AppleFoundationModelError.imageEncodingFailed
            }
            let session = currentHolder().session
            do {
                // A free-form question has no shape to guide, so it is answered
                // as plain text rather than forced into the description schemas.
                let response = try await session.respond {
                    prompt
                    Attachment(cgImage)
                }
                return try requireText(
                    response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            } catch let error as AppleFoundationModelError {
                throw error
            } catch {
                throw AppleFoundationModelError.engineFailure(error.localizedDescription)
            }
        }
        #endif
        throw AppleFoundationModelError.unsupportedSystem
    }

    /// Model generation, context window and prompt version, for the settings
    /// screen. The on-device model changes with the OS, so this is the quickest
    /// way to confirm which one a build is actually running against.
    var diagnosticsDescription: String? {
        #if canImport(FoundationModels)
        if #available(iOS 27.0, *) {
            let model = SystemLanguageModel.default
            return String(
                format: NSLocalizedString("settings.appleProvider.diagnostics", comment: ""),
                String(describing: model.variant),
                model.contextSize,
                QuickCaptionLength.appleFoundationPromptVersion
            )
        }
        #endif
        return nil
    }

    #if canImport(FoundationModels)
    @available(iOS 27.0, *)
    private func currentHolder() -> AppleSessionHolder {
        if let holder = sessionHolder as? AppleSessionHolder,
           holder.requests < Self.requestsPerSession {
            holder.requests += 1
            return holder
        }
        let holder = AppleSessionHolder(instructions: Self.sessionInstructions)
        holder.requests = 1
        sessionHolder = holder
        return holder
    }

    /// Apple recommends giving the model a role, and this one has a fixed job:
    /// describe only what is visible, for someone who cannot see.
    @available(iOS 27.0, *)
    private static var sessionInstructions: String {
        if QuickPromptLanguage.isChinese {
            return """
            你是一位為視障者撰寫口述影像描述的專家。\
            只描述看得見的事實，不要猜測或補腦，\
            使用具體的名詞、顏色與方位，\
            不要提到「圖片」或「照片」本身。
            """
        }
        return """
        You are an expert writing spoken image descriptions for blind people. \
        Describe only what is visible and never speculate or fill in gaps. \
        Use concrete nouns, colors and positions. \
        Do not refer to the image or the photo itself.
        """
    }
    #endif

    /// Flattens generated fields into one paragraph, because the result is read
    /// aloud by VoiceOver and a labeled list would be stilted to listen to.
    private func compose(_ parts: [String]) -> String {
        let terminators: Set<Character> = [
            ".", ",", "!", "?", ";", ":",
            "，", "、", "。", "！", "？", "；", "："
        ]
        let cleaned = parts.compactMap { part -> String? in
            var text = part.trimmingCharacters(in: .whitespacesAndNewlines)
            while let last = text.last, terminators.contains(last) {
                text.removeLast()
            }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        return cleaned.joined(separator: QuickPromptLanguage.isChinese ? "。" : ". ")
    }

    private func requireText(_ text: String) throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppleFoundationModelError.emptyResponse
        }
        return text
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
