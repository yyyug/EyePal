package com.eyepal.app.services

import android.content.Context
import android.graphics.Bitmap
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
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.math.sqrt

class FaceRecognitionService(private val context: Context) {
    private val faceDetector = FaceDetection.getClient(
        FaceDetectorOptions.Builder().setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST).build()
    )
    private val embeddingEngine = ArcFaceEmbeddingEngine(context)
    private var profiles: MutableList<SavedFaceProfile> = mutableListOf()
    var recognitionThreshold: Float = 0.95f
    var minimumTopMatchMargin: Float = 0.05f
    var knownMatchFrameThreshold: Int = 3

    data class SavedFaceProfile(val id: String, val name: String, val embeddings: List<FloatArray>)
    data class FaceMatch(val name: String, val confidence: Float)

    suspend fun load() = withContext(Dispatchers.IO) {
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
                profiles.add(SavedFaceProfile(obj.getString("id"), obj.getString("name"), embeddings))
            }
        }
    }

    suspend fun processFrame(bitmap: Bitmap): FaceProcessResult = withContext(Dispatchers.IO) {
        val faces = detectFaces(bitmap)
        if (faces.isEmpty()) return@withContext FaceProcessResult(null, null)

        val face = faces.maxByOrNull { it.boundingBox.width() * it.boundingBox.height() } ?: return@withContext FaceProcessResult(null, null)
        val bounds = face.boundingBox
        val faceBitmap = Bitmap.createBitmap(bitmap,
            (bounds.left.coerceAtLeast(0)),
            (bounds.top.coerceAtLeast(0)),
            bounds.width().coerceAtMost(bitmap.width - bounds.left.coerceAtLeast(0)),
            bounds.height().coerceAtMost(bitmap.height - bounds.top.coerceAtLeast(0))
        )
        val embedding = embeddingEngine.generateEmbedding(faceBitmap) ?: return@withContext FaceProcessResult(null, null)

        val match = findBestMatch(embedding)
        FaceProcessResult(match, embedding)
    }

    fun findBestMatch(embedding: FloatArray): FaceMatch? {
        if (profiles.isEmpty()) return null
        var bestName = ""
        var bestScore = 0f
        var secondBestScore = 0f
        for (profile in profiles) {
            val maxScore = profile.embeddings.maxOfOrNull { embeddingEngine.cosineSimilarity(embedding, it) } ?: continue
            android.util.Log.d("FaceRec", "Profile '${profile.name}': score=${String.format("%.4f", maxScore)}")
            if (maxScore > bestScore) { secondBestScore = bestScore; bestScore = maxScore; bestName = profile.name }
            else if (maxScore > secondBestScore) { secondBestScore = maxScore }
        }
        val margin = bestScore - secondBestScore
        android.util.Log.d("FaceRec", "Best: '$bestName'=${String.format("%.4f", bestScore)} 2nd=${String.format("%.4f", secondBestScore)} margin=${String.format("%.4f", margin)} threshold=${String.format("%.4f", recognitionThreshold)} minMargin=${String.format("%.4f", minimumTopMatchMargin)}")
        if (bestScore < recognitionThreshold) return null
        if (profiles.size > 1 && margin < minimumTopMatchMargin) return null
        return FaceMatch(bestName, bestScore)
    }

    suspend fun saveFace(name: String, embedding: FloatArray) = withContext(Dispatchers.IO) {
        val existing = profiles.firstOrNull { it.name.equals(name, ignoreCase = true) }
        if (existing != null) {
            val updatedEmbeddings = (existing.embeddings + embedding).takeLast(4)
            profiles = profiles.map { if (it.id == existing.id) it.copy(embeddings = updatedEmbeddings) else it }.toMutableList()
        } else {
            profiles.add(SavedFaceProfile(id = System.currentTimeMillis().toString(), name = name, embeddings = listOf(embedding)))
        }
        persistFaces()
    }

    suspend fun deleteFace(id: String) = withContext(Dispatchers.IO) {
        profiles.removeAll { it.id == id }
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
            arr.put(JSONObject().apply { put("id", profile.id); put("name", profile.name); put("embeddings", embArr) })
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

data class FaceProcessResult(val match: FaceRecognitionService.FaceMatch?, val embedding: FloatArray?)
