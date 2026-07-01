package com.eyepal.app

import android.os.Bundle
import android.util.Log
import android.view.InputDevice
import android.view.MotionEvent
import androidx.activity.ComponentActivity
import com.eyepal.app.services.GlassInputOutputHandler

/**
 * GlassesProjectedActivity handles the XR projected lifecycle for audio glasses.
 *
 * For audio glasses (no display):
 * - Activity stays alive to maintain projected lifecycle
 * - Receives touchpad input events from glasses
 * - Provides TTS audio feedback
 * - Routes touchpad gestures to navigation
 */
class GlassesProjectedActivity : ComponentActivity() {
    companion object {
        private const val TAG = "GlassesProjected"
    }

    private lateinit var glassIO: GlassInputOutputHandler

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        glassIO = GlassInputOutputHandler(applicationContext)
        glassIO.initialize()
        Log.i(TAG, "Projected activity created")
    }

    override fun onResume() {
        super.onResume()
        Log.i(TAG, "Projected activity resumed — glasses connected")
    }

    override fun onPause() {
        super.onPause()
        Log.i(TAG, "Projected activity paused")
    }

    override fun onDestroy() {
        super.onDestroy()
        glassIO.shutdown()
        Log.i(TAG, "Projected activity destroyed")
    }

    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        // Forward touchpad events from glasses to gesture handler
        val device = ev.source
        if (device and InputDevice.SOURCE_TOUCHSCREEN != 0 || device and InputDevice.SOURCE_CLASS_POINTER != 0) {
            glassIO.touchpadHandler.onMotionEvent(ev)

            // Collect gesture and announce
            val gesture = glassIO.touchpadHandler.gesture.value
            if (gesture != null) {
                glassIO.handleGesture(gesture)
                glassIO.touchpadHandler.clearGesture()
            }
        }
        return super.dispatchTouchEvent(ev)
    }
}
