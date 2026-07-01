package com.eyepal.app.viewmodels

import android.app.Application
import android.graphics.Bitmap
import androidx.compose.runtime.mutableStateOf
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.eyepal.app.services.AccessibilityAnnouncer
import com.eyepal.app.services.CameraService
import com.eyepal.app.services.GoogleGlassService
import com.eyepal.app.services.GoogleGlassState
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
    private val glassService = GoogleGlassService(application)
    private val announcer = AccessibilityAnnouncer(application)
    private var lastImage: Bitmap? = null
    private var lastPrompt = "For a blind user, read visible text exactly, then describe people, objects, layout, and orientation cues. Be concise."

    fun startCamera(previewView: android.view.View) {
        if (GoogleGlassState.useGlassCamera.value) return
        val lifecycleOwner = (previewView.context as? androidx.lifecycle.LifecycleOwner) ?: return
        camera.startCamera(lifecycleOwner, previewView as androidx.camera.view.PreviewView)
    }

    fun stopCamera() { camera.stopCamera() }
    fun signIn() { isSignedIn.value = true }

    fun capturePhoto() { lastPrompt = "For a blind user, read visible text exactly, then describe people, objects, layout, and orientation cues. Be concise."; doCapture() }

    fun capturePresetPhoto(prompt: String) { lastPrompt = prompt; doCapture() }

    private fun doCapture() {
        if (isProcessing.value) return
        isProcessing.value = true
        statusText.value = "Describing the photo..."
        viewModelScope.launch {
            try {
                val bitmap = if (GoogleGlassState.useGlassCamera.value) glassService.capturePhotoFromGlasses() else camera.capturePhoto()
                    ?: throw Exception("Failed to capture")
                lastImage = bitmap
                val prefs = getApplication<Application>().getSharedPreferences("settings", 0)
                val apiKey = prefs.getString("openai_api_key", "") ?: ""
                if (apiKey.isEmpty()) { descriptionText.value = "Add OpenAI API key in Settings."; isProcessing.value = false; return@launch }
                val result = openAI.describeImage(bitmap!!, apiKey, lastPrompt)
                descriptionText.value = result
                statusText.value = "Details ready."
                announcer.announce(result)
            } catch (e: Exception) { errorMessage.value = e.message; statusText.value = "Failed." }
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
                statusText.value = "Follow-up ready."
                announcer.announce(result)
            } catch (e: Exception) { errorMessage.value = e.message }
            isProcessing.value = false
        }
    }
}
