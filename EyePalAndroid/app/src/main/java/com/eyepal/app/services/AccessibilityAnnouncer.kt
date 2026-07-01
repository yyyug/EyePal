package com.eyepal.app.services

import android.content.Context
import android.speech.tts.TextToSpeech
import android.util.Log
import java.util.Locale

class AccessibilityAnnouncer(context: Context) {
    companion object {
        private const val TAG = "AccessibilityAnnouncer"
    }

    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var lastAnnouncement = ""
    private var lastTime = 0L

    // Callback for logging speech output
    var onSpeechOutput: ((String) -> Unit)? = null

    init {
        tts = TextToSpeech(context) { status ->
            if (status == TextToSpeech.SUCCESS) {
                ttsReady = true
                tts?.language = Locale.US
                Log.i(TAG, "TTS ready (English)")
            } else {
                Log.w(TAG, "TTS not available ($status) — audio glass may lack TTS engine")
            }
        }
    }

    fun announce(text: String, minimumInterval: Long = 0) {
        val now = System.currentTimeMillis()
        if (text == lastAnnouncement && now - lastTime < 2000) return
        if (now - lastTime < minimumInterval) return

        lastAnnouncement = text
        lastTime = now

        speak(text)
    }

    fun announceForced(text: String) {
        lastAnnouncement = text
        lastTime = System.currentTimeMillis()
        speak(text)
    }

    private fun speak(text: String) {
        // Log to console regardless of TTS availability
        Log.i(TAG, "SPEAK: $text")
        onSpeechOutput?.invoke(text)

        if (ttsReady) {
            tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "eyepal_${System.currentTimeMillis()}")
        }
    }

    fun shutdown() {
        tts?.stop()
        tts?.shutdown()
        tts = null
        ttsReady = false
    }
}
