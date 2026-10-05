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
@Generable(description: "A detailed spoken description of a photograph for a blind person")
struct AppleSceneDescription {
    @Guide(description: "The overall scene")
    var overview: String

    @Guide(description: "One notable element, person or surface per sentence, naming its color", .minimumCount(3))
    var notableElements: [String]

    @Guide(description: "One positional fact per sentence, using clock positions or left and right", .minimumCount(1))
    var spatialLayout: [String]

    /// An enum rather than free text: this is the one decision in the schema
    /// that is genuinely bounded, which is what constrained sampling is good at.
    var textPresence: AppleTextPresence

    @Guide(description: "The text itself, or a note that there is none", .minimumCount(1))
    var visibleText: [String]

    @Guide(description: "Something the viewer should watch out for, or a note that there is none", .minimumCount(1))
    var cautions: [String]
}

@available(iOS 27.0, *)
@Generable(description: "Whether the photograph contains readable text")
enum AppleTextPresence: String, Equatable {
    case none
    case present
}
#endif

#if canImport(FoundationModels)
/// Builds a session for one request. Prefers Private Cloud Compute when it is
/// available, and falls back to the on-device System model otherwise (offline,
/// quota exhausted, or a device without Apple Intelligence eligibility).
@available(iOS 27.0, *)
private func makeAppleSession(instructions: String) -> LanguageModelSession {
    if PrivateCloudComputeLanguageModel().isAvailable {
        return LanguageModelSession(model: PrivateCloudComputeLanguageModel(), instructions: instructions)
    }
    return LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
}

/// Holds the session `prewarm` loads model assets into.
///
/// It lives in its own availability-annotated type because the app still deploys
/// back to iOS 17 while `LanguageModelSession` needs iOS 26, and a stored property
/// cannot itself be marked potentially unavailable. Nothing is ever generated
/// with this session: it exists only so the assets are already resident when the
/// first real request opens its own session.
@available(iOS 27.0, *)
private final class WarmSessionHolder {
    let session: LanguageModelSession

    init(instructions: String) {
        session = makeAppleSession(instructions: instructions)
    }
}
#endif

/// Recognition backed by Apple Foundation Models: Private Cloud Compute when
/// available, falling back to the on-device System model. Requires iOS 27 or
/// later, which is where `Attachment` and image understanding entered the
/// framework.
@MainActor
final class AppleFoundationModelService {

    static let shared = AppleFoundationModelService()

    /// Long edge used before handing the image to the model. Apple's guidance is
    /// to shrink large camera frames so the image tokens stay within the context
    /// window and latency stays low.
    private static let maximumImageDimension: CGFloat = 1600

    #if canImport(FoundationModels)
    /// Held only so `prewarm` has something to load into. It is never used for
    /// a request, because requests each get their own session.
    private var warmHolder: AnyObject?
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
            guard warmHolder == nil else { return }
            let holder = WarmSessionHolder(instructions: Self.sessionInstructions)
            warmHolder = holder
            holder.session.prewarm()
        }
        #endif
    }

    func generateCaption(image: UIImage, length: QuickCaptionLength) async throws -> String {
        let prompt = Self.labelledPrompt(length.appleFoundationPrompt)
        #if canImport(FoundationModels)
        if #available(iOS 27.0, *) {
            guard let cgImage = preparedCGImage(from: image) else {
                throw AppleFoundationModelError.imageEncodingFailed
            }

            switch length {
            case .short, .normal:
                return try requireText(try await respond(prompt: prompt, image: cgImage))
            case .long:
                // Kept for the detailed tier, where the schema really does
                // constrain: an enum for text presence plus minimum counts.
                do {
                    let result = try await freshSession().respond(
                        generating: AppleSceneDescription.self,
                        options: GenerationOptions(samplingMode: .greedy)
                    ) {
                        prompt
                        Attachment(cgImage).label(Self.attachmentLabel)
                    }
                    let description = result.content
                    return try requireText(compose(
                        [description.overview]
                            + description.notableElements
                            + description.spatialLayout
                            + description.visibleText
                            + description.cautions
                    ))
                } catch {
                    // Two rules, both learned from a crash report: never ask a
                    // session that has already thrown for anything, and never
                    // re-enter the framework after this task was cancelled.
                    // `respond` failing tears the session down, and a second call
                    // on it walks FoundationModels into an internal assertion
                    // failure (EXC_BREAKPOINT, six frames inside the framework,
                    // entered via completeTaskWithClosure delivering a
                    // CancellationError). So the retry gets a brand new session,
                    // and a cancelled task just reports the failure.
                    guard !Task.isCancelled else {
                        throw AppleFoundationModelError.engineFailure(
                            error.localizedDescription
                        )
                    }
                    return try requireText(try await respond(prompt: prompt, image: cgImage))
                }
            }
        }
        #endif
        throw AppleFoundationModelError.unsupportedSystem
    }

    /// One plain multimodal request on its own session. Every text request goes
    /// through here so no path can ever reuse a session that has thrown.
    @available(iOS 27.0, *)
    private func respond(prompt: String, image cgImage: CGImage) async throws -> String {
        let response = try await freshSession().respond {
            prompt
            Attachment(cgImage).label(Self.attachmentLabel)
        }
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
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
            let labelled = Self.labelledPrompt(prompt)
            do {
                // A free-form question has no shape to guide, so it is answered
                // as plain text rather than forced into the description schema.
                return try requireText(try await respond(prompt: labelled, image: cgImage))
            } catch let error as AppleFoundationModelError {
                throw error
            } catch {
                throw AppleFoundationModelError.engineFailure(error.localizedDescription)
            }
        }
        #endif
        throw AppleFoundationModelError.unsupportedSystem
    }

    /// Model generation and prompt version, for the settings screen. Reports the
    /// Private Cloud Compute model in use. The model's context size is async and
    /// throwing, so it is left out of this synchronous, non-throwing property.
    var diagnosticsDescription: String? {
        #if canImport(FoundationModels)
        if #available(iOS 27.0, *) {
            let model = PrivateCloudComputeLanguageModel()
            return String(
                format: NSLocalizedString("settings.appleProvider.diagnostics", comment: ""),
                String(describing: model),
                QuickCaptionLength.appleFoundationPromptVersion
            )
        }
        #endif
        return nil
    }

    #if canImport(FoundationModels)
    /// A new session per capture, on purpose.
    ///
    /// Every request adds an image to the session's transcript. Sharing one
    /// session across captures therefore left the model looking at several
    /// unlabelled photos at once, and it would answer about whichever one it
    /// latched onto — or confabulate, since the prompt's "this image" was
    /// ambiguous. One session, one image, no ambiguity. The cost is the prompt
    /// prefix cache, which `prewarmIfNeeded` more than makes up for: the model
    /// assets stay resident in the process either way.
    @available(iOS 27.0, *)
    private func freshSession() -> LanguageModelSession {
        makeAppleSession(instructions: Self.sessionInstructions)
    }

    /// Referenced in the prompt as well as on the attachment, so the model has
    /// one unambiguous handle on the image. Plain string building, so it carries
    /// no availability requirement of its own.
    private static let attachmentLabel = "image-0"

    private static func labelledPrompt(_ base: String) -> String {
        QuickPromptLanguage.isChinese
            ? "\(base)（影像標記為 image-0，請描述 image-0。）"
            : "\(base) The image is labelled image-0; describe image-0."
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
