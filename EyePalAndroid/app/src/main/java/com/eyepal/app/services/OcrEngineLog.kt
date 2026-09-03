package com.eyepal.app.services

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Small in-memory ring buffer of OCR engine log lines, surfaced on the Text Recognition
 * settings screen so failures can be diagnosed on-device without a debugger.
 */
object OcrEngineLog {
    private const val MAX_ENTRIES = 200
    private val messages = CopyOnWriteArrayList<String>()
    private val dateFormat = SimpleDateFormat("MM-dd HH:mm:ss", Locale.getDefault())

    fun add(message: String) {
        val line = "[${dateFormat.format(Date())}] $message"
        messages.add(line)
        if (messages.size > MAX_ENTRIES) {
            messages.subList(0, messages.size - MAX_ENTRIES).clear()
        }
    }

    fun snapshot(): List<String> = messages.toList()

    fun clear() = messages.clear()

    fun copyAll(): String = messages.joinToString("\n")
}
