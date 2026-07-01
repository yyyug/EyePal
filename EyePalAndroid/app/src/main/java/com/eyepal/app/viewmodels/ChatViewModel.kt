package com.eyepal.app.viewmodels

import android.app.Application
import androidx.compose.runtime.mutableStateOf
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.eyepal.app.services.ChatService
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

class ChatViewModel(application: Application) : AndroidViewModel(application) {
    val statusText = mutableStateOf("Ready to start voice chat.")
    val isConnected = mutableStateOf(false)
    val transcript = mutableStateOf("")
    val selectedMode = mutableStateOf("interpreter")
    val languageA = mutableStateOf("en")
    val languageB = mutableStateOf("ja")

    private val chatService = ChatService(application)

    init {
        viewModelScope.launch {
            chatService.statusText.collectLatest { statusText.value = it }
        }
        viewModelScope.launch {
            chatService.isConnected.collectLatest { isConnected.value = it }
        }
        viewModelScope.launch {
            chatService.transcript.collectLatest { transcript.value = it }
        }
    }

    fun startChat(apiKey: String) {
        chatService.startVoiceChat(
            apiKey = apiKey,
            mode = selectedMode.value,
            langA = languageA.value,
            langB = languageB.value
        )
    }

    fun stopChat() { chatService.stop() }

    override fun onCleared() {
        super.onCleared()
        chatService.stop()
    }
}
