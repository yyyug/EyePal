package com.eyepal.app.viewmodels

import android.graphics.Bitmap
import androidx.compose.runtime.mutableStateOf
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class QuickRecognitionViewModel : ViewModel() {
    val statusText = mutableStateOf("Point the camera at something to describe it.")
    val responseText = mutableStateOf("")
    val isProcessing = mutableStateOf(false)
    val capturedImage = mutableStateOf<Bitmap?>(null)
    val errorMessage = mutableStateOf<String?>(null)

    fun takePhoto() {
        if (isProcessing.value) return
        isProcessing.value = true
        statusText.value = "Analyzing scene..."
        viewModelScope.launch {
            delay(2000)
            responseText.value = "This is a placeholder response. Connect Moondream API to enable real recognition."
            statusText.value = "Quick Recognition result is ready."
            isProcessing.value = false
        }
    }

    fun clearError() { errorMessage.value = null }
}

class DetailsRecognitionViewModel : ViewModel() {
    val statusText = mutableStateOf("Take a photo to describe the scene.")
    val descriptionText = mutableStateOf("")
    val followUpQuestion = mutableStateOf("")
    val isProcessing = mutableStateOf(false)
    val isSignedIn = mutableStateOf(false)
    val errorMessage = mutableStateOf<String?>(null)

    fun signIn() {
        isSignedIn.value = true
        statusText.value = "Signed in. Ready to describe scenes."
    }

    fun capturePhoto() {
        if (isProcessing.value) return
        isProcessing.value = true
        statusText.value = "Describing the photo..."
        viewModelScope.launch {
            delay(2000)
            descriptionText.value = "This is a placeholder description. Connect ChatGPT API to enable real recognition."
            statusText.value = "Photo details are ready."
            isProcessing.value = false
        }
    }

    fun submitFollowUp() {
        val question = followUpQuestion.value.trim()
        if (question.isEmpty() || isProcessing.value) return
        isProcessing.value = true
        followUpQuestion.value = ""
        viewModelScope.launch {
            delay(1500)
            descriptionText.value = "Follow-up response placeholder."
            isProcessing.value = false
        }
    }
}
