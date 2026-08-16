package com.eyepal.app.services

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID

class FaceRecognitionLogStore(private val context: Context) {
    data class LogEntry(val id: String = UUID.randomUUID().toString(), val message: String, val timestamp: Long = System.currentTimeMillis())

    private val entries = mutableListOf<LogEntry>()
    private val file = File(context.filesDir, "face_log.json")

    fun append(message: String) {
        entries.add(LogEntry(message = message))
        if (entries.size > 200) entries.removeAt(0)
        save()
    }

    fun getEntries(): List<LogEntry> = entries.toList()
    fun clear() { entries.clear(); save() }
    fun copyAll(): String = entries.joinToString("\n") { "[${it.timestamp}] ${it.message}" }

    private fun save() {
        val arr = JSONArray()
        entries.forEach { arr.put(JSONObject().put("id", it.id).put("message", it.message).put("timestamp", it.timestamp)) }
        file.writeText(arr.toString())
    }

    fun load() {
        if (!file.exists()) return
        entries.clear()
        val arr = JSONArray(file.readText())
        for (i in 0 until arr.length()) {
            val obj = arr.getJSONObject(i)
            entries.add(LogEntry(obj.getString("id"), obj.getString("message"), obj.getLong("timestamp")))
        }
    }
}
