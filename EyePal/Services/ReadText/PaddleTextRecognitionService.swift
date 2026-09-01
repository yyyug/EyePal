import CoreGraphics
import Foundation
import UIKit

/// Wraps the PaddleOCR engine (native ONNX Runtime deployment) behind the same
/// observation-shaped interface as ``TextRecognitionService`` so callers can
/// switch OCR engines without changing their consuming code.
///
/// The actor isolates the lazily-created ``OCREngine`` (and its load state) so
/// model loading and inference never race across concurrent requests.
actor PaddleTextRecognitionService {
    private var engine: OCREngine?
    private var loadErrorLogged = false

    /// Kicks off model loading in the background if the engine is not loaded yet.
    func prepareIfNeeded() {
        Task { [weak self] in
            _ = await self?.readyEngine()
        }
    }

    /// Runs PaddleOCR on a `UIImage`, delivering the combined recognized text.
    func process(
        image: UIImage,
        completion: @escaping @MainActor (TextRecognitionObservation?) -> Void
    ) {
        Task { [weak self] in
            await self?.performProcess(image: image, completion: completion)
        }
    }

    private func performProcess(
        image: UIImage,
        completion: @escaping @MainActor (TextRecognitionObservation?) -> Void
    ) async {
        guard let cgImage = image.cgImage else {
            Task { @MainActor in completion(nil) }
            return
        }
        guard let engine = await readyEngine() else {
            Task { @MainActor in completion(nil) }
            return
        }
        do {
            let run = try await engine.run(cgImage)
            let text = run.results.map(\.text).joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let observation = text.isEmpty
                ? nil
                : TextRecognitionObservation(text: text, languageCode: nil)
            Task { @MainActor in completion(observation) }
        } catch {
            Task { @MainActor in completion(nil) }
        }
    }

    private func readyEngine() async -> OCREngine? {
        if let engine {
            return engine
        }
        let manager = ORTSessionManager()
        do {
            try await manager.loadModels(executionProvider: .cpu)
            let loaded = try OCREngine(sessionManager: manager)
            engine = loaded
            return loaded
        } catch {
            engine = nil
            if !loadErrorLogged {
                loadErrorLogged = true
                NSLog("PaddleOCR engine failed to load: \(error.localizedDescription)")
            }
            return nil
        }
    }
}
