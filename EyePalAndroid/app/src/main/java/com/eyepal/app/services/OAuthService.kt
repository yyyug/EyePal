package com.eyepal.app.services

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.util.Base64
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
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

    private val secureRandom = SecureRandom()

    private fun encryptedPrefs(context: Context): SharedPreferences {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        return EncryptedSharedPreferences.create(
            context,
            "oauth_encrypted",
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    }
    private var pendingCodeVerifier = ""
    private var pendingState = ""
    private var accessToken = ""
    private var refreshToken = ""
    private var accountID = ""
    private var expiresAt = 0L

    fun getAuthorizationUrl(): String {
        pendingCodeVerifier = generateRandomString(64)
        pendingState = generateRandomString(32)
        val codeChallenge = base64Url(sha256(pendingCodeVerifier.toByteArray()))
        return Uri.parse(AUTH_URL).buildUpon()
            .appendQueryParameter("response_type", "code")
            .appendQueryParameter("client_id", CLIENT_ID)
            .appendQueryParameter("redirect_uri", REDIRECT_URI)
            .appendQueryParameter("scope", "openid profile email offline_access")
            .appendQueryParameter("code_challenge", codeChallenge)
            .appendQueryParameter("code_challenge_method", "S256")
            .appendQueryParameter("state", pendingState)
            .appendQueryParameter("originator", "eyepal_android")
            .appendQueryParameter("id_token_add_organizations", "true")
            .appendQueryParameter("codex_cli_simplified_flow", "true")
            .build()
            .toString()
    }

    fun getAuthIntent(context: Context): Intent {
        return Intent(Intent.ACTION_VIEW, Uri.parse(getAuthorizationUrl()))
    }

    fun getStoredAccessToken(context: Context): String {
        if (accessToken.isEmpty()) loadTokens(context)
        return accessToken
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
            val json = JSONObject(client.newCall(request).execute().use { it.body?.string() ?: return@withContext false })
            accessToken = json.getString("access_token")
            refreshToken = json.optString("refresh_token", "")
            accountID = decodeAccountID(accessToken)
            val expiresIn = json.optLong("expires_in", 0)
            expiresAt = System.currentTimeMillis() + expiresIn * 1000 - 60000
            saveTokens(context)
            true
        } catch (_: Exception) { false }
    }

    suspend fun getAccessToken(context: Context): String {
        return getValidAccessToken(context)
    }

    fun shouldRefresh(context: Context): Boolean {
        if (expiresAt == 0L) loadTokens(context)
        return System.currentTimeMillis() > expiresAt
    }

    suspend fun refreshToken(context: Context): Boolean = withContext(Dispatchers.IO) {
        val rt = refreshToken.ifEmpty {
            loadTokens(context)
            refreshToken
        }
        if (rt.isEmpty()) return@withContext false
        try {
            val client = OkHttpClient()
            val body = "grant_type=refresh_token&client_id=$CLIENT_ID&refresh_token=$rt"
                .toRequestBody("application/x-www-form-urlencoded".toMediaType())
            val request = Request.Builder().url(TOKEN_URL).post(body).build()
            val json = client.newCall(request).execute().use { resp ->
                if (!resp.isSuccessful) return@withContext false
                JSONObject(resp.body?.string() ?: return@withContext false)
            }
            accessToken = json.getString("access_token")
            refreshToken = json.optString("refresh_token", rt)
            accountID = decodeAccountID(accessToken)
            val expiresIn = json.optLong("expires_in", 0)
            expiresAt = System.currentTimeMillis() + expiresIn * 1000 - 60000
            saveTokens(context)
            true
        } catch (_: Exception) { false }
    }

    suspend fun getValidAccessToken(context: Context): String {
        if (accessToken.isEmpty()) loadTokens(context)
        if (shouldRefresh(context)) {
            refreshToken(context)
        }
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
                    val body = "token=$refreshToken&client_id=$CLIENT_ID"
                        .toRequestBody("application/x-www-form-urlencoded".toMediaType())
                    client.newCall(Request.Builder().url(REVOKE_URL).post(body).build()).execute().close()
                } catch (_: Exception) {}
            }
        }
        accessToken = ""
        refreshToken = ""
        accountID = ""
        expiresAt = 0L
        encryptedPrefs(context).edit().clear().apply()
    }

    fun isSignedIn(context: Context) = getStoredAccessToken(context).isNotEmpty()

    private fun saveTokens(context: Context) {
        encryptedPrefs(context).edit()
            .putString("access_token", accessToken)
            .putString("refresh_token", refreshToken)
            .putString("account_id", accountID)
            .putLong("expires_at", expiresAt)
            .apply()
    }

    private fun loadTokens(context: Context) {
        val prefs = encryptedPrefs(context)
        accessToken = prefs.getString("access_token", "") ?: ""
        refreshToken = prefs.getString("refresh_token", "") ?: ""
        accountID = prefs.getString("account_id", "") ?: ""
        expiresAt = prefs.getLong("expires_at", 0)
    }

    private fun generateRandomString(length: Int): String {
        val chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        return (1..length).map { chars[secureRandom.nextInt(chars.length)] }.joinToString("")
    }

    private fun sha256(input: ByteArray): ByteArray = java.security.MessageDigest.getInstance("SHA-256").digest(input)

    private fun base64Url(input: ByteArray): String {
        return Base64.encodeToString(input, Base64.NO_WRAP or Base64.URL_SAFE)
            .replace("+", "-").replace("/", "_").replace("=", "")
    }
}
