package com.eyepal.app.services

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Base64
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
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
    private val scope = CoroutineScope(Dispatchers.IO)

    private var pendingCodeVerifier = ""
    private var pendingState = ""
    private var accessToken = ""
    private var refreshToken = ""
    private var accountID = ""

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

    suspend fun handleCallback(uri: Uri, context: Context): Boolean = withContext(Dispatchers.IO) {
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
            accountID = decodeAccountID(accessToken)
            saveTokens(context)
            true
        } catch (_: Exception) { false }
    }

    fun getAccessToken(context: Context): String {
        if (accessToken.isEmpty()) loadTokens(context)
        return accessToken
    }

    fun getAccountID(context: Context): String {
        if (accountID.isEmpty()) loadTokens(context)
        return accountID
    }

    private fun decodeAccountID(jwt: String): String {
        val segments = jwt.split(".")
        if (segments.size < 2) return ""
        return try {
            var payload = segments[1].replace("-", "+").replace("_", "/")
            val remainder = payload.length % 4
            if (remainder != 0) payload += "=".repeat(4 - remainder)
            val data = Base64.decode(payload, Base64.DEFAULT)
            val json = JSONObject(String(data))
            val keys = listOf("chatgpt_account_id", "account_id", "https://api.openai.com/chatgpt_account_id", "https://chatgpt.com/account_id")
            keys.firstNotNullOfOrNull { json.optString(it, "").ifEmpty { null } } ?: ""
        } catch (_: Exception) { "" }
    }

    fun signOut(context: Context) {
        if (refreshToken.isNotEmpty()) {
            scope.launch {
                try {
                    val client = OkHttpClient()
                    val body = "token=$refresh_token&client_id=$CLIENT_ID"
                        .toRequestBody("application/x-www-form-urlencoded".toMediaType())
                    client.newCall(Request.Builder().url(REVOKE_URL).post(body).build()).execute()
                } catch (_: Exception) {}
            }
        }
        accessToken = ""
        refreshToken = ""
        accountID = ""
        context.getSharedPreferences("oauth", 0).edit().clear().apply()
    }

    fun isSignedIn(context: Context) = getAccessToken(context).isNotEmpty()

    private fun saveTokens(context: Context) {
        context.getSharedPreferences("oauth", 0).edit()
            .putString("access_token", accessToken)
            .putString("refresh_token", refreshToken)
            .putString("account_id", accountID)
            .apply()
    }

    private fun loadTokens(context: Context) {
        val prefs = context.getSharedPreferences("oauth", 0)
        accessToken = prefs.getString("access_token", "") ?: ""
        refreshToken = prefs.getString("refresh_token", "") ?: ""
        accountID = prefs.getString("account_id", "") ?: ""
    }

    private fun generateRandomString(length: Int): String {
        val chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        return (1..length).map { chars[SecureRandom().nextInt(chars.length)] }.joinToString("")
    }

    private fun sha256(input: ByteArray): ByteArray = java.security.MessageDigest.getInstance("SHA-256").digest(input)

    private fun base64Url(input: ByteArray): String {
        return Base64.encodeToString(input, Base64.NO_WRAP or Base64.URL_SAFE)
            .replace("+", "-").replace("/", "_").replace("=", "")
    }
}
