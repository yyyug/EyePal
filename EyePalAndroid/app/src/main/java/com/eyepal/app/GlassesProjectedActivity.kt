package com.eyepal.app

import android.content.Context
import android.os.Bundle
import android.util.Log
import android.view.InputDevice
import android.view.MotionEvent
import androidx.activity.ComponentActivity
import com.eyepal.app.services.GlassInputOutputHandler

/**
 * GlassesProjectedActivity — runs ON the glasses (or AVD glasses simulation).
 *
 * Per XR SDK docs:
 * - This activity's own context IS a projected context
 * - It handles touchpad input from the glasses
 * - It provides TTS audio feedback
 * - It shares the projected context with the phone app via a static holder
 *
 * Phone app flow:
 *   PhoneActivity → reads SharedProjectedContext → uses for CameraX / AudioRecord
 *
 * Glasses projected activity flow:
 *   GlassesProjectedActivity → receives touchpad gestures → TTS feedback
 */
class GlassesProjectedActivity : ComponentActivity() {
    companion object {
        private const val TAG = "GlassesProjected"
        /**
         * Shared projected context for the phone app to access glasses hardware.
         * Set by this activity, read by GoogleGlassService.
         */
        var projectedContext: Context? = null
            private set
    }

    private lateinit var glassIO: GlassInputOutputHandler

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // This activity's base context IS the projected context for glasses hardware
        projectedContext = baseContext
        Log.i(TAG, "Projected activity created — projected context available")

        glassIO = GlassInputOutputHandler(applicationContext)
        glassIO.initialize()
        glassIO.speak("EyePal connected to glasses")
    }

    override fun onResume() {
        super.onResume()
        projectedContext = baseContext
        Log.i(TAG, "Projected activity resumed")
    }

    override fun onPause() {
        super.onPause()
        Log.i(TAG, "Projected activity paused")
    }

    override fun onDestroy() {
        super.onDestroy()
        projectedContext = null
        glassIO.shutdown()
        Log.i(TAG, "Projected activity destroyed — projected context released")
    }

    /**
     * Receive touchpad input from glasses.
     * Audio glasses touchpad sends MotionEvent events.
     */
    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        val device = ev.source
        if (device and InputDevice.SOURCE_TOUCHSCREEN != 0 ||
            device and InputDevice.SOURCE_CLASS_POINTER != 0) {

            Log.d(TAG, "Touchpad event: action=${ev.actionMasked} x=${ev.x} y=${ev.y} source=${device}")

            glassIO.touchpadHandler.onMotionEvent(ev)
            val gesture = glassIO.touchpadHandler.gesture.value
            if (gesture != null) {
                Log.i(TAG, "Gesture detected: $gesture")
                glassIO.handleGesture(gesture)
                glassIO.touchpadHandler.clearGesture()
            }
        }
        return super.dispatchTouchEvent(ev)
    }
}
