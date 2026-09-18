package com.eyepal.app.services

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.util.Log
import com.eyepal.app.config.Defaults
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.Face
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.Locale
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.math.sqrt

class FaceRecognitionService(private val context: Context) {
    private val faceDetector = FaceDetection.getClient(
        FaceDetectorOptions.Builder()
            .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
            .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_ALL)
            .build()
    )
    private val embeddingEngine = ArcFaceEmbeddingEngine(context)
    val logStore = FaceRecognitionLogStore(context)
    val isEmbeddingReady: Boolean get() = embeddingEngine.isReady
    val embeddingEngineError: String? get() = embeddingEngine.loadError
    private var profiles: MutableList<SavedFaceProfile> = mutableListOf()
    var recognitionThreshold: Float = 0.60f
    var minimumTopMatchMargin: Float = 0.05f
    var knownMatchFrameThreshold: Int = 1
    var enrollmentSampleTarget: Int = 1
    var minimumFaceSize: Int = 80
    var enrollmentMinimumFaceSize: Int = Defaults.ENROLLMENT_MINIMUM_FACE_SIZE
    var borderlineKnownThreshold: Float = Defaults.BORDERLINE_KNOWN_THRESHOLD
    var suggestionFrameThreshold: Int = Defaults.UNKNOWN_SUGGESTION_FRAME_THRESHOLD
    var minimumSuggestionIntervalMs: Long = Defaults.UNKNOWN_SUGGESTION_MIN_INTERVAL_MS
    var minimumEnrollmentSamples: Int = Defaults.MINIMUM_ENROLLMENT_SAMPLES
    var suggestUnknownFaces: Boolean = true
    var minimumSampleSharpness: Float = 80f
    private var pendingUnknownEmbeddings: MutableList<FloatArray> = mutableListOf()
    private var consecutiveUnknownFrames = 0
    private var lastUnknownSuggestionTime = 0L
    private var enrollmentSuggested = false
    private var consecutiveMatchName: String? = null
    private var consecutiveMatchCount = 0
    private var lastMatchEmbedding: FloatArray? = null
    private var lastSampleFaceCenterX = 0f
    private var lastSampleFaceCenterY = 0f

    data class SavedFaceProfile(
        val id: String,
        val name: String,
        val embeddings: List<FloatArray>,
        val soundFilename: String? = null
    )
    data class FaceMatch(val name: String, val confidence: Float)
    data class PendingSamples(val embeddings: List<FloatArray>, val count: Int, val target: Int, val suggestNow: Boolean = false)

    suspend fun load() = withContext(Dispatchers.IO) {
        logStore.load()
        embeddingEngine.load()
        val file = File(context.filesDir, "faces.json")
        if (file.exists()) {
            val json = JSONObject(file.readText())
            val arr = json.optJSONArray("faces") ?: return@withContext
            profiles.clear()
            for (i in 0 until arr.length()) {
                val obj = arr.getJSONObject(i)
                val embeddings = mutableListOf<FloatArray>()
                val embArr = obj.getJSONArray("embeddings")
                for (j in 0 until embArr.length()) {
                    val floats = embArr.getJSONArray(j)
                    embeddings.add(FloatArray(floats.length()) { floats.getDouble(it).toFloat() })
                }
                profiles.add(
                    SavedFaceProfile(
                        id = obj.getString("id"),
                        name = obj.getString("name"),
                        embeddings = embeddings,
                        soundFilename = obj.optStringOrNull("soundFilename")
                    )
                )
            }
            logInterProfileSimilarities()
        }
    }

    suspend fun processFrame(bitmap: Bitmap): FaceProcessResult = withContext(Dispatchers.IO) {
        val faces = detectFaces(bitmap)
        if (faces.isEmpty()) {
            resetMatchTracking()
            return@withContext FaceProcessResult(null, null)
        }

        val face = faces.filter { it.boundingBox.width() >= minimumFaceSize && it.boundingBox.height() >= minimumFaceSize }
            .maxByOrNull { it.boundingBox.width() * it.boundingBox.height() } ?: run {
                resetMatchTracking()
                return@withContext FaceProcessResult(null, null)
            }
        val faceBitmap = alignFace(bitmap, face)
        val embedding = embeddingEngine.generateEmbedding(faceBitmap) ?: return@withContext FaceProcessResult(null, null)

        val match = findBestMatch(embedding)
        if (match != null) {
            val sameName = match.name == consecutiveMatchName
            val sameIdentity = lastMatchEmbedding != null &&
                embeddingEngine.cosineSimilarity(embedding, lastMatchEmbedding!!) >= Defaults.SAME_IDENTITY_SIMILARITY
            if (sameName && (lastMatchEmbedding == null || sameIdentity)) {
                consecutiveMatchCount++
            } else {
                consecutiveMatchName = match.name
                consecutiveMatchCount = 1
            }
            lastMatchEmbedding = embedding
            pendingUnknownEmbeddings.clear()
            consecutiveUnknownFrames = 0
            lastSampleFaceCenterX = 0f
            lastSampleFaceCenterY = 0f
            enrollmentSuggested = false
            if (consecutiveMatchCount >= knownMatchFrameThreshold) {
                logStore.append("Recognized: ${match.name} (${String.format(Locale.US, "%.3f", match.confidence)})")
                FaceProcessResult(match, embedding)
            } else {
                FaceProcessResult(null, embedding)
            }
        } else {
            resetMatchTracking()
            if (suggestUnknownFaces) {
                val ranked = rankedProfiles(embedding)
                val bestScore = ranked.firstOrNull()?.second ?: 0f
                val reason = when {
                    ranked.isEmpty() -> "no profiles"
                    bestScore < recognitionThreshold -> "below threshold"
                    ranked.size > 1 && (bestScore - ranked[1].second) < minimumTopMatchMargin -> "margin too small"
                    else -> "frame threshold"
                }
                Log.d("FaceRec", "No match: ${ranked.firstOrNull()?.first?.name ?: "-"} ${String.format(Locale.US, "%.4f", bestScore)} [$reason]")
                if (ranked.isNotEmpty() && bestScore >= borderlineKnownThreshold) {
                    Log.d("FaceRec", "Borderline known (score=$bestScore >= $borderlineKnownThreshold), suppressing unknown suggestion")
                    pendingUnknownEmbeddings.clear()
                    consecutiveUnknownFrames = 0
                    lastSampleFaceCenterX = 0f
                    lastSampleFaceCenterY = 0f
                    enrollmentSuggested = false
                    FaceProcessResult(null, embedding)
                } else {
                    consecutiveUnknownFrames++
                    collectUnknownSample(embedding, face, faceBitmap)
                    val current = pendingUnknownEmbeddings.toList()
                    if (current.size >= enrollmentSampleTarget &&
                        consecutiveUnknownFrames >= suggestionFrameThreshold
                    ) {
                        val now = System.currentTimeMillis()
                        if (!enrollmentSuggested && now - lastUnknownSuggestionTime >= minimumSuggestionIntervalMs) {
                            lastUnknownSuggestionTime = now
                            consecutiveUnknownFrames = 0
                            enrollmentSuggested = true
                            logStore.append("Suggest saving unknown face (${current.size} samples)")
                            FaceProcessResult(null, embedding, PendingSamples(current, current.size, enrollmentSampleTarget, suggestNow = true))
                        } else {
                            // Collection is held open for saving; suppress further sample updates.
                            FaceProcessResult(null, embedding)
                        }
                    } else {
                        FaceProcessResult(null, embedding, PendingSamples(current, current.size, enrollmentSampleTarget))
                    }
                }
            } else {
                FaceProcessResult(null, embedding)
            }
        }
    }

    private fun computeSharpness(bitmap: Bitmap): Float {
        val w = bitmap.width
        val h = bitmap.height
        if (w < 3 || h < 3) return 0f
        val gray = IntArray(w * h)
        for (y in 0 until h) {
            for (x in 0 until w) {
                val c = bitmap.getPixel(x, y)
                gray[y * w + x] = (((c shr 16) and 0xFF) + ((c shr 8) and 0xFF) + (c and 0xFF)) / 3
            }
        }
        var laplacianSumSq = 0.0
        var count = 0
        for (y in 1 until h - 1) {
            for (x in 1 until w - 1) {
                val center = gray[y * w + x]
                val lap = center * 8 -
                    gray[(y - 1) * w + x] - gray[(y + 1) * w + x] -
                    gray[y * w + x - 1] - gray[y * w + x + 1] -
                    gray[(y - 1) * w + x - 1] - gray[(y - 1) * w + x + 1] -
                    gray[(y + 1) * w + x - 1] - gray[(y + 1) * w + x + 1]
                laplacianSumSq += lap.toDouble() * lap.toDouble()
                count++
            }
        }
        if (count == 0) return 0f
        return (laplacianSumSq / count).toFloat()
    }

    private fun resetMatchTracking() {
        consecutiveMatchName = null
        consecutiveMatchCount = 0
        lastMatchEmbedding = null
    }

    private fun collectUnknownSample(embedding: FloatArray, face: Face, faceBitmap: Bitmap) {
        if (face.boundingBox.width() < enrollmentMinimumFaceSize || face.boundingBox.height() < enrollmentMinimumFaceSize) {
            Log.d("FaceRec", "Sample rejected (face too small): ${face.boundingBox.width()}x${face.boundingBox.height()} < $enrollmentMinimumFaceSize")
            return
        }
        val sharpness = computeSharpness(faceBitmap)
        if (sharpness < minimumSampleSharpness) {
            Log.d("FaceRec", "Sample rejected (blurry): sharpness=${String.format("%.1f", sharpness)}")
            return
        }
        val centerX = face.boundingBox.exactCenterX()
        val centerY = face.boundingBox.exactCenterY()
        if (pendingUnknownEmbeddings.isNotEmpty()) {
            val dx = centerX - lastSampleFaceCenterX
            val dy = centerY - lastSampleFaceCenterY
            val distance = sqrt(dx * dx + dy * dy)
            if (distance > face.boundingBox.width() * 1.5f) {
                pendingUnknownEmbeddings.clear()
            }
        }
        lastSampleFaceCenterX = centerX
        lastSampleFaceCenterY = centerY
        if (pendingUnknownEmbeddings.size < enrollmentSampleTarget) {
            val isDistinctEnough = pendingUnknownEmbeddings.all { savedEmbedding ->
                embeddingEngine.cosineSimilarity(savedEmbedding, embedding) < Defaults.SAMPLE_DISTINCT_SIMILARITY
            }
            // Prefer distinct samples, but always accept non-distinct ones once the
            // collection is nearly complete so a still face can still reach the full
            // target (prevents getting stuck below the target while holding still).
            if (isDistinctEnough || pendingUnknownEmbeddings.isEmpty() ||
                pendingUnknownEmbeddings.size >= minimumEnrollmentSamples - 1
            ) {
                pendingUnknownEmbeddings.add(embedding)
            }
        }
    }

    fun resetSampleCollection() {
        pendingUnknownEmbeddings.clear()
        lastSampleFaceCenterX = 0f
        lastSampleFaceCenterY = 0f
        enrollmentSuggested = false
    }

    private fun alignFace(source: Bitmap, face: Face): Bitmap {
        val bounds = face.boundingBox
        val padX = (bounds.width() * 0.15f).toInt()
        val padY = (bounds.height() * 0.15f).toInt()
        val left = (bounds.left - padX).coerceAtLeast(0)
        val top = (bounds.top - padY).coerceAtLeast(0)
        val right = (bounds.right + padX).coerceAtMost(source.width)
        val bottom = (bounds.bottom + padY).coerceAtMost(source.height)
        val output = Bitmap.createBitmap(112, 112, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        canvas.drawBitmap(source, android.graphics.Rect(left, top, right, bottom), android.graphics.Rect(0, 0, 112, 112), null)
        return output
    }

    fun findBestMatch(embedding: FloatArray): FaceMatch? {
        val ranked = rankedProfiles(embedding)
        if (ranked.isEmpty()) return null
        val bestScore = ranked[0].second
        val secondBestScore = if (ranked.size > 1) ranked[1].second else 0f
        val margin = bestScore - secondBestScore
        val bestName = ranked[0].first.name
        android.util.Log.d("FaceRec", "Best: '$bestName'=${String.format("%.4f", bestScore)} 2nd=${String.format("%.4f", secondBestScore)} margin=${String.format("%.4f", margin)} threshold=${String.format("%.4f", recognitionThreshold)} minMargin=${String.format("%.4f", minimumTopMatchMargin)}")
        if (bestScore < recognitionThreshold) return null
        if (ranked.size > 1 && margin < minimumTopMatchMargin) return null
        return FaceMatch(bestName, bestScore)
    }

    private fun rankedProfiles(embedding: FloatArray): List<Pair<SavedFaceProfile, Float>> {
        return profiles
            .mapNotNull { profile ->
                val score = cosineToProfileMean(embedding, profile)
                android.util.Log.d("FaceRec", "Profile '${profile.name}': score=${String.format("%.4f", score)}")
                profile to score
            }
            .sortedByDescending { it.second }
    }

    private fun cosineToProfileMean(embedding: FloatArray, profile: SavedFaceProfile): Float {
        val stored = profile.embeddings.firstOrNull { it.isNotEmpty() } ?: return 0f
        return embeddingEngine.cosineSimilarity(embedding, stored)
    }

    private fun logInterProfileSimilarities() {
        if (profiles.size < 2) return
        for (i in 0 until profiles.size - 1) {
            for (j in (i + 1) until profiles.size) {
                val embA = profiles[i].embeddings.firstOrNull { it.isNotEmpty() } ?: continue
                val embB = profiles[j].embeddings.firstOrNull { it.isNotEmpty() } ?: continue
                val similarity = embeddingEngine.cosineSimilarity(embA, embB)
                Log.d("FaceRec", "InterProfile: '${profiles[i].name}' vs '${profiles[j].name}' = ${String.format(Locale.US, "%.4f", similarity)}")
            }
        }
    }

    suspend fun saveFace(name: String, embedding: FloatArray): String? = withContext(Dispatchers.IO) {
        val existing = profiles.firstOrNull { it.name.equals(name, ignoreCase = true) }
        if (existing != null) {
            profiles = profiles.map { if (it.id == existing.id) it.copy(embeddings = listOf(embedding)) else it }.toMutableList()
        } else {
            checkDuplicateSave(name, listOf(embedding))?.let { return@withContext it }
            profiles.add(SavedFaceProfile(id = System.currentTimeMillis().toString(), name = name, embeddings = listOf(embedding)))
        }
        logStore.append("Saved: $name")
        persistFaces()
        null
    }

    suspend fun saveFaceMultiple(
        name: String,
        embeddings: List<FloatArray>,
        audioSource: File? = null
    ): String? = withContext(Dispatchers.IO) {
        val validEmbeddings = embeddings.filter { it.isNotEmpty() }
        if (validEmbeddings.isEmpty()) return@withContext null
        val primary = validEmbeddings.first()
        val existing = profiles.firstOrNull { it.name.equals(name, ignoreCase = true) }
        if (existing != null) {
            val soundFilename = if (audioSource != null) {
                existing.soundFilename?.let { deleteAudioFile(it) }
                installAudioFile(audioSource, existing.id)
            } else {
                existing.soundFilename
            }
            profiles = profiles.map {
                if (it.id == existing.id) it.copy(embeddings = listOf(primary), soundFilename = soundFilename) else it
            }.toMutableList()
        } else {
            checkDuplicateSave(name, listOf(primary))?.let { return@withContext it }
            val id = System.currentTimeMillis().toString()
            val soundFilename = audioSource?.let { installAudioFile(it, id) }
            profiles.add(SavedFaceProfile(id = id, name = name, embeddings = listOf(primary), soundFilename = soundFilename))
        }
        logStore.append("Saved: $name")
        persistFaces()
        null
    }

    private fun audioDir(): File =
        File(context.filesDir, "face_audio").apply { if (!exists()) mkdirs() }

    private fun installAudioFile(source: File, profileId: String): String {
        val filename = "$profileId.m4a"
        val target = File(audioDir(), filename)
        source.copyTo(target, overwrite = true)
        return filename
    }

    fun recordingFile(filename: String): File = File(audioDir(), filename)

    private fun deleteAudioFile(filename: String) {
        val file = audioDir().listFiles()?.firstOrNull { it.name == filename } ?: return
        runCatching { file.delete() }
    }

    /**
     * The existing profile a pending face is already too similar to save as a new
     * face (name + similarity), or null when saving would be allowed. Used to avoid
     * offering a save that the duplicate check would reject.
     */
    fun tooSimilarProfile(embeddings: List<FloatArray>): Pair<String, Float>? {
        val newEmb = embeddings.firstOrNull { it.isNotEmpty() } ?: return null
        var bestName: String? = null
        var bestSimilarity = 0f
        for (profile in profiles) {
            val existingEmb = profile.embeddings.firstOrNull { it.isNotEmpty() } ?: continue
            val similarity = embeddingEngine.cosineSimilarity(newEmb, existingEmb)
            if (similarity > bestSimilarity) {
                bestSimilarity = similarity
                bestName = profile.name
            }
        }
        if (bestName == null || bestSimilarity < Defaults.FACE_DUPLICATE_WARNING_THRESHOLD) return null
        return bestName to bestSimilarity
    }

    private fun checkDuplicateSave(newName: String, newEmbeddings: List<FloatArray>): String? {
        if (profiles.isEmpty()) {
            Log.d("FaceRec", "Saved first profile '$newName' — no existing profiles to compare")
            return null
        }
        val newEmb = newEmbeddings.firstOrNull { it.isNotEmpty() } ?: return null
        var maxSimilarity = 0f
        var maxProfileName = ""
        for (profile in profiles) {
            val existingEmb = profile.embeddings.firstOrNull { it.isNotEmpty() } ?: continue
            val similarity = embeddingEngine.cosineSimilarity(newEmb, existingEmb)
            Log.d("FaceRec", "Similarity: '$newName' vs '${profile.name}' = ${String.format(Locale.US, "%.4f", similarity)}")
            if (similarity > maxSimilarity) {
                maxSimilarity = similarity
                maxProfileName = profile.name
            }
        }
        val summary = "Similarity: '$newName' vs existing — closest='$maxProfileName' ${String.format(Locale.US, "%.3f", maxSimilarity)}"
        Log.d("FaceRec", summary)
        if (maxSimilarity >= Defaults.FACE_DUPLICATE_WARNING_THRESHOLD) {
            val reason = "Duplicate blocked: '$newName' is too similar to '$maxProfileName' (${String.format(Locale.US, "%.3f", maxSimilarity)}) — likely the same person. Use the same name as '$maxProfileName' to update it, or delete that profile first."
            Log.w("FaceRec", reason)
            logStore.append(reason)
            return reason
        }
        logStore.append(summary)
        return null
    }

    suspend fun deleteFace(id: String) = withContext(Dispatchers.IO) {
        val profile = profiles.firstOrNull { it.id == id }
        profile?.soundFilename?.let { deleteAudioFile(it) }
        profiles.removeAll { it.id == id }
        persistFaces()
    }

    suspend fun renameFace(id: String, newName: String) = withContext(Dispatchers.IO) {
        val trimmedName = newName.trim()
        if (trimmedName.isEmpty()) return@withContext
        profiles = profiles.map { if (it.id == id) it.copy(name = trimmedName) else it }.toMutableList()
        persistFaces()
    }

    fun getProfiles() = profiles.toList()

    private fun persistFaces() {
        val arr = JSONArray()
        for (profile in profiles) {
            val embArr = JSONArray()
            for (emb in profile.embeddings) {
                val floatArr = JSONArray()
                for (v in emb) floatArr.put(v.toDouble())
                embArr.put(floatArr)
            }
            arr.put(JSONObject().apply {
                put("id", profile.id)
                put("name", profile.name)
                put("embeddings", embArr)
                if (profile.soundFilename != null) put("soundFilename", profile.soundFilename)
            })
        }
        File(context.filesDir, "faces.json").writeText(JSONObject().put("faces", arr).toString())
    }

    private suspend fun detectFaces(bitmap: Bitmap): List<Face> = suspendCancellableCoroutine { cont ->
        val image = InputImage.fromBitmap(bitmap, 0)
        faceDetector.process(image)
            .addOnSuccessListener { faces -> cont.resume(faces) }
            .addOnFailureListener { cont.resumeWithException(it) }
    }

    fun close() { faceDetector.close(); embeddingEngine.close() }
}

private fun JSONObject.optStringOrNull(key: String): String? =
    if (has(key) && !isNull(key)) optString(key) else null

data class FaceProcessResult(
    val match: FaceRecognitionService.FaceMatch?,
    val embedding: FloatArray?,
    val pendingSamples: FaceRecognitionService.PendingSamples? = null
)
