package com.eyepal.app.services

import android.os.Handler
import android.os.Looper
import android.view.MotionEvent
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * Handles touchpad gestures from audio glasses.
 * Audio glasses have a small touchpad on the temple arm.
 * Supports: tap, double-tap, swipe up/down/left/right, long-press.
 *
 * Gesture mapping for EyePal:
 * - Tap: Confirm / activate current action
 * - Swipe Up: Next item / scroll up
 * - Swipe Down: Previous item / scroll down
 * - Swipe Right: Quick Recognition
 * - Swipe Left: Back
 * - Double-tap: Read Text
 * - Long-press: Details Recognition
 */
class GlassTouchpadHandler {
    companion object {
        private const val TAG = "GlassTouchpadHandler"
        private const val SWIPE_THRESHOLD = 50
        private const val TAP_TIMEOUT = 300L
        private const val LONG_PRESS_TIMEOUT = 500L
        private const val DOUBLE_TAP_TIMEOUT = 300L
    }

    sealed class Gesture {
        data object Tap : Gesture()
        data object DoubleTap : Gesture()
        data object LongPress : Gesture()
        data object SwipeUp : Gesture()
        data object SwipeDown : Gesture()
        data object SwipeLeft : Gesture()
        data object SwipeRight : Gesture()
    }

    private val _gesture = MutableStateFlow<Gesture?>(null)
    val gesture: StateFlow<Gesture?> = _gesture

    private val handler = Handler(Looper.getMainLooper())
    private var downTime = 0L
    private var downX = 0f
    private var downY = 0f
    private var lastTapTime = 0L
    private var tapCount = 0
    private var pendingTapRunnable: Runnable? = null

    fun onMotionEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downTime = System.currentTimeMillis()
                downX = event.x
                downY = event.y
                return true
            }
            MotionEvent.ACTION_UP -> {
                val duration = System.currentTimeMillis() - downTime
                val dx = event.x - downX
                val dy = event.y - downY

                if (duration < TAP_TIMEOUT && Math.abs(dx) < SWIPE_THRESHOLD && Math.abs(dy) < SWIPE_THRESHOLD) {
                    val now = System.currentTimeMillis()
                    pendingTapRunnable?.let { handler.removeCallbacks(it) }
                    pendingTapRunnable = null
                    if (now - lastTapTime < DOUBLE_TAP_TIMEOUT) {
                        _gesture.value = Gesture.DoubleTap
                        tapCount = 0
                    } else {
                        tapCount = 1
                        val runnable = Runnable {
                            if (tapCount == 1) {
                                _gesture.value = Gesture.Tap
                                tapCount = 0
                            }
                        }
                        pendingTapRunnable = runnable
                        handler.postDelayed(runnable, DOUBLE_TAP_TIMEOUT)
                    }
                    lastTapTime = now
                } else if (duration >= LONG_PRESS_TIMEOUT && Math.abs(dx) < SWIPE_THRESHOLD && Math.abs(dy) < SWIPE_THRESHOLD) {
                    _gesture.value = Gesture.LongPress
                } else {
                    // Swipe
                    if (Math.abs(dx) > Math.abs(dy)) {
                        _gesture.value = if (dx > 0) Gesture.SwipeRight else Gesture.SwipeLeft
                    } else {
                        _gesture.value = if (dy > 0) Gesture.SwipeDown else Gesture.SwipeUp
                    }
                }
                return true
            }
        }
        return false
    }

    fun clearGesture() {
        _gesture.value = null
    }
}
