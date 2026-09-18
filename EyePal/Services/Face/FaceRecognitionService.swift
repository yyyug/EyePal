import AVFoundation
import CoreImage
import UIKit
import Vision

private enum FaceConfig {
    static let recognitionThreshold: Float = 0.60
    static let suggestionFrameThreshold = 6
    static let minimumSuggestionInterval: TimeInterval = 10
    static let knownMatchFrameThreshold = 1
    static let minimumTopMatchMargin: Float = 0.05
    static let borderlineKnownThreshold: Float = 0.85
    static let enrollmentSampleTarget = 1
    static let minimumEnrollmentSamples = 1
    static let enrollmentMinimumFaceSize: CGFloat = 80
    static let duplicateWarningThreshold: Float = 0.60
    static let sampleDistinctSimilarity: Float = 0.995
    static let cropPadding: CGFloat = 0.15
}

struct FaceMatch: Equatable {
    let id: UUID
    let name: String
    let voiceNoteFilename: String?
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
    private var enrollmentSuggested = false

    var recognitionThreshold: Float = FaceConfig.recognitionThreshold
    var suggestionFrameThreshold = FaceConfig.suggestionFrameThreshold
    var minimumSuggestionInterval: TimeInterval = FaceConfig.minimumSuggestionInterval
    var knownMatchFrameThreshold = FaceConfig.knownMatchFrameThreshold
    var minimumTopMatchMargin: Float = FaceConfig.minimumTopMatchMargin
    var borderlineKnownThreshold: Float = FaceConfig.borderlineKnownThreshold
    var enrollmentSampleTarget = FaceConfig.enrollmentSampleTarget
    var minimumEnrollmentSamples = FaceConfig.minimumEnrollmentSamples

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
                    let embedding: [Float]
                    do {
                        embedding = try await self.embeddingEngine.embedding(for: faceImage)
                    } catch {
                        await MainActor.run { onLog?("[Face] Embedding engine error: \(error.localizedDescription)") }
                        throw error
                    }
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
                        await MainActor.run { onLog?("[Face] No face detected in frame") }
                    } else {
                        await MainActor.run { onLog?("Error: \(error.localizedDescription)") }
                    }
                    await completion(nil, nil)
                }
            }
        }
    }

    func saveFace(
        name: String?,
        suggestion: FaceSuggestion,
        voiceNoteData: Data? = nil
    ) async throws -> FaceProfile? {
        let trimmedName = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? unnamedName() : trimmedName

        let sampleEmbeddings = suggestion.sampleEmbeddings.filter { !$0.isEmpty }
        guard !sampleEmbeddings.isEmpty else { return nil }

        if let idx = profiles.firstIndex(where: { $0.name.caseInsensitiveCompare(resolvedName) == .orderedSame }) {
            profiles[idx].sampleEmbeddings = sampleEmbeddings
            profiles[idx].updatedAt = .now
            if let jpegData = suggestion.jpegData {
                profiles[idx].sampleImageFilename = try await faceStore.saveImage(jpegData, for: profiles[idx].id)
            }
            if let voiceNoteData {
                if let oldName = profiles[idx].voiceNoteFilename {
                    await faceStore.deleteRecording(named: oldName)
                }
                profiles[idx].voiceNoteFilename = try await faceStore.saveRecording(voiceNoteData, for: profiles[idx].id)
            }
            try await faceStore.saveProfiles(profiles)
            logProfileSimilarityDiagnostics(newProfile: profiles[idx])
            resetUnknownTracking()
            return profiles[idx]
        }

        if let duplicate = duplicateMatch(for: suggestion) {
            onLog?("Duplicate save blocked: \(resolvedName) vs \(duplicate.profile.name) similarity \(String(format: "%.4f", duplicate.similarity))")
            return nil
        }

        var profile = FaceProfile(name: resolvedName, sampleEmbeddings: sampleEmbeddings)
        if let jpegData = suggestion.jpegData {
            profile.sampleImageFilename = try await faceStore.saveImage(jpegData, for: profile.id)
        }
        if let voiceNoteData {
            profile.voiceNoteFilename = try await faceStore.saveRecording(voiceNoteData, for: profile.id)
        }
        profiles.append(profile)
        try await faceStore.saveProfiles(profiles)
        logProfileSimilarityDiagnostics(newProfile: profile)
        resetUnknownTracking()
        return profile
    }

    /// A default display name for a face saved without a typed name. A numeric
    /// suffix keeps each unnamed face distinct so saving another one never
    /// overwrites an existing profile.
    private func unnamedName() -> String {
        let base = NSLocalizedString("face.unnamedName", comment: "")
        guard profiles.contains(where: { $0.name.caseInsensitiveCompare(base) == .orderedSame }) else {
            return base
        }
        var index = 2
        while profiles.contains(where: { $0.name.caseInsensitiveCompare("\(base) \(index)") == .orderedSame }) {
            index += 1
        }
        return "\(base) \(index)"
    }

    /// The existing profile that this suggested face is too similar to save as a
    /// new face, if any. This is the same comparison used to block duplicates on
    /// save, so the "offer to save" and "blocked on save" paths stay consistent.
    private func duplicateMatch(for suggestion: FaceSuggestion) -> (profile: FaceProfile, similarity: Float)? {
        guard let newEmbedding = suggestion.sampleEmbeddings.first(where: { !$0.isEmpty }) else { return nil }
        for existing in profiles {
            let existingEmbedding = existing.sampleEmbeddings.first(where: { !$0.isEmpty }) ?? []
            guard !existingEmbedding.isEmpty else { continue }
            let similarity = cosineSimilarity(newEmbedding, existingEmbedding)
            if similarity >= FaceConfig.duplicateWarningThreshold {
                return (existing, similarity)
            }
        }
        return nil
    }

    func deleteProfile(id: UUID) async throws -> [FaceProfile] {
        if let profile = profiles.first(where: { $0.id == id }) {
            if let name = profile.sampleImageFilename {
                try? await faceStore.deleteImage(named: name)
            }
            if let filename = profile.voiceNoteFilename {
                await faceStore.deleteRecording(named: filename)
            }
        }
        profiles.removeAll { $0.id == id }
        try await faceStore.saveProfiles(profiles)
        return profiles
    }

    func renameProfile(id: UUID, newName: String) async throws -> FaceProfile? {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = profiles.firstIndex(where: { $0.id == id }) else { return nil }
        profiles[idx].name = trimmed
        profiles[idx].updatedAt = .now
        try await faceStore.saveProfiles(profiles)
        return profiles[idx]
    }

    private func extractPrimaryFace(from sampleBuffer: CMSampleBuffer) throws -> CGImage {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw FaceEmbeddingError.invalidOutput
        }

        let pixelW = CVPixelBufferGetWidth(pixelBuffer)
        let pixelH = CVPixelBufferGetHeight(pixelBuffer)
        let isPortraitBuffer = pixelH > pixelW
        let orientation: CGImagePropertyOrientation = isPortraitBuffer ? .up : .right

        let uprightCI = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
        let uprightRect = uprightCI.extent
        guard let uprightImage = context.createCGImage(uprightCI, from: uprightRect) else {
            onLog?("[Face] createCGImage upright failed \(uprightRect)")
            throw FaceEmbeddingError.featurePrintGenerationFailed
        }
        let imgW = uprightImage.width
        let imgH = uprightImage.height
        onLog?("[Face] Buffer \(pixelW)×\(pixelH), upright \(imgW)×\(imgH), orient \(orientation.rawValue)")

        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: uprightImage, orientation: .up, options: [:])
        try handler.perform([request])

        let faces = request.results ?? []
        onLog?("[Face] Vision faces: \(faces.count)")
        guard let observation = faces.max(by: {
            $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
        }) else {
            throw FaceEmbeddingError.noFaceDetected
        }

        let bb = observation.boundingBox
        let faceWidthPx = bb.width * CGFloat(imgW)
        let faceHeightPx = bb.height * CGFloat(imgH)
        guard faceWidthPx >= FaceConfig.enrollmentMinimumFaceSize,
              faceHeightPx >= FaceConfig.enrollmentMinimumFaceSize else {
            onLog?("[Face] Face too small: \(faceWidthPx)×\(faceHeightPx)")
            throw FaceEmbeddingError.noFaceDetected
        }

        guard let cropped = cropFace(from: uprightImage, boundingBox: bb) else {
            onLog?("[Face] Face crop failed")
            throw FaceEmbeddingError.featurePrintGenerationFailed
        }
        return cropped
    }

    private func cropFace(from cgImage: CGImage, boundingBox: CGRect) -> CGImage? {
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let padding = FaceConfig.cropPadding

        // Vision bounding box is normalized with bottom-left origin.
        let x = max(0, (boundingBox.minX - padding) * width)
        let y = max(0, (1 - boundingBox.maxY - padding) * height)
        let w = min(width - x, (boundingBox.width + padding * 2) * width)
        let h = min(height - y, (boundingBox.height + padding * 2) * height)

        let cropRect = CGRect(x: x, y: y, width: w, height: h)
        return cgImage.cropping(to: cropRect)
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

        return FaceMatch(
            id: candidate.profile.id,
            name: candidate.profile.name,
            voiceNoteFilename: candidate.profile.voiceNoteFilename,
            confidence: candidate.confidence
        )
    }

    private func rankedCandidates(for embedding: [Float]) -> [CandidateMatch] {
        profiles
            .compactMap { profile in
                let validEmbeddings = profile.sampleEmbeddings.filter { !$0.isEmpty }
                guard !validEmbeddings.isEmpty else { return nil }

                let mean = meanEmbedding(validEmbeddings)
                let confidence = cosineSimilarity(embedding, mean)

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

        guard pendingUnknownEmbeddings.count >= enrollmentSampleTarget else {
            return nil
        }

        let now = Date()
        guard !enrollmentSuggested,
              now.timeIntervalSince(lastUnknownSuggestionDate) >= minimumSuggestionInterval else {
            return nil
        }

        let suggestion = FaceSuggestion(
            sampleEmbeddings: Array(pendingUnknownEmbeddings.prefix(enrollmentSampleTarget)),
            jpegData: pendingUnknownJPEGData
        )

        if let duplicate = duplicateMatch(for: suggestion) {
            resetUnknownTracking()
            lastUnknownSuggestionDate = now
            let message = "Not offering save: too similar to \(duplicate.profile.name) similarity \(String(format: "%.4f", duplicate.similarity))"
            Task { @MainActor in self.onLog?(message) }
            return nil
        }

        lastUnknownSuggestionDate = now
        enrollmentSuggested = true
        let topCandidate = rankedCandidates.first
        let topDescription = topCandidate.map { "\($0.profile.name) \(String(format: "%.3f", $0.confidence))" } ?? "none"
        Task { @MainActor in self.onLog?("Offering save suggestion (top existing match: \(topDescription))") }
        return suggestion
    }

    private func collectUnknownSample(embedding: [Float], faceImage: CGImage) {
        if pendingUnknownEmbeddings.count < enrollmentSampleTarget {
            let isDistinctEnough = pendingUnknownEmbeddings.allSatisfy { savedEmbedding in
                cosineSimilarity(savedEmbedding, embedding) < FaceConfig.sampleDistinctSimilarity
            }

            if isDistinctEnough || pendingUnknownEmbeddings.isEmpty ||
                pendingUnknownEmbeddings.count >= minimumEnrollmentSamples - 1 {
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
            if sim >= FaceConfig.duplicateWarningThreshold {
                onLog?("WARNING: \(newProfile.name) vs \(existing.name) similarity \(String(format: "%.4f", sim)) >= \(FaceConfig.duplicateWarningThreshold) — high cross-profile similarity!")
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
        if valid.count == 1 { return valid[0] }
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

    func resetPendingEnrollment() {
        resetUnknownTracking()
    }

    private func resetUnknownTracking() {
        consecutiveUnknownFrames = 0
        pendingUnknownEmbeddings = []
        pendingUnknownJPEGData = nil
        enrollmentSuggested = false
    }
}

private func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Float {
    guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
    var dot: Float = 0, magA: Float = 0, magB: Float = 0
    for i in 0..<lhs.count {
        dot += lhs[i] * rhs[i]
        magA += lhs[i] * lhs[i]
        magB += rhs[i] * rhs[i]
    }
    let mag = sqrt(magA) * sqrt(magB)
    return mag > 0 ? dot / mag : 0
}
