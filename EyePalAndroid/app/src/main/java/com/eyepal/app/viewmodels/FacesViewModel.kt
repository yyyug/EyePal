package com.eyepal.app.viewmodels

import android.app.Application
import android.graphics.Bitmap
import androidx.compose.runtime.mutableStateOf
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.eyepal.app.services.CameraService
import com.eyepal.app.services.FaceDetectionService
import kotlinx.coroutines.launch

class FacesViewModel(application: Application) : AndroidViewModel(application) {
    val statusText = mutableStateOf("Point the camera at a face.")
    val recognizedName = mutableStateOf<String?>(null)
    val isProcessing = mutableStateOf(false)
    val errorMessage = mutableStateOf<String?>(null)

    val camera = CameraService(application)
    private val faceDetection = FaceDetectionService(application)

    fun startCamera(previewView: android.view.View) {
        val lifecycleOwner = (previewView.context as? androidx.lifecycle.LifecycleOwner) ?: return
        camera.startCamera(lifecycleOwner, previewView as androidx.camera.view.PreviewView)
    }

    fun stopCamera() { camera.stopCamera() }

    fun detectFaces() {
        if (isProcessing.value) return
        isProcessing.value = true
        viewModelScope.launch {
            try {
                val bitmap = camera.capturePhoto() ?: throw Exception("Failed to capture")
                val faces = faceDetection.detectFaces(bitmap)
                if (faces.isNotEmpty()) {
                    statusText.value = "Detected ${faces.size} face(s)."
                } else {
                    statusText.value = "No faces detected."
                }
            } catch (e: Exception) {
                errorMessage.value = e.message
            }
            isProcessing.value = false
        }
    }

    override fun onCleared() {
        super.onCleared()
        faceDetection.close()
    }
}
