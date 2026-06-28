import AVFoundation
import CoreImage
import UIKit
import Vision

struct FaceMatch: Equatable {
    let name: String
    let confidence: Float
}

final class FaceRecognitionService {
    private struct CandidateMatch {
        let profile: FaceProfile
        let confidence: Float
    }

    private let embeddingEngine = FaceEmbeddingEngine()
    private let faceStore = FaceStore()
    private let processingQueue = DispatchQueue(label: "com.eyepals.face.recognition")
    private let context = CIContext()
    var onLog: ((String) -> Void)? {
        didSet { embeddingEngine.setLogger { [weak self] msg in self?.onLog?(msg) } }
    }

    private var isProcessing = false
    private var profiles: [FaceProfile] = []
    private var lastUnknownSuggestionDate = Date.distantPast
    private var consecutiveUnknownFrames = 0
    private var pendingKnownMatch: CandidateMatch?
    private var consecutiveKnownFrames = 0
    private var pendingUnknownEmbeddings: [[Float]] = []
    private var pendingUnknownJPEGData: Data?

    var recognitionThreshold: Float = 0.95
    var suggestionFrameThreshold = 6
    var minimumSuggestionInterval: TimeInterval = 10
    var knownMatchFrameThreshold = 1
    var minimumTopMatchMargin: Float = 0.02
    var borderlineKnownThreshold: Float = 0.90
    var enrollmentSampleTarget = 4
    var minimumEnrollmentSamples = 3

    func loadProfiles() async throws -> [FaceProfile] {
        let loaded = try await faceStore.loadProfiles()
        profiles = loaded
        return loaded
    }

    func loadEmbeddingEngine() {
        embeddingEngine.load()
    }

    func process(
        sampleBuffer: CMSampleBuffer,
        completion: @escaping @MainActor (FaceMatch?, FaceSuggestion?) -> Void,
        onSampleCollected: ((Int, Int) -> Void)? = nil,
        onLog: ((String) -> Void)? = nil
    ) {
        processingQueue.async {
            guard !self.isProcessing else { return }
            self.isProcessing = true

            Task {
                defer {
                    self.processingQueue.async {
                        self.isProcessing = false
                    }
                }

                do {
                    let faceImage = try self.extractPrimaryFace(from: sampleBuffer)
                    let embedding = try await self.embeddingEngine.embedding(for: faceImage)
                    let rankedCandidates = self.rankedCandidates(for: embedding)

                    if let match = self.confirmedMatch(for: rankedCandidates) {
                        self.resetUnknownTracking()
                        await MainActor.run { onLog?("Matched: \(match.name) \(String(format: "%.3f", match.confidence))") }
                        await completion(match, nil)
                    } else {
                        if rankedCandidates.isEmpty {
                            await MainActor.run { onLog?("Face detected, no saved profiles to match") }
                        } else if let best = rankedCandidates.first {
                            let second = rankedCandidates.count > 1 ? rankedCandidates[1].confidence : 0
                            let margin = best.confidence - second
                            let reason = best.confidence < self.recognitionThreshold
                                ? "below threshold"
                                : (rankedCandidates.count > 1 && margin < self.minimumTopMatchMargin
                                    ? "margin too small (\(String(format: "%.3f", margin)) < \(String(format: "%.3f", self.minimumTopMatchMargin)))"
                                    : "frame threshold")
                            let msg = "No match: \(best.profile.name) \(String(format: "%.3f", best.confidence)) [\(reason)]"
                            await MainActor.run { onLog?(msg) }
                        }
                        let suggestion = self.handleUnknownFace(
                            embedding: embedding,
                            faceImage: faceImage,
                            rankedCandidates: rankedCandidates,
                            onSampleCollected: onSampleCollected
                        )
                        await completion(nil, suggestion)
                    }
                } catch {
                    if case FaceEmbeddingError.noFaceDetected = error {
                        // silently skip — no face in frame
                    } else {
                        await MainActor.run { onLog?("Error: \(error.localizedDescription)") }
                    }
                    await completion(nil, nil)
                }
            }
        }
    }

    func saveFace(name: String, suggestion: FaceSuggestion) async throws -> [FaceProfile] {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return profiles }

        let sampleEmbeddings = suggestion.sampleEmbeddings.filter { !$0.isEmpty }
        guard !sampleEmbeddings.isEmpty else { return profiles }

        var profile = FaceProfile(name: trimmedName, sampleEmbeddings: sampleEmbeddings)
        if let jpegData = suggestion.jpegData {
            profile.sampleImageFilename = try await faceStore.saveImage(jpegData, for: profile.id)
        }
        profiles.append(profile)
        try await faceStore.saveProfiles(profiles)
        resetUnknownTracking()
        return profiles
    }

    func deleteProfile(id: UUID) async throws -> [FaceProfile] {
        profiles.removeAll { $0.id == id }
        try await faceStore.saveProfiles(profiles)
        return profiles
    }

    private func extractPrimaryFace(from sampleBuffer: CMSampleBuffer) throws -> CGImage {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw FaceEmbeddingError.invalidOutput
        }

        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        try handler.perform([request])

        guard let observation = (request.results as? [VNFaceObservation])?.max(by: {
            $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
        }) else {
            throw FaceEmbeddingError.noFaceDetected
        }

        guard let landmarks = observation.landmarks,
              let leftEye = landmarks.leftEye?.normalizedPoints,
              let rightEye = landmarks.rightEye?.normalizedPoints,
              let nose = landmarks.nose?.normalizedPoints,
              let outerLips = landmarks.outerLips?.normalizedPoints else {
            throw FaceEmbeddingError.noFaceDetected
        }

        let imgW = observation.boundingBox.width
        let imgH = observation.boundingBox.height
        let imgX = observation.boundingBox.origin.x
        let imgY = observation.boundingBox.origin.y

        let eyeCenter = CGPoint(
            x: imgX + (leftEye[0].x + rightEye[0].x) / 2 * imgW,
            y: imgY + (leftEye[0].y + rightEye[0].y) / 2 * imgH
        )

        let eyeDistance = sqrt(
            pow((leftEye[0].x - rightEye[0].x) * imgW, 2) +
            pow((leftEye[0].y - rightEye[0].y) * imgH, 2)
        )
        let faceSize = eyeDistance * 2.2

        let pixelW = CVPixelBufferGetWidth(pixelBuffer)
        let pixelH = CVPixelBufferGetHeight(pixelBuffer)

        let cropSize = max(faceSize * Double(pixelW), faceSize * Double(pixelH)) / max(Double(pixelW), Double(pixelH))
        let cropRect = CGRect(
            x: eyeCenter.x * Double(pixelW) - cropSize / 2,
            y: eyeCenter.y * Double(pixelH) - cropSize / 2,
            width: cropSize,
            height: cropSize
        ).intersection(CGRect(x: 0, y: 0, width: Double(pixelW), height: Double(pixelH)))

        guard let sourceCGImage = context.createCGImage(
            CIImage(cvPixelBuffer: pixelBuffer).oriented(.right),
            from: CIImage(cvPixelBuffer: pixelBuffer).oriented(.right).extent
        ) else {
            throw FaceEmbeddingError.invalidOutput
        }

        guard let croppedCG = sourceCGImage.cropping(to: cropRect) else {
            throw FaceEmbeddingError.invalidOutput
        }

        let outputSize = 112
        guard let outputContext = CGContext(
            data: nil,
            width: outputSize,
            height: outputSize,
            bitsPerComponent: 8,
            bytesPerRow: outputSize * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw FaceEmbeddingError.preprocessingFailed
        }

        outputContext.interpolationQuality = .high
        outputContext.draw(croppedCG, in: CGRect(x: 0, y: 0, width: outputSize, height: outputSize))

        guard let result = outputContext.makeImage() else {
            throw FaceEmbeddingError.invalidOutput
        }

        return result
    }

    private func confirmedMatch(for rankedCandidates: [CandidateMatch]) -> FaceMatch? {
        guard let candidate = acceptedKnownCandidate(from: rankedCandidates) else {
            pendingKnownMatch = nil
            consecutiveKnownFrames = 0
            return nil
        }

        if pendingKnownMatch?.profile.id == candidate.profile.id {
            consecutiveKnownFrames += 1
            pendingKnownMatch = candidate
        } else {
            pendingKnownMatch = candidate
            consecutiveKnownFrames = 1
        }

        guard consecutiveKnownFrames >= knownMatchFrameThreshold else {
            return nil
        }

        return FaceMatch(name: candidate.profile.name, confidence: candidate.confidence)
    }

    private func rankedCandidates(for embedding: [Float]) -> [CandidateMatch] {
        profiles
            .compactMap { profile in
                let validEmbeddings = profile.sampleEmbeddings.filter { !$0.isEmpty }
                guard !validEmbeddings.isEmpty else { return nil }

                let confidence = validEmbeddings
                    .map { cosineSimilarity(embedding, $0) }
                    .max() ?? -1

                return CandidateMatch(profile: profile, confidence: confidence)
            }
            .sorted { $0.confidence > $1.confidence }
    }

    private func acceptedKnownCandidate(from rankedCandidates: [CandidateMatch]) -> CandidateMatch? {
        guard let bestCandidate = rankedCandidates.first,
              bestCandidate.confidence >= recognitionThreshold else {
            return nil
        }

        if rankedCandidates.count > 1 {
            let secondBestConfidence = rankedCandidates[1].confidence
            guard (bestCandidate.confidence - secondBestConfidence) >= minimumTopMatchMargin else {
                return nil
            }
        }

        return bestCandidate
    }

    private func handleUnknownFace(
        embedding: [Float],
        faceImage: CGImage,
        rankedCandidates: [CandidateMatch],
        onSampleCollected: ((Int, Int) -> Void)? = nil
    ) -> FaceSuggestion? {
        pendingKnownMatch = nil
        consecutiveKnownFrames = 0

        if let bestCandidate = rankedCandidates.first,
           bestCandidate.confidence >= borderlineKnownThreshold {
            resetUnknownTracking()
            return nil
        }

        consecutiveUnknownFrames += 1
        collectUnknownSample(embedding: embedding, faceImage: faceImage)

        if let onSampleCollected {
            let current = pendingUnknownEmbeddings.count
            let target = enrollmentSampleTarget
            onSampleCollected(current, target)
        }

        guard consecutiveUnknownFrames >= suggestionFrameThreshold else {
            return nil
        }

        guard pendingUnknownEmbeddings.count >= minimumEnrollmentSamples else {
            return nil
        }

        let now = Date()
        guard now.timeIntervalSince(lastUnknownSuggestionDate) >= minimumSuggestionInterval else {
            return nil
        }

        lastUnknownSuggestionDate = now
        let suggestion = FaceSuggestion(
            sampleEmbeddings: Array(pendingUnknownEmbeddings.prefix(enrollmentSampleTarget)),
            jpegData: pendingUnknownJPEGData
        )
        resetUnknownTracking()
        return suggestion
    }

    private func collectUnknownSample(embedding: [Float], faceImage: CGImage) {
        if pendingUnknownEmbeddings.count < enrollmentSampleTarget {
            let isDistinctEnough = pendingUnknownEmbeddings.allSatisfy { savedEmbedding in
                cosineSimilarity(savedEmbedding, embedding) < 0.995
            }

            if isDistinctEnough || pendingUnknownEmbeddings.isEmpty {
                pendingUnknownEmbeddings.append(embedding)
            } else if pendingUnknownEmbeddings.count < minimumEnrollmentSamples {
                pendingUnknownEmbeddings.append(embedding)
            }
        }

        if pendingUnknownJPEGData == nil {
            pendingUnknownJPEGData = UIImage(cgImage: faceImage).jpegData(compressionQuality: 0.8)
        }
    }

    private func resetUnknownTracking() {
        consecutiveUnknownFrames = 0
        pendingUnknownEmbeddings = []
        pendingUnknownJPEGData = nil
    }
}

private func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Float {
    guard lhs.count == rhs.count, !lhs.isEmpty else { return -1 }
    return zip(lhs, rhs).reduce(0) { $0 + ($1.0 * $1.1) }
}
