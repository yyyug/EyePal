package com.eyepal.app.services

import android.content.Context
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

class MoondreamService(private val client: OkHttpClient = OkHttpClient()) {

    suspend fun describeImage(bitmap: Bitmap, apiKey: String, prompt: String = "Describe what you see in this image briefly."): String = withContext(Dispatchers.IO) {
        val base64 = bitmapToBase64(bitmap)
        val payload = JSONObject().apply {
            put("image_url", "data:image/jpeg;base64,$base64")
            put("question", prompt)
        }

        val request = Request.Builder()
            .url("https://api.moondream.ai/v1/query")
            .post(payload.toString().toRequestBody("application/json".toMediaType()))
            .header("X-Moondream-Auth", apiKey)
            .build()

        val response = client.newCall(request).execute()
        val body = response.body?.string() ?: throw Exception("No response from Moondream API")
        if (!response.isSuccessful) {
            val errorMsg = try { JSONObject(body).optString("error", body) } catch (_: Exception) { body }
            throw Exception("Moondream API error ${response.code}: $errorMsg")
        }
        val json = JSONObject(body)
        if (!json.has("answer")) throw Exception("Unexpected response: missing 'answer' field")
        json.getString("answer")
    }

    private fun bitmapToBase64(bitmap: Bitmap): String {
        val stream = ByteArrayOutputStream()
        val maxDim = 320f
        val scale = minOf(1f, maxDim / maxOf(bitmap.width, bitmap.height))
        val resized = Bitmap.createScaledBitmap(bitmap, (bitmap.width * scale).toInt(), (bitmap.height * scale).toInt(), true)
        resized.compress(Bitmap.CompressFormat.JPEG, 50, stream)
        if (resized !== bitmap) resized.recycle()
        return Base64.encodeToString(stream.toByteArray(), Base64.NO_WRAP)
    }
}
