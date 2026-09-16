import Foundation
import UIKit
#if canImport(FoundationModels)
import FoundationModels
#endif

enum QuickRecognitionError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case invalidResponse
    case emptyResponse
    case badStatusCode(Int, String)
    case imageEncodingFailed

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add your Moondream API key in Settings > Quick Recognition."
        case .invalidURL:
            return "The Moondream API URL is invalid."
        case .invalidResponse:
            return "The Moondream response could not be read."
        case .emptyResponse:
            return "Moondream returned an empty response."
        case .badStatusCode(let code, let body):
            return body.isEmpty ? "Moondream request failed with HTTP \(code)." : body
        case .imageEncodingFailed:
            return "The image could not be prepared for quick recognition."
        }
    }
}

final class QuickRecognitionService {
    private let session: URLSession
    private let baseURL = "https://api.moondream.ai/v1"

    init(session: URLSession = .shared) {
        self.session = session
    }

    func prepareImageDataURL(
        from image: UIImage,
        maximumDimension: CGFloat? = 320,
        compressionQuality: CGFloat = 0.5
    ) throws -> String {
        let originalSize = image.size
        guard originalSize.width > 0, originalSize.height > 0 else {
            throw QuickRecognitionError.imageEncodingFailed
        }

        let resolvedMaxDimension = maximumDimension ?? max(originalSize.width, originalSize.height)
        let scale = min(1, resolvedMaxDimension / max(originalSize.width, originalSize.height))
        let targetSize = CGSize(width: originalSize.width * scale, height: originalSize.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let jpegData = resizedImage.jpegData(compressionQuality: compressionQuality) else {
            throw QuickRecognitionError.imageEncodingFailed
        }

        return "data:image/jpeg;base64,\(jpegData.base64EncodedString())"
    }

    func generateCaption(
        imageDataURL: String,
        length: QuickCaptionLength,
        apiKey: String
    ) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw QuickRecognitionError.missingAPIKey
        }

        let payload: [String: Any] = [
            "image_url": imageDataURL,
            "length": length.rawValue
        ]

        let response = try await performRequest(
            path: "/caption",
            payload: payload,
            apiKey: apiKey
        )

        guard let caption = response["caption"] as? String else {
            throw QuickRecognitionError.invalidResponse
        }

        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw QuickRecognitionError.emptyResponse
        }
        return trimmed
    }

    func queryImage(
        imageDataURL: String,
        question: String,
        enforceSingleSentenceResponse: Bool,
        apiKey: String
    ) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw QuickRecognitionError.missingAPIKey
        }

        let formattedQuestion = enforceSingleSentenceResponse
            ? question + " respond with one sentence"
            : question

        let payload: [String: Any] = [
            "image_url": imageDataURL,
            "question": formattedQuestion
        ]

        let response = try await performRequest(
            path: "/query",
            payload: payload,
            apiKey: apiKey
        )

        guard let answer = response["answer"] as? String else {
            throw QuickRecognitionError.invalidResponse
        }

        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw QuickRecognitionError.emptyResponse
        }
        return trimmed
    }

    private func performRequest(
        path: String,
        payload: [String: Any],
        apiKey: String
    ) async throws -> [String: Any] {
        guard let url = URL(string: baseURL + path) else {
            throw QuickRecognitionError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Moondream-Auth")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw QuickRecognitionError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw QuickRecognitionError.badStatusCode(httpResponse.statusCode, body)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw QuickRecognitionError.invalidResponse
        }

        return json
    }
}

// MARK: - Apple Foundation Model (on-device)

enum AppleFoundationModelError: LocalizedError {
    case unsupportedOS
    case unavailable
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .unsupportedOS:
            return NSLocalizedString("applefm.error.unsupportedOS", comment: "")
        case .unavailable:
            return NSLocalizedString("applefm.error.unavailable", comment: "")
        case .emptyResponse:
            return NSLocalizedString("applefm.error.empty", comment: "")
        }
    }
}

/// Runs Quick Recognition through Apple's on-device Foundation Model
/// (`LanguageModelSession`), including image prompts.
final class AppleFoundationModelService {
    static let shared = AppleFoundationModelService()

    private var sessionStorage: Any?

    /// Whether the on-device system model is ready to use right now.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// Loads the model into memory ahead of the first request.
    func preload() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let session = currentSession() ?? LanguageModelSession()
            sessionStorage = session
            session.prewarm(promptPrefix: nil)
        }
        #endif
    }

    func generate(prompt: String, image: UIImage?) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else {
                throw AppleFoundationModelError.unavailable
            }
            let session = currentSession() ?? LanguageModelSession()
            sessionStorage = session

            let text: String
            if let cgImage = image?.cgImage {
                let response = try await session.respond {
                    prompt
                    Attachment(cgImage)
                }
                text = response.content
            } else {
                let response = try await session.respond(to: prompt)
                text = response.content
            }

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw AppleFoundationModelError.emptyResponse }
            return trimmed
        }
        #endif
        throw AppleFoundationModelError.unsupportedOS
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func currentSession() -> LanguageModelSession? {
        sessionStorage as? LanguageModelSession
    }
    #endif
}
