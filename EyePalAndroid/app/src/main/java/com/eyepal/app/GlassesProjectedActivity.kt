package com.eyepal.app

import android.content.Context
import android.os.Bundle
import android.util.Log
import android.view.InputDevice
import android.view.MotionEvent
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.xr.glimmer.onIndirectPointerGesture
import com.eyepal.app.services.GlassInputOutputHandler
import com.eyepal.app.services.GlassTouchpadHandler

/**
 * GlassesProjectedActivity — projected to the glasses display.
 *
 * Two input paths:
 * 1. onIndirectPointerGesture (Compose) — handles real glasses touchpad via XR SDK
 * 2. dispatchTouchEvent — fallback for emulator testing (regular touch events)
 */
class GlassesProjectedActivity : ComponentActivity() {
    companion object {
        private const val TAG = "GlassesProjected"
        var projectedContext: Context? = null
            private set
    }

    private lateinit var glassIO: GlassInputOutputHandler

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        projectedContext = baseContext
        Log.i(TAG, "Projected activity created")

        glassIO = GlassInputOutputHandler(applicationContext)
        glassIO.initialize()

        setContent {
            GlassesTouchpadScreen(glassIO)
        }

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
        Log.i(TAG, "Projected activity destroyed")
    }

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

@Composable
fun GlassesTouchpadScreen(glassIO: GlassInputOutputHandler) {
    val focusRequester = remember { FocusRequester() }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .focusRequester(focusRequester)
            .onFocusChanged { state ->
                Log.d("GlassesProjected", "Focus: ${state.isFocused}, hasFocus: ${state.hasFocus}")
            }
            .focusable()
            .onIndirectPointerGesture(
                enabled = true,
                onClick = {
                    Log.i("GlassesProjected", "onClick → Tap")
                    glassIO.handleGesture(GlassTouchpadHandler.Gesture.Tap)
                },
                onSwipeForward = {
                    Log.i("GlassesProjected", "onSwipeForward → next feature")
                    glassIO.handleGesture(GlassTouchpadHandler.Gesture.SwipeRight)
                },
                onSwipeBackward = {
                    Log.i("GlassesProjected", "onSwipeBackward → previous feature")
                    glassIO.handleGesture(GlassTouchpadHandler.Gesture.SwipeLeft)
                }
            )
    )

    LaunchedEffect(Unit) {
        focusRequester.requestFocus()
    }
}
