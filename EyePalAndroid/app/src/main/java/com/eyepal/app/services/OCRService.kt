package com.eyepal.app.services

import android.content.Context
import android.graphics.Bitmap
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
import com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

class OCRService(private val context: Context) {
    private val latinRecognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    private val chineseRecognizer = TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build())
    private val japaneseRecognizer = TextRecognition.getClient(JapaneseTextRecognizerOptions.Builder().build())
    private val koreanRecognizer = TextRecognition.getClient(KoreanTextRecognizerOptions.Builder().build())

    suspend fun recognizeText(bitmap: Bitmap): String = suspendCancellableCoroutine { cont ->
        val image = InputImage.fromBitmap(bitmap, 0)
        latinRecognizer.process(image)
            .addOnSuccessListener { result ->
                val text = result.text
                if (text.isNotBlank()) {
                    cont.resume(text)
                } else {
                    chineseRecognizer.process(image)
                        .addOnSuccessListener { result2 ->
                            val text2 = result2.text
                            if (text2.isNotBlank()) {
                                cont.resume(text2)
                            } else {
                                japaneseRecognizer.process(image)
                                    .addOnSuccessListener { result3 ->
                                        val text3 = result3.text
                                        if (text3.isNotBlank()) {
                                            cont.resume(text3)
                                        } else {
                                            koreanRecognizer.process(image)
                                                .addOnSuccessListener { result4 ->
                                                    cont.resume(result4.text.ifBlank { "No text detected" })
                                                }
                                                .addOnFailureListener { cont.resumeWithException(it) }
                                        }
                                    }
                                    .addOnFailureListener { cont.resumeWithException(it) }
                            }
                        }
                        .addOnFailureListener { cont.resumeWithException(it) }
                }
            }
            .addOnFailureListener { cont.resumeWithException(it) }
    }

    fun close() {
        latinRecognizer.close()
        chineseRecognizer.close()
        japaneseRecognizer.close()
        koreanRecognizer.close()
    }
}
