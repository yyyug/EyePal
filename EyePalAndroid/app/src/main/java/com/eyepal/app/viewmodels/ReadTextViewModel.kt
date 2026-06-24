package com.eyepal.app.viewmodels

import android.app.Application
import android.graphics.Bitmap
import androidx.compose.runtime.mutableStateOf
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.eyepal.app.services.CameraService
import com.eyepal.app.services.OCRService
import kotlinx.coroutines.launch

class ReadTextViewModel(application: Application) : AndroidViewModel(application) {
    val statusText = mutableStateOf("Point the camera at text to recognize it.")
    val recognizedText = mutableStateOf("")
    val isProcessing = mutableStateOf(false)
    val errorMessage = mutableStateOf<String?>(null)

    val camera = CameraService(application)
    private val ocr = OCRService(application)

    fun startCamera(previewView: android.view.View) {
        val lifecycleOwner = (previewView.context as? androidx.lifecycle.LifecycleOwner) ?: return
        camera.startCamera(lifecycleOwner, previewView as androidx.camera.view.PreviewView)
    }

    fun stopCamera() { camera.stopCamera() }

    fun captureAndRecognize() {
        if (isProcessing.value) return
        isProcessing.value = true
        statusText.value = "Capturing text..."
        viewModelScope.launch {
            try {
                val bitmap = camera.capturePhoto() ?: throw Exception("Failed to capture")
                val text = ocr.recognizeText(bitmap)
                recognizedText.value = text
                statusText.value = "Text recognized."
            } catch (e: Exception) {
                errorMessage.value = e.message
                statusText.value = "Text recognition failed."
            }
            isProcessing.value = false
        }
    }

    override fun onCleared() {
        super.onCleared()
        ocr.close()
    }
}
