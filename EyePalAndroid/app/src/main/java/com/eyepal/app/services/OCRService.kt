package com.eyepal.app.services

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Rect
import com.eyepal.app.R
import com.eyepal.app.config.Defaults
import com.eyepal.app.data.SettingsRepository
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
import com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

data class TextBlockInfo(val text: String, val bounds: Rect)

data class OCRResult(
    val text: String,
    val detectedLanguage: String,
    val textBlocks: List<TextBlockInfo>
)

enum class OcrEngine(val value: String, val labelRes: Int) {
    ML_KIT("mlkit", R.string.ocr_engine_mlkit),
    PADDLE("paddle", R.string.ocr_engine_paddle);

    companion object {
        fun fromValue(value: String): OcrEngine = entries.find { it.value == value } ?: ML_KIT
    }
}

class OCRService(
    private val context: Context,
    private val settingsRepository: SettingsRepository
) {
    private val latinRecognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    private val chineseRecognizer = TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build())
    private val japaneseRecognizer = TextRecognition.getClient(JapaneseTextRecognizerOptions.Builder().build())
    private val koreanRecognizer = TextRecognition.getClient(KoreanTextRecognizerOptions.Builder().build())
    private val paddleEngine = PaddleOCREngine(context)

    private var lastSuccessfulRecognizer: TextRecognizer? = null
    private var lastRecognizerIndex = 0
    private val recognizers = listOf(latinRecognizer, chineseRecognizer, japaneseRecognizer, koreanRecognizer)
    private val recognizerLanguages = listOf("Latin", "Chinese", "Japanese", "Korean")

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    var currentEngine: OcrEngine = OcrEngine.fromValue(Defaults.OCR_ENGINE)
        private set

    init {
        scope.launch {
            settingsRepository.ocrEngine.collect { value -> currentEngine = OcrEngine.fromValue(value) }
        }
    }

    suspend fun recognizeText(bitmap: Bitmap): OCRResult {
        val startMs = System.currentTimeMillis()
        val result = if (currentEngine == OcrEngine.PADDLE) {
            paddleEngine.recognizeText(bitmap)
        } else {
            recognizeMlKit(bitmap)
        }
        android.util.Log.i("OCRService", "recognizeText engine=${currentEngine} ${System.currentTimeMillis() - startMs}ms → '${result.text.take(80)}'")
        return result
    }

    private suspend fun recognizeMlKit(bitmap: Bitmap): OCRResult = suspendCancellableCoroutine { cont ->
        val image = InputImage.fromBitmap(bitmap, 0)

        fun tryRecognizer(index: Int) {
            if (index >= recognizers.size) {
                cont.resume(OCRResult("No text detected", "Unknown", emptyList()))
                return
            }
            val recognizer = recognizers[index]
            recognizer.process(image)
                .addOnSuccessListener { result ->
                    val text = result.text
                    if (text.isNotBlank()) {
                        lastSuccessfulRecognizer = recognizer
                        lastRecognizerIndex = index
                        val blocks = result.textBlocks.map { block ->
                            TextBlockInfo(block.text, block.boundingBox ?: Rect())
                        }
                        cont.resume(OCRResult(text, recognizerLanguages[index], blocks))
                    } else {
                        tryRecognizer(index + 1)
                    }
                }
                .addOnFailureListener { tryRecognizer(index + 1) }
        }

        if (lastSuccessfulRecognizer != null) {
            lastSuccessfulRecognizer!!.process(image)
                .addOnSuccessListener { result ->
                    if (result.text.isNotBlank()) {
                        val blocks = result.textBlocks.map { block ->
                            TextBlockInfo(block.text, block.boundingBox ?: Rect())
                        }
                        cont.resume(OCRResult(result.text, recognizerLanguages[lastRecognizerIndex], blocks))
                    } else {
                        tryRecognizer(0)
                    }
                }
                .addOnFailureListener { tryRecognizer(0) }
        } else {
            tryRecognizer(0)
        }
    }

    fun close() {
        recognizers.forEach { it.close() }
        paddleEngine.close()
        scope.cancel()
    }
}
