package com.eyepal.app.services

import android.content.Context
import android.graphics.Bitmap
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
import com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
import com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

class OCRService(private val context: Context) {
    private val latinRecognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    private val chineseRecognizer = TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build())
    private val devanagariRecognizer = TextRecognition.getClient(DevanagariTextRecognizerOptions.Builder().build())
    private val japaneseRecognizer = TextRecognition.getClient(JapaneseTextRecognizerOptions.Builder().build())
    private val koreanRecognizer = TextRecognition.getClient(KoreanTextRecognizerOptions.Builder().build())

    private var lastSuccessfulRecognizer: TextRecognizer? = null
    private val recognizers = listOf(latinRecognizer, chineseRecognizer, devanagariRecognizer, japaneseRecognizer, koreanRecognizer)

    suspend fun recognizeText(bitmap: Bitmap): String = suspendCancellableCoroutine { cont ->
        val image = InputImage.fromBitmap(bitmap, 0)

        fun tryRecognizer(index: Int) {
            if (index >= recognizers.size) { cont.resume("No text detected"); return }
            val recognizer = recognizers[index]
            recognizer.process(image)
                .addOnSuccessListener { result ->
                    val text = result.text
                    if (text.isNotBlank()) {
                        lastSuccessfulRecognizer = recognizer
                        cont.resume(text)
                    } else {
                        tryRecognizer(index + 1)
                    }
                }
                .addOnFailureListener { tryRecognizer(index + 1) }
        }

        if (lastSuccessfulRecognizer != null) {
            lastSuccessfulRecognizer!!.process(image)
                .addOnSuccessListener { result ->
                    if (result.text.isNotBlank()) { cont.resume(result.text) }
                    else { tryRecognizer(0) }
                }
                .addOnFailureListener { tryRecognizer(0) }
        } else {
            tryRecognizer(0)
        }
    }

    fun close() { recognizers.forEach { it.close() } }
}
