import CoreGraphics
import Foundation
import Vision

enum FaceEmbeddingError: LocalizedError {
    case noFaceDetected
    case featurePrintGenerationFailed
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .noFaceDetected:
            return "No face detected in frame."
        case .featurePrintGenerationFailed:
            return "Could not generate a face feature print from the image."
        case .invalidOutput:
            return "The face feature print was empty or invalid."
        }
    }
}

final class FaceEmbeddingEngine {
    private var onLog: ((String) -> Void)?
    private let inferenceQueue = DispatchQueue(label: "com.eyepal.vision.faceprint")

    func setLogger(_ logger: @escaping (String) -> Void) {
        onLog = logger
    }

    func load() {
        // No model to load — Vision's face feature print runs on-device without setup.
    }

    func embedding(for cgImage: CGImage) async throws -> [Float] {
        try await withCheckedThrowingContinuation { continuation in
            inferenceQueue.async {
                do {
                    let request = VNGenerateImageFeaturePrintRequest()
                    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                    try handler.perform([request])

                    guard let featurePrint = request.results?.first else {
                        continuation.resume(throwing: FaceEmbeddingError.featurePrintGenerationFailed)
                        return
                    }

                    let data = featurePrint.data
                    let count = data.count / MemoryLayout<Float>.size
                    guard count > 0 else {
                        continuation.resume(throwing: FaceEmbeddingError.invalidOutput)
                        return
                    }

                    var floats = [Float](repeating: 0, count: count)
                    _ = floats.withUnsafeMutableBytes { data.copyBytes(to: $0) }
                    continuation.resume(returning: floats)
                } catch {
                    continuation.resume(throwing: FaceEmbeddingError.featurePrintGenerationFailed)
                }
            }
        }
    }
}
