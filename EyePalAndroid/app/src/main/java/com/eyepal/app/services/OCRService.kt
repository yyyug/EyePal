package com.eyepal.app.services

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Rect
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
import com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

data class TextBlockInfo(val text: String, val bounds: Rect)

data class OCRResult(
    val text: String,
    val detectedLanguage: String,
    val textBlocks: List<TextBlockInfo>
)

class OCRService(private val context: Context) {
    private val latinRecognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    private val chineseRecognizer = TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build())
    private val japaneseRecognizer = TextRecognition.getClient(JapaneseTextRecognizerOptions.Builder().build())
    private val koreanRecognizer = TextRecognition.getClient(KoreanTextRecognizerOptions.Builder().build())

    private var lastSuccessfulRecognizer: TextRecognizer? = null
    private var lastRecognizerIndex = 0
    private val recognizers = listOf(latinRecognizer, chineseRecognizer, japaneseRecognizer, koreanRecognizer)
    private val recognizerLanguages = listOf("Latin", "Chinese", "Japanese", "Korean")

    suspend fun recognizeText(bitmap: Bitmap): OCRResult = suspendCancellableCoroutine { cont ->
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

    fun close() { recognizers.forEach { it.close() } }
}
