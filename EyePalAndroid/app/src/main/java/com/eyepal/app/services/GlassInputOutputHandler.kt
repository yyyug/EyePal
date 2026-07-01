package com.eyepal.app.services

import android.content.Context
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.util.Log
import android.view.InputDevice
import android.view.MotionEvent
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.util.Locale

/**
 * Handles audio glasses input (touchpad) and output (TTS).
 * Runs in the phone app — receives input events from glasses via system.
 * Provides TTS audio feedback for touchpad gestures.
 */
class GlassInputOutputHandler(private val context: Context) {
    companion object {
        private const val TAG = "GlassIOHandler"
    }

    // TTS for voice feedback
    private var tts: TextToSpeech? = null
    private var ttsReady = false

    // Touchpad handler
    val touchpadHandler = GlassTouchpadHandler()

    // Current screen navigation state
    private val _currentScreen = MutableStateFlow("Home")
    val currentScreen: StateFlow<String> = _currentScreen

    // Feature list for navigation
    private val features = listOf(
        "Quick Recognition",
        "Details Recognition",
        "Read Text",
        "Floor Detection",
        "Chat",
        "Lyric Prompter"
    )
    private var currentFeatureIndex = 0

    fun initialize() {
        tts = TextToSpeech(context) { status ->
            if (status == TextToSpeech.SUCCESS) {
                ttsReady = true
                tts?.language = Locale.getDefault()
                tts?.setSpeechRate(1.1f)
                Log.i(TAG, "TTS initialized")
            }
        }
    }

    fun shutdown() {
        tts?.stop()
        tts?.shutdown()
        tts = null
    }

    fun speak(text: String) {
        if (ttsReady) {
            tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "eyepal_${System.currentTimeMillis()}")
        }
    }

    /**
     * Handle a touchpad gesture and provide TTS feedback.
     * Returns the navigation action to perform.
     */
    fun handleGesture(gesture: GlassTouchpadHandler.Gesture): String? {
        return when (gesture) {
            is GlassTouchpadHandler.Gesture.Tap -> {
                speak("Selected: ${features[currentFeatureIndex]}")
                features[currentFeatureIndex]
            }
            is GlassTouchpadHandler.Gesture.DoubleTap -> {
                speak("Quick Recognition")
                "Quick Recognition"
            }
            is GlassTouchpadHandler.Gesture.LongPress -> {
                speak("Details Recognition")
                "Details Recognition"
            }
            is GlassTouchpadHandler.Gesture.SwipeUp -> {
                currentFeatureIndex = (currentFeatureIndex - 1 + features.size) % features.size
                speak(features[currentFeatureIndex])
                null
            }
            is GlassTouchpadHandler.Gesture.SwipeDown -> {
                currentFeatureIndex = (currentFeatureIndex + 1) % features.size
                speak(features[currentFeatureIndex])
                null
            }
            is GlassTouchpadHandler.Gesture.SwipeRight -> {
                speak("Quick Recognition")
                "Quick Recognition"
            }
            is GlassTouchpadHandler.Gesture.SwipeLeft -> {
                speak("Back")
                "Back"
            }
        }
    }

    fun announceStatus(text: String) {
        speak(text)
    }
}
