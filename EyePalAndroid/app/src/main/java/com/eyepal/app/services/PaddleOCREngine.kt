package com.eyepal.app.services

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Rect
import com.paddle.ocr.EngineConfig
import com.paddle.ocr.PaddleOCR
import com.paddle.ocr.PaddleOCRConfig
import com.paddle.ocr.util.OpenCVUtils
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

class PaddleOCREngine(private val context: Context) {
    private val mutex = Mutex()
    private var ocr: PaddleOCR? = null

    private suspend fun getOrCreate(): PaddleOCR = mutex.withLock {
        ocr ?: run {
            if (!OpenCVUtils.init(context)) {
                throw RuntimeException("OpenCV native library could not be loaded")
            }
            val created = PaddleOCR.create(context, PaddleOCRConfig(), EngineConfig(numThreads = 4))
            ocr = created
            created
        }
    }

    suspend fun recognizeText(bitmap: Bitmap): OCRResult = withContext(Dispatchers.IO) {
        val paddle = try {
            getOrCreate()
        } catch (t: Throwable) {
            android.util.Log.e("PaddleOCREngine", "PaddleOCR init failed: ${t.message}", t)
            OcrEngineLog.add("PaddleOCR 初始化失敗: ${t.message}")
            return@withContext OCRResult("No text detected", "Unknown", emptyList())
        }
        val run = try {
            paddle.recognize(bitmap)
        } catch (t: Throwable) {
            android.util.Log.e("PaddleOCREngine", "PaddleOCR recognize failed: ${t.message}", t)
            OcrEngineLog.add("PaddleOCR 辨識失敗: ${t.message}")
            return@withContext OCRResult("No text detected", "Unknown", emptyList())
        }
        val blocks = run.results.map { item ->
            val xMin = item.box.points.minOf { it.x }.coerceAtLeast(0f)
            val yMin = item.box.points.minOf { it.y }.coerceAtLeast(0f)
            val xMax = item.box.points.maxOf { it.x }.coerceAtMost(bitmap.width.toFloat())
            val yMax = item.box.points.maxOf { it.y }.coerceAtMost(bitmap.height.toFloat())
            TextBlockInfo(item.text, Rect(xMin.toInt(), yMin.toInt(), xMax.toInt(), yMax.toInt()))
        }
        val text = blocks.joinToString("\n") { it.text }.trim()
        if (text.isBlank()) {
            OCRResult("No text detected", "Unknown", emptyList())
        } else {
            OCRResult(text, "Chinese", blocks)
        }
    }

    fun close() {
        val instance = ocr ?: return
        CoroutineScope(Dispatchers.IO).launch {
            try {
                instance.release()
            } catch (_: Throwable) {
            }
        }
    }
}