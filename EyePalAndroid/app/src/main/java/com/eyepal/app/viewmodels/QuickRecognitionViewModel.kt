package com.eyepal.app.viewmodels

import android.app.Application
import android.graphics.Bitmap
import androidx.compose.runtime.mutableStateOf
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.eyepal.app.services.CameraService
import com.eyepal.app.services.MoondreamService
import kotlinx.coroutines.launch

class QuickRecognitionViewModel(application: Application) : AndroidViewModel(application) {
    val statusText = mutableStateOf("Point the camera at something to describe it.")
    val responseText = mutableStateOf("")
    val isProcessing = mutableStateOf(false)
    val capturedImage = mutableStateOf<Bitmap?>(null)
    val errorMessage = mutableStateOf<String?>(null)

    val camera = CameraService(application)
    private val moondream = MoondreamService()

    fun startCamera(previewView: android.view.View) {
        val lifecycleOwner = (previewView.context as? androidx.lifecycle.LifecycleOwner) ?: return
        camera.startCamera(lifecycleOwner, previewView as androidx.camera.view.PreviewView)
    }

    fun stopCamera() { camera.stopCamera() }

    fun takePhoto() {
        if (isProcessing.value) return
        isProcessing.value = true
        statusText.value = "Analyzing scene..."
        viewModelScope.launch {
            try {
                val bitmap = camera.capturePhoto() ?: throw Exception("Failed to capture photo")
                capturedImage.value = bitmap
                val apiKey = getApplication<Application>()
                    .getSharedPreferences("settings", 0)
                    .getString("moondream_api_key", "") ?: ""
                if (apiKey.isEmpty()) {
                    responseText.value = "Add Moondream API key in Settings."
                    isProcessing.value = false
                    return@launch
                }
                val result = moondream.describeImage(bitmap, apiKey)
                responseText.value = result
                statusText.value = "Quick Recognition result is ready."
            } catch (e: Exception) {
                errorMessage.value = e.message
                statusText.value = "Quick Recognition failed."
            }
            isProcessing.value = false
        }
    }

    fun clearError() { errorMessage.value = null }
}
