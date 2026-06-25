package com.eyepal.app.services

import android.graphics.Bitmap
import android.util.Base64
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.ByteArrayOutputStream
import java.io.InputStreamReader

class OpenAIService(private val client: OkHttpClient = OkHttpClient()) {

    data class ConversationTurn(val role: String, val content: String, val imageData: String? = null)

    private val conversations = mutableMapOf<String, MutableList<ConversationTurn>>()

    suspend fun describeImage(bitmap: Bitmap, apiKey: String, prompt: String, conversationId: String = "default"): String = withContext(Dispatchers.IO) {
        val base64 = bitmapToBase64(bitmap)
        val history = conversations.getOrPut(conversationId) { mutableListOf() }

        history.add(ConversationTurn(role = "user", content = prompt, imageData = base64))

        val messagesArray = JSONArray()
        for (turn in history) {
            val msg = JSONObject().put("role", turn.role)
            if (turn.imageData != null) {
                msg.put("content", JSONArray().apply {
                    put(JSONObject().apply { put("type", "text"); put("text", turn.content) })
                    put(JSONObject().apply { put("type", "image_url"); put("image_url", JSONObject().apply { put("url", "data:image/jpeg;base64,${turn.imageData}") }) })
                })
            } else {
                msg.put("content", turn.content)
            }
            messagesArray.put(msg)
        }

        val payload = JSONObject().apply {
            put("model", "gpt-4o-mini")
            put("messages", messagesArray)
            put("max_tokens", 1000)
            put("stream", true)
        }

        val request = Request.Builder()
            .url("https://api.openai.com/v1/chat/completions")
            .post(payload.toString().toRequestBody("application/json".toMediaType()))
            .header("Authorization", "Bearer $apiKey")
            .header("Content-Type", "application/json")
            .build()

        val response = client.newCall(request).execute()
        val reader = BufferedReader(InputStreamReader(response.body?.byteStream() ?: throw Exception("No response")))
        var fullText = ""
        var line: String?
        while (reader.readLine().also { line = it } != null) {
            val l = line ?: continue
            if (l.startsWith("data: ") && l != "data: [DONE]") {
                try {
                    val json = JSONObject(l.removePrefix("data: "))
                    val delta = json.getJSONArray("choices").getJSONObject(0)
                        .optJSONObject("delta")?.optString("content", "") ?: ""
                    fullText += delta
                } catch (_: Exception) {}
            }
        }

        history.add(ConversationTurn(role = "assistant", content = fullText))
        fullText
    }

    fun clearConversation(conversationId: String = "default") {
        conversations.remove(conversationId)
    }

    private fun bitmapToBase64(bitmap: Bitmap): String {
        val stream = ByteArrayOutputStream()
        val maxDim = 640f
        val scale = minOf(1f, maxDim / maxOf(bitmap.width, bitmap.height))
        val resized = Bitmap.createScaledBitmap(bitmap, (bitmap.width * scale).toInt(), (bitmap.height * scale).toInt(), true)
        resized.compress(Bitmap.CompressFormat.JPEG, 72, stream)
        return Base64.encodeToString(stream.toByteArray(), Base64.NO_WRAP)
    }
}
