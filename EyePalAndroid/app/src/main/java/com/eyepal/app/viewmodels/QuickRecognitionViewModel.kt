package com.eyepal.app.viewmodels

import android.app.Application
import android.graphics.Bitmap
import androidx.compose.runtime.mutableStateOf
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.eyepal.app.services.AccessibilityAnnouncer
import com.eyepal.app.services.CameraService
import com.eyepal.app.services.MoondreamService
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class QuickRecognitionViewModel(application: Application) : AndroidViewModel(application) {
    val statusText = mutableStateOf("Point the camera at something to describe it.")
    val responseText = mutableStateOf("")
    val isProcessing = mutableStateOf(false)
    val isContinuousCapture = mutableStateOf(false)
    val capturedImage = mutableStateOf<Bitmap?>(null)
    val errorMessage = mutableStateOf<String?>(null)

    val camera = CameraService(application)
    private val moondream = MoondreamService()
    private val announcer = AccessibilityAnnouncer(application)
    private var continuousJob: Job? = null
    private var lastPrompt = "Describe what you see briefly"

    fun startCamera(previewView: android.view.View) {
        val lifecycleOwner = (previewView.context as? androidx.lifecycle.LifecycleOwner) ?: return
        camera.startCamera(lifecycleOwner, previewView as androidx.camera.view.PreviewView)
    }

    fun stopCamera() { camera.stopCamera() }

    fun takePhoto() { lastPrompt = "Describe what you see briefly"; capture() }

    fun takePresetPhoto(prompt: String) { lastPrompt = prompt; capture() }

    fun startContinuousMode() {
        if (isContinuousCapture.value) return
        isContinuousCapture.value = true
        statusText.value = "Continuous mode running."
        continuousJob = viewModelScope.launch {
            while (isContinuousCapture.value) {
                capture()
                delay(3000)
            }
        }
    }

    fun stopContinuous() {
        continuousJob?.cancel()
        continuousJob = null
        isContinuousCapture.value = false
        if (!isProcessing.value) statusText.value = "Quick Recognition ready."
    }

    private fun capture() {
        if (isProcessing.value) return
        isProcessing.value = true
        statusText.value = "Analyzing scene..."
        viewModelScope.launch {
            try {
                val bitmap = camera.capturePhoto() ?: throw Exception("Failed to capture")
                capturedImage.value = bitmap
                val prefs = getApplication<Application>().getSharedPreferences("settings", 0)
                val apiKey = prefs.getString("moondream_api_key", "") ?: ""
                if (apiKey.isEmpty()) { responseText.value = "Add Moondream API key in Settings."; isProcessing.value = false; return@launch }
                val result = moondream.describeImage(bitmap, apiKey, lastPrompt)
                responseText.value = result
                statusText.value = "Result ready."
                announcer.announce(result)
            } catch (e: Exception) { errorMessage.value = e.message; statusText.value = "Failed." }
            isProcessing.value = false
        }
    }

    fun clearError() { errorMessage.value = null }
}
