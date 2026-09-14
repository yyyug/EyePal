package com.eyepal.app.viewmodels

import android.app.Application
import androidx.compose.runtime.mutableStateOf
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.eyepal.app.EyePalApplication
import com.eyepal.app.services.FaceAudioPlayer
import com.eyepal.app.services.FaceRecognitionService
import kotlinx.coroutines.launch

class SavedFacesViewModel(application: Application) : AndroidViewModel(application) {
    data class RenameTarget(val id: String, val currentName: String)

    val profiles = mutableStateOf<List<FaceRecognitionService.SavedFaceProfile>>(emptyList())
    val errorMessage = mutableStateOf<String?>(null)
    val playingProfileId = mutableStateOf<String?>(null)

    private val container = (application as EyePalApplication).container
    private val faceService = container.faceRecognitionService
    private val player = FaceAudioPlayer(application)

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

    fun togglePlay(profile: FaceRecognitionService.SavedFaceProfile) {
        val filename = profile.soundFilename ?: return
        val file = faceService.recordingFile(filename)
        if (!file.exists()) return
        if (playingProfileId.value == profile.id) {
            stopPlayback()
            return
        }
        playingProfileId.value = profile.id
        player.onFinish = { playingProfileId.value = null }
        player.play(file)
    }

    fun stopPlayback() {
        player.stop()
        player.onFinish = null
        playingProfileId.value = null
    }

    fun deleteFace(id: String) {
        viewModelScope.launch {
            faceService.deleteFace(id)
            if (playingProfileId.value == id) stopPlayback()
            profiles.value = faceService.getProfiles()
        }
    }

    fun renameFace(id: String, newName: String) {
        viewModelScope.launch {
            faceService.renameFace(id, newName)
            profiles.value = faceService.getProfiles()
        }
    }

    fun updateTextNote(id: String, text: String?) {
        viewModelScope.launch {
            faceService.updateTextNote(id, text)
            profiles.value = faceService.getProfiles()
        }
    }

    override fun onCleared() {
        super.onCleared()
        player.release()
    }
}