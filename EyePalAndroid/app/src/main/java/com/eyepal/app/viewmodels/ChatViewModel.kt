package com.eyepal.app.viewmodels

import android.app.Application
import android.media.AudioManager
import android.util.Log
import androidx.compose.runtime.mutableStateOf
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.eyepal.app.EyePalApplication
import com.eyepal.app.R
import com.eyepal.app.services.OAuthService
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

class ChatViewModel(application: Application) : AndroidViewModel(application) {
    private val container = (application as EyePalApplication).container
    private val settings = container.settingsRepository

    companion object {
        private const val TAG = "ChatViewModel"
        private const val DEFAULT_INSTRUCTIONS = "You are a helpful voice assistant. Be concise and natural."
    }

    private fun str(resId: Int): String = getApplication<Application>().getString(resId)
    private fun str(resId: Int, vararg args: Any?): String = getApplication<Application>().getString(resId, *args)

    val statusText = mutableStateOf(str(R.string.chat_status_ready))
    val transcript = mutableStateOf("")
    val isConnected = mutableStateOf(false)
    val isConnecting = mutableStateOf(false)
    val errorMessage = mutableStateOf<String?>(null)
    val selectedMode = mutableStateOf("chat")
    val languageA = mutableStateOf("en")
    val languageB = mutableStateOf("ja")

    private val rtcService = container.realtimeWebRTCService
    private var initialized = false

    init {
        viewModelScope.launch {
            languageA.value = settings.chatInterpreterLangA.first()
            languageB.value = settings.chatInterpreterLangB.first()
        }
    }

    fun start() {
        val context = getApplication<Application>()
        val accessToken = OAuthService.getStoredAccessToken(context)
        if (accessToken.isEmpty()) {
            errorMessage.value = str(R.string.chat_sign_in_first)
            return
        }

        isConnecting.value = true
        statusText.value = str(R.string.chat_connecting)
        errorMessage.value = null
        transcript.value = ""

        rtcService.onTranscript = { text ->
            val current = transcript.value
            transcript.value = if (current.isEmpty()) text else "$current\n$text"
        }
        rtcService.onInputTranscript = { text ->
            val current = transcript.value
            transcript.value = if (current.isEmpty()) text else "$current\n$text"
        }
        rtcService.onStatusChange = { status ->
            statusText.value = status
            when (status) {
                "Connected" -> {
                    isConnected.value = true
                    isConnecting.value = false
                }
                "Disconnected" -> {
                    isConnected.value = false
                    isConnecting.value = false
                }
                else -> { }
            }
        }
        rtcService.onError = { error ->
            Log.e(TAG, "RTC error: $error")
            errorMessage.value = error
            isConnecting.value = false
        }

        if (!initialized) {
            rtcService.initialize()
            initialized = true
        }

        val am = context.getSystemService(Application.AUDIO_SERVICE) as AudioManager
        am.mode = AudioManager.MODE_IN_COMMUNICATION

        viewModelScope.launch(kotlinx.coroutines.Dispatchers.IO) {
            try {
                if (selectedMode.value == "interpreter") {
                    rtcService.languageA = languageA.value
                    rtcService.languageB = languageB.value
                    rtcService.connectInterpreter(accessToken, languageA.value, languageB.value)
                } else {
                    rtcService.connectChat(accessToken, DEFAULT_INSTRUCTIONS)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Connection error", e)
                errorMessage.value = str(R.string.chat_connection_error, e.message)
                isConnecting.value = false
            }
        }
    }

    fun persistLanguages() {
        viewModelScope.launch {
            settings.setChatInterpreterLangA(languageA.value)
            settings.setChatInterpreterLangB(languageB.value)
        }
    }

    fun stop() {
        persistLanguages()
        rtcService.disconnect()
        isConnected.value = false
        isConnecting.value = false
        statusText.value = str(R.string.chat_status_ready)

        val context = getApplication<Application>()
        val am = context.getSystemService(Application.AUDIO_SERVICE) as AudioManager
        am.mode = AudioManager.MODE_NORMAL
    }

    override fun onCleared() {
        persistLanguages()
        super.onCleared()
        rtcService.disconnect()
        val context = getApplication<Application>()
        val am = context.getSystemService(Application.AUDIO_SERVICE) as AudioManager
        am.mode = AudioManager.MODE_NORMAL
    }
}