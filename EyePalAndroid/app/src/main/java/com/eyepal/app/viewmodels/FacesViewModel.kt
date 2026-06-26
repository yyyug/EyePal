package com.eyepal.app.viewmodels

import android.app.Application
import android.graphics.Bitmap
import androidx.compose.runtime.mutableStateOf
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.eyepal.app.services.CameraService
import com.eyepal.app.services.FaceRecognitionService
import kotlinx.coroutines.launch

class FacesViewModel(application: Application) : AndroidViewModel(application) {
    val statusText = mutableStateOf("Point the camera at a face.")
    val recognizedName = mutableStateOf<String?>(null)
    val isProcessing = mutableStateOf(false)
    val errorMessage = mutableStateOf<String?>(null)
    val profiles = mutableStateOf<List<FaceRecognitionService.SavedFaceProfile>>(emptyList())
    val pendingSaveName = mutableStateOf<String?>(null)
    val pendingEmbedding = mutableStateOf<FloatArray?>(null)

    val camera = CameraService(application)
    private val faceService = FaceRecognitionService(application)
    private val prefs = application.getSharedPreferences("settings", 0)

    init {
        faceService.recognitionThreshold = prefs.getFloat("face_match_threshold", 0.95f)
        faceService.minimumTopMatchMargin = prefs.getFloat("face_match_margin", 0.05f)
        faceService.knownMatchFrameThreshold = prefs.getInt("face_match_frame_threshold", 3)
        viewModelScope.launch {
            faceService.load()
            profiles.value = faceService.getProfiles()
        }
    }

    fun startCamera(previewView: android.view.View) {
        val lifecycleOwner = (previewView.context as? androidx.lifecycle.LifecycleOwner) ?: return
        camera.startCamera(lifecycleOwner, previewView as androidx.camera.view.PreviewView) { bitmap ->
            processFrame(bitmap)
        }
    }

    fun stopCamera() { camera.stopCamera() }

    private fun processFrame(bitmap: Bitmap) {
        if (isProcessing.value) return
        isProcessing.value = true
        viewModelScope.launch {
            try {
                val result = faceService.processFrame(bitmap)
                if (result.match != null) {
                    recognizedName.value = result.match.name
                    statusText.value = "Recognized ${result.match.name}."
                } else if (result.embedding != null) {
                    recognizedName.value = null
                    pendingEmbedding.value = result.embedding
                    pendingSaveName.value = ""
                    statusText.value = "Unknown face detected. Enter name to save."
                }
            } catch (_: Exception) {}
            isProcessing.value = false
        }
    }

    fun saveFace(name: String) {
        val embedding = pendingEmbedding.value ?: return
        viewModelScope.launch {
            faceService.saveFace(name, embedding)
            profiles.value = faceService.getProfiles()
            pendingSaveName.value = null
            pendingEmbedding.value = null
            statusText.value = "$name was saved."
        }
    }

    fun dismissSave() {
        pendingSaveName.value = null
        pendingEmbedding.value = null
    }

    fun deleteFace(id: String) {
        viewModelScope.launch {
            faceService.deleteFace(id)
            profiles.value = faceService.getProfiles()
        }
    }

    override fun onCleared() { super.onCleared(); faceService.close() }
}
