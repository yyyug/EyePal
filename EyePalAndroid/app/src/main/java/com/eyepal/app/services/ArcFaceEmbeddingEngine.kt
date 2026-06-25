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

    suspend fun load() = withContext(Dispatchers.IO) {
        try {
            ortEnv = OrtEnvironment.getEnvironment()
            val modelFile = File(context.filesDir, "arcface_fresh.onnx")
            if (!modelFile.exists()) {
                context.assets.open("arcface_fresh.onnx").use { input ->
                    modelFile.outputStream().use { output -> input.copyTo(output) }
                }
            }
            val sessionOptions = OrtSession.SessionOptions()
            session = ortEnv!!.createSession(modelFile.absolutePath, sessionOptions)
            isLoaded = true
        } catch (_: Exception) { isLoaded = false }
    }

    suspend fun generateEmbedding(faceBitmap: Bitmap): FloatArray? = withContext(Dispatchers.IO) {
        if (!isLoaded || session == null || ortEnv == null) return@withContext null
        try {
            val inputBitmap = Bitmap.createScaledBitmap(faceBitmap, 112, 112, true)
            val floatBuffer = FloatBuffer.allocate(3 * 112 * 112)
            for (y in 0 until 112) {
                for (x in 0 until 112) {
                    val pixel = inputBitmap.getPixel(x, y)
                    floatBuffer.put(Color.red(pixel) / 127.5f - 1.0f)
                    floatBuffer.put(Color.green(pixel) / 127.5f - 1.0f)
                    floatBuffer.put(Color.blue(pixel) / 127.5f - 1.0f)
                }
            }
            floatBuffer.rewind()
            val inputTensor = OnnxTensor.createTensor(ortEnv!!, floatBuffer, longArrayOf(1, 3, 112, 112))
            val results = session!!.run(mapOf(session!!.inputNames.first() to inputTensor))
            val output = results[0].value as Array<FloatArray>
            results.close()
            inputTensor.close()
            val embedding = output[0]
            val norm = kotlin.math.sqrt(embedding.sumOf { (it * it).toDouble() }).toFloat()
            if (norm > 0) FloatArray(embedding.size) { embedding[it] / norm } else embedding
        } catch (_: Exception) { null }
    }

    fun cosineSimilarity(a: FloatArray, b: FloatArray): Float {
        if (a.size != b.size || a.isEmpty()) return -1f
        return a.indices.sumOf { (a[it] * b[it]).toDouble() }.toFloat()
    }

    fun close() { session?.close(); ortEnv?.close(); isLoaded = false }
}
