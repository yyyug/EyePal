package com.eyepal.app.viewmodels

import android.app.Application
import android.graphics.Bitmap
import androidx.compose.runtime.mutableStateOf
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.eyepal.app.services.AccessibilityAnnouncer
import com.eyepal.app.services.CameraService
import com.eyepal.app.services.OpenAIService
import kotlinx.coroutines.launch

class DetailsRecognitionViewModel(application: Application) : AndroidViewModel(application) {
    val statusText = mutableStateOf("Take a photo to describe the scene.")
    val descriptionText = mutableStateOf("")
    val followUpQuestion = mutableStateOf("")
    val isProcessing = mutableStateOf(false)
    val isSignedIn = mutableStateOf(false)
    val errorMessage = mutableStateOf<String?>(null)

    val camera = CameraService(application)
    private val openAI = OpenAIService()
    private val announcer = AccessibilityAnnouncer(application)
    private var lastImage: Bitmap? = null

    fun startCamera(previewView: android.view.View) {
        val lifecycleOwner = (previewView.context as? androidx.lifecycle.LifecycleOwner) ?: return
        camera.startCamera(lifecycleOwner, previewView as androidx.camera.view.PreviewView)
    }

    fun stopCamera() { camera.stopCamera() }
    fun signIn() { isSignedIn.value = true }

    fun capturePhoto() {
        if (isProcessing.value) return
        isProcessing.value = true
        statusText.value = "Describing the photo..."
        viewModelScope.launch {
            try {
                val bitmap = camera.capturePhoto() ?: throw Exception("Failed to capture photo")
                lastImage = bitmap
                val prefs = getApplication<Application>().getSharedPreferences("settings", 0)
                val apiKey = prefs.getString("openai_api_key", "") ?: ""
                if (apiKey.isEmpty()) { descriptionText.value = "Add OpenAI API key in Settings."; isProcessing.value = false; return@launch }
                val prompt = "For a blind user, if visible text is present, read it exactly. Then describe people, objects, layout, and orientation cues. Be concise and specific."
                val result = openAI.describeImage(bitmap, apiKey, prompt)
                descriptionText.value = result
                statusText.value = "Photo details are ready."
                announcer.announce(result)
            } catch (e: Exception) { errorMessage.value = e.message; statusText.value = "Could not describe the photo." }
            isProcessing.value = false
        }
    }

    fun submitFollowUp() {
        val question = followUpQuestion.value.trim()
        if (question.isEmpty() || isProcessing.value) return
        isProcessing.value = true
        followUpQuestion.value = ""
        viewModelScope.launch {
            try {
                val image = lastImage ?: throw Exception("Take a photo first")
                val prefs = getApplication<Application>().getSharedPreferences("settings", 0)
                val apiKey = prefs.getString("openai_api_key", "") ?: ""
                val result = openAI.describeImage(image, apiKey, question)
                descriptionText.value = result
                statusText.value = "Follow-up answer is ready."
                announcer.announce(result)
            } catch (e: Exception) { errorMessage.value = e.message }
            isProcessing.value = false
        }
    }
}
