import Foundation
import LiteRTLM
import UIKit

enum GemmaRecognitionError: LocalizedError {
    case noModelDownloaded
    case imageEncodingFailed
    case emptyResponse
    case engineFailure(String)

    var errorDescription: String? {
        switch self {
        case .noModelDownloaded:
            return NSLocalizedString("gemma.error.noModel", comment: "")
        case .imageEncodingFailed:
            return NSLocalizedString("gemma.error.imageEncoding", comment: "")
        case .emptyResponse:
            return NSLocalizedString("gemma.error.emptyResponse", comment: "")
        case .engineFailure(let message):
            return message
        }
    }
}

final class GemmaTextRecognitionService {
    private let modelManager: GemmaModelManager
    private var engine: Engine?
    private var conversation: Conversation?

    init(modelManager: GemmaModelManager) {
        self.modelManager = modelManager
    }

    func prepareIfNeeded() {
        guard let modelPath = modelManager.downloadedModelURL() else { return }
        Task { _ = try? await readyEngine(modelURL: modelPath) }
    }

    func canRun() -> Bool {
        modelManager.isAnyModelDownloaded
    }

    func generateCaption(image: UIImage, length: QuickCaptionLength) async throws -> String {
        let prompt: String
        switch length {
        case .short:
            prompt = "Describe this image in one short sentence."
        case .normal:
            prompt = "Describe this image in 1 or 2 concise sentences."
        case .long:
            prompt = "Describe this image in detail, in a few sentences."
        }
        return try await run(prompt: prompt, image: image)
    }

    func queryImage(image: UIImage, question: String, enforceSingleSentenceResponse: Bool) async throws -> String {
        let prompt = enforceSingleSentenceResponse
            ? question + " Respond with one sentence."
            : question
        return try await run(prompt: prompt, image: image)
    }

    private func run(prompt: String, image: UIImage) async throws -> String {
        guard let modelPath = modelManager.downloadedModelURL() else {
            throw GemmaRecognitionError.noModelDownloaded
        }

        let tempURL = try writeImageToTempFile(image)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        _ = try await readyEngine(modelURL: modelPath)
        guard let conversation else {
            throw GemmaRecognitionError.engineFailure(NSLocalizedString("gemma.error.engine", comment: ""))
        }
        let message = Message(contents: [
            Content.imageFile(tempURL.path),
            Content.text(prompt)
        ])

        let response = try await conversation.sendMessage(message)

        let trimmed = response.toString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GemmaRecognitionError.emptyResponse
        }
        return trimPrefixWhitespace(trimmed)
    }

    private func readyEngine(modelURL: URL) async throws -> Engine {
        if let engine, conversation != nil {
            return engine
        }
        let modelPath = modelURL.path
        let cacheDir = NSTemporaryDirectory()
        let config = try EngineConfig(
            modelPath: modelPath,
            backend: .gpu,
            visionBackend: .cpu(),
            audioBackend: .cpu(),
            maxNumTokens: 256,
            cacheDir: cacheDir
        )
        let engine = Engine(engineConfig: config)
        try await engine.initialize()
        self.engine = engine
        conversation = try await engine.createConversation()
        return engine
    }

    private func writeImageToTempFile(_ image: UIImage) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            throw GemmaRecognitionError.imageEncodingFailed
        }
        try data.write(to: url)
        return url
    }

    private func trimPrefixWhitespace(_ text: String) -> String {
        text
    }
}
