package com.eyepal.app.services

import android.graphics.Bitmap
import android.util.Base64
import com.eyepal.app.config.Defaults
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream

class UnauthorizedException(message: String) : Exception(message)

class OpenAIService(private val client: OkHttpClient = OkHttpClient()) {

    suspend fun describeImageCodexWithHistory(bitmap: Bitmap, accessToken: String, accountID: String, prompt: String, history: List<Map<String, Any>>): String = withContext(Dispatchers.IO) {
        val base64 = bitmapToBase64(bitmap)
        val payload = JSONObject().apply {
            put("model", Defaults.MODEL_ID)
            put("input", JSONArray().apply {
                for (turn in history) {
                    put(JSONObject().apply {
                        put("role", turn["role"])
                        put("content", turn["content"])
                    })
                }
                put(JSONObject().apply {
                    put("role", "user")
                    put("content", JSONArray().apply {
                        put(JSONObject().apply {
                            put("type", "input_text")
                            put("text", prompt)
                        })
                        put(JSONObject().apply {
                            put("type", "input_image")
                            put("image_url", "data:image/jpeg;base64,$base64")
                        })
                    })
                })
            })
        }

        val headers = mutableMapOf(
            "Authorization" to "Bearer $accessToken",
            "Content-Type" to "application/json",
            "User-Agent" to "EyePal/1.0"
        )
        if (accountID.isNotEmpty()) {
            headers["ChatGPT-Account-ID"] = accountID
        }

        val requestBuilder = Request.Builder()
            .url("https://chatgpt.com/backend-api/codex/responses")
            .post(payload.toString().toRequestBody("application/json".toMediaType()))
        for ((key, value) in headers) {
            requestBuilder.header(key, value)
        }

        val response = client.newCall(requestBuilder.build()).execute()
        val fullText = response.use { resp ->
            if (resp.code == 401) throw UnauthorizedException("Unauthorized (401)")
            resp.body?.charStream()?.buffered()?.use { reader ->
                var text = ""
                var line: String?
                while (reader.readLine().also { line = it } != null) {
                    val l = line ?: continue
                    if (l.startsWith("data: ") && l != "data: [DONE]") {
                        try {
                            val json = JSONObject(l.removePrefix("data: "))
                            val eventType = json.optString("type", "")
                            if (eventType == "response.output_text.delta") {
                                text += json.optString("delta", "")
                            } else if (eventType == "response.completed") {
                                val output = json.optJSONObject("response")
                                    ?.optJSONArray("output")
                                if (output != null) {
                                    for (i in 0 until output.length()) {
                                        val item = output.getJSONObject(i)
                                        if (item.optString("type") == "message") {
                                            val contentArr = item.optJSONArray("content")
                                            if (contentArr != null) {
                                                for (j in 0 until contentArr.length()) {
                                                    val contentItem = contentArr.getJSONObject(j)
                                                    if (contentItem.optString("type") == "output_text") {
                                                        text += contentItem.optString("text", "")
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        } catch (_: Exception) {}
                    }
                }
                text
            } ?: throw Exception("No response body")
        }

        fullText
    }

    private fun bitmapToBase64(bitmap: Bitmap): String {
        val stream = ByteArrayOutputStream()
        val maxDim = 640f
        val scale = minOf(1f, maxDim / maxOf(bitmap.width, bitmap.height))
        val resized = Bitmap.createScaledBitmap(bitmap, (bitmap.width * scale).toInt(), (bitmap.height * scale).toInt(), true)
        resized.compress(Bitmap.CompressFormat.JPEG, 72, stream)
        if (resized !== bitmap) resized.recycle()
        return Base64.encodeToString(stream.toByteArray(), Base64.NO_WRAP)
    }
}
