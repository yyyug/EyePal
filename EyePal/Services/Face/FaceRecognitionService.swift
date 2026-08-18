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

    var recognitionThreshold: Float = 0.65
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
        logInterProfileSimilarities()
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

        if let idx = profiles.firstIndex(where: { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }) {
            profiles[idx].sampleEmbeddings.append(contentsOf: sampleEmbeddings)
            if let jpegData = suggestion.jpegData {
                profiles[idx].sampleImageFilename = try await faceStore.saveImage(jpegData, for: profiles[idx].id)
            }
            try await faceStore.saveProfiles(profiles)
            logProfileSimilarityDiagnostics(newProfile: profiles[idx])
            resetUnknownTracking()
            return profiles
        }

        let newMean = meanEmbedding(sampleEmbeddings)
        if !newMean.isEmpty {
            for existing in profiles {
                let existingMean = meanEmbedding(existing.sampleEmbeddings)
                guard !existingMean.isEmpty else { continue }
                let sim = cosineSimilarity(newMean, existingMean)
                if sim >= 0.60 {
                    onLog?("Duplicate save blocked: \(trimmedName) vs \(existing.name) similarity \(String(format: "%.4f", sim))")
                    return profiles
                }
            }
        }

        var profile = FaceProfile(name: trimmedName, sampleEmbeddings: sampleEmbeddings)
        if let jpegData = suggestion.jpegData {
            profile.sampleImageFilename = try await faceStore.saveImage(jpegData, for: profile.id)
        }
        profiles.append(profile)
        try await faceStore.saveProfiles(profiles)
        logProfileSimilarityDiagnostics(newProfile: profile)
        resetUnknownTracking()
        return profiles
    }

    func deleteProfile(id: UUID) async throws -> [FaceProfile] {
        profiles.removeAll { $0.id == id }
        try await faceStore.saveProfiles(profiles)
        return profiles
    }

    private static let referenceLandmarks: [(x: Double, y: Double)] = [
        (38.2946, 51.6963), // left eye
        (73.5318, 51.5014), // right eye
        (56.0252, 71.7366), // nose
        (41.5493, 92.3655), // left mouth corner
        (70.7299, 92.2041)  // right mouth corner
    ]

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

        guard let landmarks = observation.landmarks else {
            throw FaceEmbeddingError.noFaceDetected
        }

        let bb = observation.boundingBox
        let pixelW = CVPixelBufferGetWidth(pixelBuffer)
        let pixelH = CVPixelBufferGetHeight(pixelBuffer)

        func toPixel(_ points: [CGPoint]?) -> CGPoint? {
            guard let pts = points, !pts.isEmpty else { return nil }
            let cx = pts.map(\.x).reduce(0, +) / Double(pts.count)
            let cy = pts.map(\.y).reduce(0, +) / Double(pts.count)
            return CGPoint(x: bb.origin.x + cx * bb.width, y: bb.origin.y + cy * bb.height)
        }

        func outerLipsCorner(_ pickLeft: Bool) -> CGPoint? {
            guard let pts = landmarks.outerLips?.normalizedPoints, pts.count >= 2 else { return nil }
            let sorted = pts.sorted { pickLeft ? ($0.x < $1.x) : ($0.x > $1.x) }
            let pt = sorted[0]
            return CGPoint(x: bb.origin.x + pt.x * bb.width, y: bb.origin.y + pt.y * bb.height)
        }

        guard let lePx = toPixel(landmarks.leftEye?.normalizedPoints),
              let rePx = toPixel(landmarks.rightEye?.normalizedPoints),
              let nosePx = toPixel(landmarks.nose?.normalizedPoints),
              let lmPx = outerLipsCorner(true),
              let rmPx = outerLipsCorner(false) else {
            throw FaceEmbeddingError.noFaceDetected
        }

        let srcPoints: [(Double, Double)] = [
            (lePx.x * Double(pixelW), lePx.y * Double(pixelH)),
            (rePx.x * Double(pixelW), rePx.y * Double(pixelH)),
            (nosePx.x * Double(pixelW), nosePx.y * Double(pixelH)),
            (lmPx.x * Double(pixelW), lmPx.y * Double(pixelH)),
            (rmPx.x * Double(pixelW), rmPx.y * Double(pixelH))
        ]

        guard let affine = computeAffineAffine(srcPoints: srcPoints, dstPoints: Self.referenceLandmarks) else {
            throw FaceEmbeddingError.preprocessingFailed
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

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
        let affineFilter = CIFilter(name: "CIAffineTransform")!
        affineFilter.setValue(ciImage, forKey: kCIInputImageKey)
        let transform = CGAffineTransform(
            a: CGFloat(affine[0]), b: CGFloat(affine[2]),
            c: CGFloat(affine[1]), d: CGFloat(affine[3]),
            tx: CGFloat(affine[4]), ty: CGFloat(affine[5])
        )
        affineFilter.setValue(NSValue(cgAffineTransform: transform), forKey: "inputTransform")

        guard let alignedCI = affineFilter.outputImage else {
            throw FaceEmbeddingError.preprocessingFailed
        }

        let alignedCrop = alignedCI.cropped(to: CGRect(x: 0, y: 0, width: 112, height: 112))
        guard let cgImage = context.createCGImage(alignedCrop, from: alignedCrop.extent) else {
            throw FaceEmbeddingError.preprocessingFailed
        }

        outputContext.interpolationQuality = .high
        outputContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: outputSize, height: outputSize))

        guard let result = outputContext.makeImage() else {
            throw FaceEmbeddingError.preprocessingFailed
        }

        return result
    }

    private func computeAffineAffine(srcPoints: [(Double, Double)], dstPoints: [(Double, Double)]) -> [Double]? {
        guard srcPoints.count == 5, dstPoints.count == 5 else { return nil }
        let n = 5
        var A = [[Double]](repeating: [Double](repeating: 0, count: 6), count: 2 * n)
        var b = [Double](repeating: 0, count: 2 * n)
        for i in 0..<n {
            let (sx, sy) = srcPoints[i]
            let (dx, dy) = dstPoints[i]
            A[2 * i] = [sx, sy, 1, 0, 0, 0]
            A[2 * i + 1] = [0, 0, 0, sx, sy, 1]
            b[2 * i] = dx
            b[2 * i + 1] = dy
        }
        let At = (0..<6).map { j in (0..<2 * n).map { i in A[i][j] } }
        var AtA = [[Double]](repeating: [Double](repeating: 0, count: 6), count: 6)
        var Atb = [Double](repeating: 0, count: 6)
        for i in 0..<6 {
            for j in 0..<6 {
                AtA[i][j] = (0..<2 * n).reduce(0) { $0 + At[i][$1] * A[$1][j] }
            }
            Atb[i] = (0..<2 * n).reduce(0) { $0 + At[i][$1] * b[$1] }
        }
        return solveLinearSystem(AtA, Atb)
    }

    private func solveLinearSystem(_ A: [[Double]], _ b: [Double]) -> [Double]? {
        let n = b.count
        var a = A; var x = b
        for i in 0..<n {
            var maxRow = i
            for k in (i + 1)..<n where abs(a[k][i]) > abs(a[maxRow][i]) { maxRow = k }
            a.swapAt(i, maxRow); x.swapAt(i, maxRow)
            guard abs(a[i][i]) > 1e-12 else { return nil }
            for k in (i + 1)..<n {
                let f = a[k][i] / a[i][i]
                for j in i..<n { a[k][j] -= f * a[i][j] }
                x[k] -= f * x[i]
            }
        }
        var result = [Double](repeating: 0, count: n)
        for i in stride(from: n - 1, through: 0, by: -1) {
            result[i] = (x[i] - (i + 1..<n).reduce(0) { $0 + a[i][$1] * result[$1] }) / a[i][i]
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

                let scores = validEmbeddings.map { cosineSimilarity(embedding, $0) }
                let confidence = scores.reduce(0, +) / Float(scores.count)

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

    private func logProfileSimilarityDiagnostics(newProfile: FaceProfile) {
        let newMean = meanEmbedding(newProfile.sampleEmbeddings)
        guard !newMean.isEmpty else { return }

        for existing in profiles where existing.id != newProfile.id {
            let existingMean = meanEmbedding(existing.sampleEmbeddings)
            guard !existingMean.isEmpty else { continue }
            let sim = cosineSimilarity(newMean, existingMean)
            let msg = "Diagnostics: \(newProfile.name) vs \(existing.name) similarity \(String(format: "%.4f", sim))"
            onLog?(msg)
            if sim >= 0.60 {
                onLog?("WARNING: \(newProfile.name) vs \(existing.name) similarity \(String(format: "%.4f", sim)) >= 0.60 — high cross-profile similarity!")
            }
        }
    }

    private func logInterProfileSimilarities() {
        guard profiles.count >= 2 else { return }
        for i in 0..<profiles.count {
            for j in (i + 1)..<profiles.count {
                let meanA = meanEmbedding(profiles[i].sampleEmbeddings)
                let meanB = meanEmbedding(profiles[j].sampleEmbeddings)
                guard !meanA.isEmpty, !meanB.isEmpty else { continue }
                let sim = cosineSimilarity(meanA, meanB)
                let msg = "Inter-profile: \(profiles[i].name) vs \(profiles[j].name) similarity \(String(format: "%.4f", sim))"
                onLog?(msg)
            }
        }
    }

    private func meanEmbedding(_ embeddings: [[Float]]) -> [Float] {
        let valid = embeddings.filter { !$0.isEmpty }
        guard !valid.isEmpty, let dim = valid.first?.count else { return [] }
        var result = [Float](repeating: 0, count: dim)
        for emb in valid {
            for i in 0..<dim { result[i] += emb[i] }
        }
        let count = Float(valid.count)
        for i in 0..<dim { result[i] /= count }
        let mag = sqrt(result.reduce(0) { $0 + $1 * $1 })
        guard mag > 0 else { return result }
        return result.map { $0 / mag }
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
