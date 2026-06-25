package com.eyepal.app.services

import android.content.Context
import android.os.Bundle
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityManager

class AccessibilityAnnouncer(private val context: Context) {
    private val accessibilityManager = context.getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
    private var lastAnnouncement = ""
    private var lastTime = 0L

    fun announce(text: String, minimumInterval: Long = 0) {
        val now = System.currentTimeMillis()
        if (text == lastAnnouncement && now - lastTime < 2000) return
        if (now - lastTime < minimumInterval) return

        lastAnnouncement = text
        lastTime = now

        val event = AccessibilityEvent.obtain(AccessibilityEvent.TYPE_ANNOUNCEMENT).apply {
            this.text.add(text)
            this.className = "com.eyepal.app.MainActivity"
        }
        accessibilityManager.sendAccessibilityEvent(event)
    }

    fun announceForced(text: String) {
        lastAnnouncement = text
        lastTime = System.currentTimeMillis()
        val event = AccessibilityEvent.obtain(AccessibilityEvent.TYPE_ANNOUNCEMENT).apply {
            this.text.add(text)
            this.className = "com.eyepal.app.MainActivity"
        }
        accessibilityManager.sendAccessibilityEvent(event)
    }
}
