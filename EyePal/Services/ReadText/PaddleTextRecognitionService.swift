import CoreGraphics
import Foundation
import UIKit

/// Wraps the PaddleOCR engine (native ONNX Runtime deployment) behind the same
/// observation-shaped interface as ``TextRecognitionService`` so callers can
/// switch OCR engines without changing their consuming code.
///
/// All entry points dispatch through a private serial queue; the lazily-created
/// ``OCREngine`` is loaded once and reused for subsequent requests.
final class PaddleTextRecognitionService {
    private let processingQueue = DispatchQueue(label: "com.eyepals.text.recognition.paddle")
    private var engine: OCREngine?
    private var loadErrorLogged = false

    /// Kicks off model loading in the background if the engine is not loaded yet.
    func prepareIfNeeded() {
        processingQueue.async { [weak self] in
            guard let self else { return }
            Task { _ = await self.readyEngine() }
        }
    }

    /// Runs PaddleOCR on a `UIImage`, delivering the combined recognized text.
    func process(
        image: UIImage,
        completion: @escaping @MainActor (TextRecognitionObservation?) -> Void
    ) {
        processingQueue.async { [weak self] in
            guard let self else {
                Task { @MainActor in completion(nil) }
                return
            }
            guard let cgImage = image.cgImage else {
                Task { @MainActor in completion(nil) }
                return
            }
            Task {
                guard let engine = await self.readyEngine() else {
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
        }
    }

    private func readyEngine() async -> OCREngine? {
        if engine != nil {
            return engine
        }

        let manager = ORTSessionManager()
        do {
            try await manager.loadModels(executionProvider: .cpu)
            let loaded = try OCREngine(sessionManager: manager)
            engine = loaded
            OcrEngineLogStore.shared.add("PaddleOCR engine loaded successfully")
            return loaded
        } catch {
            engine = nil
            if !loadErrorLogged {
                loadErrorLogged = true
                NSLog("PaddleOCR engine failed to load: \(error.localizedDescription)")
            }
            OcrEngineLogStore.shared.add("PaddleOCR engine load failed: \(error.localizedDescription)")
            return nil
        }
    }
}
