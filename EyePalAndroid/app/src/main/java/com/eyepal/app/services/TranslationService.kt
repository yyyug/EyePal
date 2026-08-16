package com.eyepal.app.services

import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.Translator
import com.google.mlkit.nl.translate.TranslatorOptions
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

class TranslationService {
    private var translator: Translator? = null
    private var sourceLang: String = "en"
    private var targetLang: String = ""

    suspend fun setLanguages(source: String, target: String) {
        if (source == sourceLang && target == targetLang && translator != null) return
        translator?.close()
        sourceLang = source
        targetLang = target

        if (!SUPPORTED_CODES.contains(source) || !SUPPORTED_CODES.contains(target)) return

        val options = TranslatorOptions.Builder()
            .setSourceLanguage(source)
            .setTargetLanguage(target)
            .build()
        translator = Translation.getClient(options)

        val conditions = DownloadConditions.Builder()
            .requireWifi()
            .build()
        suspendCancellableCoroutine { cont ->
            translator!!.downloadModelIfNeeded(conditions)
                .addOnSuccessListener { cont.resume(true) }
                .addOnFailureListener { cont.resume(false) }
        }
    }

    suspend fun translate(text: String): String {
        val t = translator ?: return text
        return suspendCancellableCoroutine { cont ->
            t.translate(text)
                .addOnSuccessListener { result -> cont.resume(result) }
                .addOnFailureListener { cont.resume(text) }
        }
    }

    fun close() {
        translator?.close()
        translator = null
    }

    companion object {
        private val SUPPORTED_CODES = setOf(
            "en", "zh", "ja", "ko", "es", "fr", "de", "pt", "it", "ru",
            "ar", "hi", "th", "vi", "nl", "pl", "tr", "uk"
        )
        val SUPPORTED_LANGUAGES = listOf(
            "en" to "English", "zh" to "Chinese", "ja" to "Japanese",
            "ko" to "Korean", "es" to "Spanish", "fr" to "French",
            "de" to "German", "pt" to "Portuguese", "it" to "Italian",
            "ru" to "Russian", "ar" to "Arabic", "hi" to "Hindi",
            "th" to "Thai", "vi" to "Vietnamese", "nl" to "Dutch",
            "pl" to "Polish", "tr" to "Turkish", "uk" to "Ukrainian"
        )
    }
}
