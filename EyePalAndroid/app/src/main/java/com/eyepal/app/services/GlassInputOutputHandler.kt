package com.eyepal.app.services

import android.content.Context
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.util.Log
import android.view.InputDevice
import android.view.MotionEvent
import com.eyepal.app.R
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
    private val featureStrings by lazy {
        listOf(
            context.getString(R.string.feature_quick_recognition),
            context.getString(R.string.feature_details_recognition),
            context.getString(R.string.feature_read_text),
            context.getString(R.string.feature_floor_detection),
            context.getString(R.string.feature_chat),
            context.getString(R.string.feature_lyric_prompter)
        )
    }
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
        Log.i(TAG, "SPEAK: $text")
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
                speak(context.getString(R.string.tts_selected, featureStrings[currentFeatureIndex]))
                featureStrings[currentFeatureIndex]
            }
            is GlassTouchpadHandler.Gesture.DoubleTap -> {
                speak(context.getString(R.string.feature_quick_recognition))
                context.getString(R.string.feature_quick_recognition)
            }
            is GlassTouchpadHandler.Gesture.LongPress -> {
                speak(context.getString(R.string.feature_details_recognition))
                context.getString(R.string.feature_details_recognition)
            }
            is GlassTouchpadHandler.Gesture.SwipeUp -> {
                speak(context.getString(R.string.tts_back))
                context.getString(R.string.tts_back)
            }
            is GlassTouchpadHandler.Gesture.SwipeDown -> {
                currentFeatureIndex = (currentFeatureIndex + 1) % featureStrings.size
                speak(featureStrings[currentFeatureIndex])
                null
            }
            is GlassTouchpadHandler.Gesture.SwipeRight -> {
                currentFeatureIndex = (currentFeatureIndex + 1) % featureStrings.size
                speak(featureStrings[currentFeatureIndex])
                null
            }
            is GlassTouchpadHandler.Gesture.SwipeLeft -> {
                currentFeatureIndex = (currentFeatureIndex - 1 + featureStrings.size) % featureStrings.size
                speak(featureStrings[currentFeatureIndex])
                null
            }
        }
    }

    fun announceStatus(text: String) {
        speak(text)
    }
}
