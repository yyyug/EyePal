package com.eyepal.app.services

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.nio.FloatBuffer

class ArcFaceEmbeddingEngine(private val context: Context) {
    private var ortEnv: OrtEnvironment? = null
    private var session: OrtSession? = null
    private var isLoaded = false
    var loadError: String? = null
        private set

    val isReady: Boolean get() = isLoaded

    suspend fun load() = withContext(Dispatchers.IO) {
        try {
            loadError = null
            ortEnv = OrtEnvironment.getEnvironment()
            val modelFile = File(context.filesDir, "w600k_mbf.onnx")
            if (!modelFile.exists()) {
                context.assets.open("w600k_mbf.onnx").use { input ->
                    modelFile.outputStream().use { output -> input.copyTo(output) }
                }
            }
            val modelSize = modelFile.length()
            android.util.Log.d("ArcFace", "Model file: ${modelFile.absolutePath} (${modelSize / 1024 / 1024} MB)")
            val sessionOptions = OrtSession.SessionOptions()
            session = ortEnv!!.createSession(modelFile.absolutePath, sessionOptions)
            val inputNames = session!!.inputNames
            val outputNames = session!!.outputNames
            android.util.Log.d("ArcFace", "Session loaded. Inputs: $inputNames Outputs: $outputNames")
            isLoaded = true
            android.util.Log.d("ArcFace", "ArcFace engine loaded successfully")
        } catch (e: Exception) {
            android.util.Log.e("ArcFace", "Failed to load model: ${e.message}", e)
            loadError = e.message ?: e.toString()
            isLoaded = false
        }
    }

    suspend fun generateEmbedding(faceBitmap: Bitmap): FloatArray? = withContext(Dispatchers.IO) {
        if (!isLoaded || session == null || ortEnv == null) {
            android.util.Log.w("ArcFace", "Embedding engine not ready${loadError?.let { ": $it" } ?: ""} — skipping frame")
            return@withContext null
        }
        var inputBitmap: Bitmap? = null
        var inputTensor: OnnxTensor? = null
        var results: OrtSession.Result? = null
        try {
            inputBitmap = Bitmap.createScaledBitmap(faceBitmap, 112, 112, true)
            val rChannel = FloatArray(112 * 112)
            val gChannel = FloatArray(112 * 112)
            val bChannel = FloatArray(112 * 112)
            var idx = 0
            for (y in 0 until 112) {
                for (x in 0 until 112) {
                    val pixel = inputBitmap.getPixel(x, y)
                    rChannel[idx] = Color.red(pixel) / 127.5f - 1.0f
                    gChannel[idx] = Color.green(pixel) / 127.5f - 1.0f
                    bChannel[idx] = Color.blue(pixel) / 127.5f - 1.0f
                    idx++
                }
            }
            val allChannels = rChannel + gChannel + bChannel
            val floatBuffer = FloatBuffer.wrap(allChannels)
            floatBuffer.rewind()
            inputTensor = OnnxTensor.createTensor(ortEnv!!, floatBuffer, longArrayOf(1, 3, 112, 112))
            results = session!!.run(mapOf(session!!.inputNames.first() to inputTensor))
            val output = results[0].value as Array<FloatArray>
            val embedding = output[0]
            val norm = kotlin.math.sqrt(embedding.sumOf { (it * it).toDouble() }).toFloat()
            if (norm > 0) FloatArray(embedding.size) { embedding[it] / norm } else embedding
        } catch (e: Exception) {
            android.util.Log.e("ArcFace", "Embedding generation failed: ${e.message}", e)
            null
        } finally {
            results?.close()
            inputTensor?.close()
            inputBitmap?.recycle()
        }
    }

    fun cosineSimilarity(a: FloatArray, b: FloatArray): Float {
        if (a.size != b.size || a.isEmpty()) return -1f
        return a.indices.sumOf { (a[it] * b[it]).toDouble() }.toFloat()
    }

    fun close() { session?.close(); ortEnv?.close(); isLoaded = false }
}
