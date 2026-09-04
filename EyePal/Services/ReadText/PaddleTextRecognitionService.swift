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
            // `image.cgImage` ignores the UIImage's orientation (camera frames are often rotated),
            // so bake the orientation in to get an upright image. Otherwise PaddleOCR det can't
            // find upright text (unlike ML Kit, which reads orientation from the sample buffer).
            guard let cgImage = Self.uprightCGImage(from: image) else {
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
                    NSLog("PaddleOCR engine.run error: \(error.localizedDescription)")
                    OcrEngineLogStore.shared.add("PaddleOCR error: \(error.localizedDescription)")
                    Task { @MainActor in completion(nil) }
                }
            }
        }
    }

    /// Produces an upright `CGImage` from a `UIImage`, honoring its `imageOrientation`.
    private static func uprightCGImage(from image: UIImage) -> CGImage? {
        guard image.imageOrientation == .up, let cg = image.cgImage else {
            // Fall back to rendering (and flipping Y if needed) when not already upright.
            let size = image.size
            guard size.width > 0, size.height > 0 else { return nil }
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(size: size, format: format)
            let rendered = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
            return rendered.cgImage
        }
        return cg
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
