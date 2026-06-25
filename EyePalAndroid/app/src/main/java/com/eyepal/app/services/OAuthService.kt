package com.eyepal.app.services

import android.content.Context
import android.content.Intent
import android.net.Uri
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.security.SecureRandom

object OAuthService {
    private const val CLIENT_ID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private const val REDIRECT_URI = "http://localhost:1455/auth/callback"
    private const val AUTH_URL = "https://auth.openai.com/oauth/authorize"
    private const val TOKEN_URL = "https://auth.openai.com/oauth/token"
    private const val REVOKE_URL = "https://auth.openai.com/oauth/revoke"

    private var pendingCodeVerifier = ""
    private var pendingState = ""
    private var accessToken = ""
    private var refreshToken = ""

    fun getAuthIntent(context: Context): Intent {
        pendingCodeVerifier = generateRandomString(64)
        pendingState = generateRandomString(32)
        val codeChallenge = base64Url(sha256(pendingCodeVerifier.toByteArray()))
        val uri = Uri.parse(AUTH_URL).buildUpon()
            .appendQueryParameter("response_type", "code")
            .appendQueryParameter("client_id", CLIENT_ID)
            .appendQueryParameter("redirect_uri", REDIRECT_URI)
            .appendQueryParameter("scope", "openid profile email offline_access")
            .appendQueryParameter("code_challenge", codeChallenge)
            .appendQueryParameter("code_challenge_method", "S256")
            .appendQueryParameter("state", pendingState)
            .appendQueryParameter("originator", "eyepal_android")
            .build()
        return Intent(Intent.ACTION_VIEW, uri)
    }

    suspend fun handleCallback(uri: Uri): Boolean = withContext(Dispatchers.IO) {
        val code = uri.getQueryParameter("code") ?: return@withContext false
        val state = uri.getQueryParameter("state") ?: return@withContext false
        if (state != pendingState) return@withContext false
        try {
            val client = OkHttpClient()
            val body = "grant_type=authorization_code&client_id=$CLIENT_ID&code=$code&redirect_uri=$REDIRECT_URI&code_verifier=$pendingCodeVerifier"
                .toRequestBody("application/x-www-form-urlencoded".toMediaType())
            val request = Request.Builder().url(TOKEN_URL).post(body).build()
            val response = client.newCall(request).execute()
            val json = JSONObject(response.body?.string() ?: return@withContext false)
            accessToken = json.getString("access_token")
            refreshToken = json.optString("refresh_token", "")
            val prefs = (android.app.ActivityThread.currentApplication() ?: return@withContext false)
                .getSharedPreferences("oauth", 0)
            prefs.edit().putString("access_token", accessToken).putString("refresh_token", refreshToken).apply()
            true
        } catch (_: Exception) { false }
    }

    fun getAccessToken(context: Context): String {
        if (accessToken.isEmpty()) {
            val prefs = context.getSharedPreferences("oauth", 0)
            accessToken = prefs.getString("access_token", "") ?: ""
            refreshToken = prefs.getString("refresh_token", "") ?: ""
        }
        return accessToken
    }

    fun signOut(context: Context) {
        if (refreshToken.isNotEmpty()) {
            CoroutineScope(Dispatchers.IO).launch {
                try {
                    val client = OkHttpClient()
                    val body = "token=$refreshToken&client_id=$CLIENT_ID"
                        .toRequestBody("application/x-www-form-urlencoded".toMediaType())
                    client.newCall(Request.Builder().url(REVOKE_URL).post(body).build()).execute()
                } catch (_: Exception) {}
            }
        }
        accessToken = ""
        refreshToken = ""
        context.getSharedPreferences("oauth", 0).edit().clear().apply()
    }

    fun isSignedIn(context: Context) = getAccessToken(context).isNotEmpty()

    private fun generateRandomString(length: Int): String {
        val chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        return (1..length).map { chars[SecureRandom().nextInt(chars.length)] }.joinToString("")
    }

    private fun sha256(input: ByteArray): ByteArray {
        val digest = java.security.MessageDigest.getInstance("SHA-256")
        return digest.digest(input)
    }

    private fun base64Url(input: ByteArray): String {
        return android.util.Base64.encodeToString(input, android.util.Base64.NO_WRAP or android.util.Base64.URL_SAFE)
            .replace("+", "-").replace("/", "_").replace("=", "")
    }
}

private object CoroutineScope {
    fun launch(block: suspend () -> Unit) { kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.IO).launch { block() } }
}
private fun kotlinx.coroutines.CoroutineScope.launch(block: suspend kotlinx.coroutines.CoroutineScope.() -> Unit) = kotlinx.coroutines.GlobalScope.launch(kotlinx.coroutines.Dispatchers.IO) { block() }
