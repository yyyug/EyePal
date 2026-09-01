import CoreGraphics
import Foundation
import UIKit

/// Wraps the PaddleOCR engine (native ONNX Runtime deployment) behind the same
/// observation-shaped interface as ``TextRecognitionService`` so callers can
/// switch OCR engines without changing their consuming code.
final class PaddleTextRecognitionService {
    private let processingQueue = DispatchQueue(label: "com.eyepals.text.recognition.paddle")
    private let loadLock = NSLock()
    private var engine: OCREngine?
    private var loadErrorLogged = false

    /// Begins loading the PaddleOCR models in the background if they are not already loaded.
    func prepareIfNeeded() {
        processingQueue.async { [weak self] in
            _ = self?.readyEngine()
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

    private func currentEngine() -> OCREngine? {
        loadLock.lock()
        defer { loadLock.unlock() }
        return engine
    }

    private func readyEngine() async -> OCREngine? {
        if let engine = currentEngine() { return engine }

        let manager = ORTSessionManager()
        do {
            try await manager.loadModels(executionProvider: .cpu)
            let loaded = try OCREngine(sessionManager: manager)
            loadLock.lock()
            engine = loaded
            loadLock.unlock()
            return loaded
        } catch {
            loadLock.lock()
            engine = nil
            loadLock.unlock()
            if !loadErrorLogged {
                loadErrorLogged = true
                NSLog("PaddleOCR engine failed to load: \(error.localizedDescription)")
            }
            return nil
        }
    }
}
