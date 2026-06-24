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
import java.io.ByteArrayOutputStream

class OpenAIService(private val client: OkHttpClient = OkHttpClient()) {

    suspend fun describeImage(bitmap: Bitmap, apiKey: String, prompt: String): String = withContext(Dispatchers.IO) {
        val base64 = bitmapToBase64(bitmap)
        val payload = JSONObject().apply {
            put("model", "gpt-4o-mini")
            put("messages", JSONArray().apply {
                put(JSONObject().apply {
                    put("role", "user")
                    put("content", JSONArray().apply {
                        put(JSONObject().apply {
                            put("type", "text")
                            put("text", prompt)
                        })
                        put(JSONObject().apply {
                            put("type", "image_url")
                            put("image_url", JSONObject().apply {
                                put("url", "data:image/jpeg;base64,$base64")
                            })
                        })
                    })
                })
            })
            put("max_tokens", 1000)
        }

        val request = Request.Builder()
            .url("https://api.openai.com/v1/chat/completions")
            .post(payload.toString().toRequestBody("application/json".toMediaType()))
            .header("Authorization", "Bearer $apiKey")
            .header("Content-Type", "application/json")
            .build()

        val response = client.newCall(request).execute()
        val body = response.body?.string() ?: throw Exception("No response")
        val json = JSONObject(body)
        json.getJSONArray("choices").getJSONObject(0)
            .getJSONObject("message").getString("content")
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
