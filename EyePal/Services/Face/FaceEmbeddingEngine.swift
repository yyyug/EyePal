import CoreGraphics
import Foundation

enum FaceEmbeddingError: LocalizedError {
    case missingModel
    case preprocessingFailed
    case missingInputFeature(String)
    case missingOutputFeature(String)
    case invalidInputShape([Int])
    case invalidOutputShape([NSNumber])
    case invalidOutput
    case runtimeUnavailable(String)
    case noFaceDetected

    var errorDescription: String? {
        switch self {
        case .missingModel:
            return "arcface_fresh.onnx was not found in the app bundle."
        case .preprocessingFailed:
            return "The face image could not be converted into the embedding model input format."
        case .missingInputFeature(let name):
            return "The face embedding model is missing the expected input named \(name)."
        case .missingOutputFeature(let name):
            return "The face embedding model is missing the expected output named \(name)."
        case .invalidInputShape(let shape):
            return "The face embedding model expects a different input shape: \(shape)."
        case .invalidOutputShape(let shape):
            return "The face embedding model returned an unexpected output shape: \(shape)."
        case .invalidOutput:
            return "The face embedding model did not return a usable vector."
        case .runtimeUnavailable(let detail):
            return "ONNX Runtime could not run the face embedding model: \(detail)"
        case .noFaceDetected:
            return "No face detected in frame."
        }
    }
}

final class FaceEmbeddingEngine {
    private var sessionState: SessionState?
    private var cachedInputName: String?
    private var cachedOutputName: String?
    private var onLog: ((String) -> Void)?
    private let inferenceQueue = DispatchQueue(label: "com.eyepal.arcface.inference")

    func setLogger(_ logger: @escaping (String) -> Void) {
        onLog = logger
    }

    func load() {
        guard sessionState == nil else { return }
        guard let modelURL = Bundle.main.url(
            forResource: FaceModelContract.modelFilename,
            withExtension: FaceModelContract.modelExtension
        ) else {
            let msg = "[ArcFace] ERROR: Model file not found"
            NSLog("%@", msg)
            onLog?(msg)
            return
        }

        do {
            NSLog("[ArcFace] Loading model: \(modelURL.path)")
            let env = try ORTEnv(loggingLevel: .warning)
            let sessionOptions = try ORTSessionOptions()
            let session = try ORTSession(env: env, modelPath: modelURL.path, sessionOptions: sessionOptions)
            let inputNames = try session.inputNames()
            let outputNames = try session.outputNames()
            cachedInputName = inputNames.first
            cachedOutputName = outputNames.first
            let info = "[ArcFace] Inputs: \(inputNames) Outputs: \(outputNames)"
            NSLog("%@", info)
            onLog?(info)
            sessionState = SessionState(env: env, session: session)
        } catch {
            let msg = "[ArcFace] ERROR loading: \(error.localizedDescription)"
            NSLog("%@", msg)
            onLog?(msg)
        }
    }

    func embedding(for cgImage: CGImage) async throws -> [Float] {
        guard let sessionState else {
            throw FaceEmbeddingError.missingModel
        }

        let inputName = cachedInputName ?? FaceModelContract.inputName
        let outputName = cachedOutputName ?? FaceModelContract.outputName
        let inputData = try makeInputData(from: cgImage)
        let tensor = try makeTensor(from: inputData)

        let outputTensorData: Data
        let outputShape: [NSNumber]
        do {
            (outputTensorData, outputShape) = try await withCheckedThrowingContinuation { continuation in
                inferenceQueue.async {
                    do {
                        let result = try sessionState.session.run(
                            withInputs: [inputName: tensor],
                            outputNames: [outputName],
                            runOptions: nil
                        )
                        guard let outVal = result[outputName] else {
                            continuation.resume(throwing: FaceEmbeddingError.missingOutputFeature(outputName))
                            return
                        }
                        let data = try outVal.tensorData() as Data
                        let shape = try outVal.tensorTypeAndShapeInfo().shape
                        continuation.resume(returning: (data, shape))
                    } catch {
                        continuation.resume(throwing: FaceEmbeddingError.runtimeUnavailable(error.localizedDescription))
                    }
                }
            }
        } catch let error as FaceEmbeddingError {
            throw error
        } catch {
            throw FaceEmbeddingError.runtimeUnavailable(error.localizedDescription)
        }

        let actualDim = outputShape.last?.intValue ?? FaceModelContract.defaultEmbeddingSize
        let expectedBytes = actualDim * MemoryLayout<Float32>.stride
        let msg = "[ArcFace] Output: \(outputTensorData.count) bytes, shape=\(outputShape), dim=\(actualDim)"
        NSLog("%@", msg)
        onLog?(msg)

        guard outputTensorData.count >= expectedBytes else {
            throw FaceEmbeddingError.invalidOutputShape(outputShape)
        }

        let vector = try outputTensorData.toEmbeddingVector(shape: outputShape, expectedCount: actualDim)
        let embedding = normalized(vector)
        return embedding
    }

    private func makeTensor(from inputData: Data) throws -> ORTValue {
        let shape = FaceModelContract.inputShape.map(NSNumber.init(value:))
        do {
            return try ORTValue(
                tensorData: NSMutableData(data: inputData),
                elementType: ORTTensorElementDataType.float,
                shape: shape
            )
        } catch {
            throw FaceEmbeddingError.runtimeUnavailable(error.localizedDescription)
        }
    }

    private func makeInputData(from cgImage: CGImage) throws -> Data {
        let width = FaceModelContract.imageWidth
        let height = FaceModelContract.imageHeight
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel

        var rgbaBytes = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw FaceEmbeddingError.preprocessingFailed
        }
        guard let context = CGContext(
            data: &rgbaBytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw FaceEmbeddingError.preprocessingFailed
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let pixelCount = width * height
        var rChannel = [Float32](repeating: 0, count: pixelCount)
        var gChannel = [Float32](repeating: 0, count: pixelCount)
        var bChannel = [Float32](repeating: 0, count: pixelCount)
        var idx = 0
        for y in 0..<height {
            for x in 0..<width {
                let sourceIndex = (y * bytesPerRow) + (x * bytesPerPixel)
                rChannel[idx] = normalize(rgbaBytes[sourceIndex])
                gChannel[idx] = normalize(rgbaBytes[sourceIndex + 1])
                bChannel[idx] = normalize(rgbaBytes[sourceIndex + 2])
                idx += 1
            }
        }
        let floats = rChannel + gChannel + bChannel

        guard floats.count == FaceModelContract.inputShape.reduce(1, *) else {
            throw FaceEmbeddingError.invalidInputShape(FaceModelContract.inputShape)
        }

        return floats.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }

    private func normalize(_ value: UInt8) -> Float32 {
        (Float32(value) - FaceModelContract.normalizationOffset) / FaceModelContract.normalizationScale
    }
}

private struct SessionState {
    let env: ORTEnv
    let session: ORTSession
}

private func normalized(_ values: [Float]) -> [Float] {
    let magnitude = sqrt(values.reduce(0) { $0 + ($1 * $1) })
    guard magnitude > 0 else { return values }
    return values.map { $0 / magnitude }
}

private extension Data {
    func toEmbeddingVector(shape: [NSNumber], expectedCount: Int) throws -> [Float] {
        guard let lastDimension = shape.last?.intValue, lastDimension == expectedCount else {
            throw FaceEmbeddingError.invalidOutputShape(shape)
        }

        let valueCount = count / MemoryLayout<Float32>.stride
        guard valueCount >= expectedCount else {
            throw FaceEmbeddingError.invalidOutput
        }

        let values: [Float] = withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) -> [Float] in
            let floats = rawBuffer.bindMemory(to: Float32.self)
            return (0..<expectedCount).map { Float(floats[$0]) }
        }
        return values
    }
}
