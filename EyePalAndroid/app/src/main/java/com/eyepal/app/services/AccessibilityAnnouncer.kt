package com.eyepal.app.services

import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityManager
import java.util.Locale

class AccessibilityAnnouncer(private val context: Context) {
    companion object {
        private const val TAG = "AccessibilityAnnouncer"
        private const val DEFAULT_MINIMUM_INTERVAL = 2000L
    }

    private var lastAnnouncement = ""
    private var lastTime = 0L
    private val accessibilityManager = context.getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager

    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var pendingText: String? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    var onSpeechOutput: ((String) -> Unit)? = null

    init {
        tts = TextToSpeech(context) { status ->
            if (status == TextToSpeech.SUCCESS) {
                ttsReady = true
                tts?.language = Locale.getDefault()
                tts?.setSpeechRate(1.1f)
                pendingText?.let { text ->
                    pendingText = null
                    tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "eyepal_${System.currentTimeMillis()}")
                }
                Log.i(TAG, "TTS initialized")
            }
        }
    }

    private val hasSpokenAccessibilityService: Boolean
        get() = accessibilityManager
            ?.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_SPOKEN)
            ?.isNotEmpty() == true

    fun announce(text: String, minimumInterval: Long = 0) {
        val now = System.currentTimeMillis()
        val effectiveInterval = if (minimumInterval > 0) minimumInterval else DEFAULT_MINIMUM_INTERVAL
        if (text == lastAnnouncement && now - lastTime < effectiveInterval) return
        if (now - lastTime < minimumInterval) return

        lastAnnouncement = text
        lastTime = now

        announceToTalkBack(text)
    }

    fun announceForced(text: String) {
        lastAnnouncement = text
        lastTime = System.currentTimeMillis()
        announceToTalkBack(text)
    }

    private fun announceToTalkBack(text: String) {
        Log.i(TAG, "ANNOUNCE: $text")
        onSpeechOutput?.invoke(text)

        val post: () -> Unit = {
            if (hasSpokenAccessibilityService) {
                val event = AccessibilityEvent.obtain().apply {
                    eventType = AccessibilityEvent.TYPE_ANNOUNCEMENT
                    className = AccessibilityAnnouncer::class.java.name
                    packageName = context.packageName
                    this.text.add(text)
                }
                try {
                    accessibilityManager?.sendAccessibilityEvent(event)
                } finally {
                    event.recycle()
                }
            } else if (ttsReady) {
                tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "eyepal_${System.currentTimeMillis()}")
            } else {
                pendingText = text
            }
        }

        // TYPE_ANNOUNCEMENT/TTS must be issued on the main thread for reliable delivery to
        // TalkBack; if announce() is called from a background thread, hop to the main looper.
        if (Looper.myLooper() == Looper.getMainLooper()) {
            post()
        } else {
            mainHandler.post(post)
        }
    }

    fun shutdown() {
        pendingText = null
        tts?.stop()
        tts?.shutdown()
        tts = null
        ttsReady = false
    }
}
