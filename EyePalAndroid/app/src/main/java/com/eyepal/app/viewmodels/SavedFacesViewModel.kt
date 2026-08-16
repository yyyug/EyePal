package com.eyepal.app.viewmodels

import android.app.Application
import androidx.compose.runtime.mutableStateOf
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.eyepal.app.EyePalApplication
import com.eyepal.app.services.FaceRecognitionService
import kotlinx.coroutines.launch

class SavedFacesViewModel(application: Application) : AndroidViewModel(application) {
    data class RenameTarget(val id: String, val currentName: String)

    val profiles = mutableStateOf<List<FaceRecognitionService.SavedFaceProfile>>(emptyList())
    val errorMessage = mutableStateOf<String?>(null)

    private val container = (application as EyePalApplication).container
    private val faceService = container.faceRecognitionService

    init {
        loadProfiles()
    }

    fun loadProfiles() {
        viewModelScope.launch {
            try {
                faceService.load()
                profiles.value = faceService.getProfiles()
            } catch (e: Exception) {
                errorMessage.value = e.message
            }
        }
    }

    fun deleteFace(id: String) {
        viewModelScope.launch {
            faceService.deleteFace(id)
            profiles.value = faceService.getProfiles()
        }
    }

    fun renameFace(id: String, newName: String) {
        viewModelScope.launch {
            faceService.renameFace(id, newName)
            profiles.value = faceService.getProfiles()
        }
    }
}
