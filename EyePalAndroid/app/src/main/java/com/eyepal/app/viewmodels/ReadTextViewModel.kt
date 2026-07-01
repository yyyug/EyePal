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
import com.eyepal.app.services.OCRService
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

class ReadTextViewModel(application: Application) : AndroidViewModel(application) {
    val statusText = mutableStateOf("Point the camera at text to recognize it.")
    val recognizedText = mutableStateOf("")
    val isProcessing = mutableStateOf(false)
    val isContinuous = mutableStateOf(false)
    val errorMessage = mutableStateOf<String?>(null)

    val camera = CameraService(application)
    private val ocr = OCRService(application)
    private val glassService = GoogleGlassService(application)
    private val announcer = AccessibilityAnnouncer(application)
    private var continuousJob: Job? = null
    private var lastAnnouncedText = ""

    fun startCamera(previewView: android.view.View) {
        if (GoogleGlassState.useGlassCamera.value) return
        val lifecycleOwner = (previewView.context as? androidx.lifecycle.LifecycleOwner) ?: return
        camera.startCamera(lifecycleOwner, previewView as androidx.camera.view.PreviewView) { bitmap ->
            if (isContinuous.value && !isProcessing.value) recognizeFrame(bitmap)
        }
    }

    fun stopCamera() { camera.stopCamera() }

    fun captureAndRecognize() {
        if (isProcessing.value) return
        isProcessing.value = true
        statusText.value = "Capturing text..."
        viewModelScope.launch {
            try {
                val bitmap = if (GoogleGlassState.useGlassCamera.value) glassService.capturePhotoFromGlasses() else camera.capturePhoto()
                    ?: throw Exception("Failed to capture")
                val text = ocr.recognizeText(bitmap!!)
                recognizedText.value = text
                statusText.value = "Text recognized."
                announcer.announce(text)
            } catch (e: Exception) { errorMessage.value = e.message; statusText.value = "Failed." }
            isProcessing.value = false
        }
    }

    fun startContinuous() { isContinuous.value = true; statusText.value = "Continuous recognition active." }

    fun stopContinuous() { isContinuous.value = false; if (!isProcessing.value) statusText.value = "Ready." }

    private fun recognizeFrame(bitmap: Bitmap) {
        if (isProcessing.value) return
        isProcessing.value = true
        viewModelScope.launch {
            try {
                val text = ocr.recognizeText(bitmap)
                if (text.isNotBlank() && text != lastAnnouncedText) { recognizedText.value = text; lastAnnouncedText = text; announcer.announce(text, minimumInterval = 3000) }
            } catch (_: Exception) {}
            isProcessing.value = false
        }
    }

    override fun onCleared() { super.onCleared(); ocr.close() }
}
