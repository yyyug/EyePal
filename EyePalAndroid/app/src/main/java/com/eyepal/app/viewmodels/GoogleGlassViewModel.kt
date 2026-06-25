package com.eyepal.app.viewmodels

import android.app.Activity
import android.graphics.Bitmap
import androidx.compose.runtime.mutableStateOf
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.camera.view.PreviewView
import androidx.lifecycle.LifecycleOwner
import com.eyepal.app.services.AccessibilityAnnouncer
import com.eyepal.app.services.GoogleGlassService
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

class GoogleGlassViewModel(application: android.app.Application) : AndroidViewModel(application) {
    val isConnected = mutableStateOf(false)
    val statusText = mutableStateOf("No glasses connected.")
    val useGlassCamera = mutableStateOf(false)
    val cameraFrame = mutableStateOf<Bitmap?>(null)

    private val glassService = GoogleGlassService(application)
    private val announcer = AccessibilityAnnouncer(application)

    init {
        viewModelScope.launch { glassService.isConnected.collectLatest { isConnected.value = it } }
        viewModelScope.launch { glassService.statusText.collectLatest { statusText.value = it } }
        viewModelScope.launch { glassService.useGlassCamera.collectLatest { useGlassCamera.value = it } }
        viewModelScope.launch { glassService.cameraFrame.collectLatest { cameraFrame.value = it } }
    }

    fun connect(activity: Activity) {
        glassService.connect(activity)
        announcer.announce("Connected to audio glasses")
    }

    fun disconnect() {
        glassService.stopGlassCamera()
        glassService.disconnect()
        announcer.announce("Disconnected from glasses.")
    }

    fun toggleGlassCamera(lifecycleOwner: LifecycleOwner, previewView: PreviewView) {
        val newValue = !useGlassCamera.value
        glassService.setUseGlassCamera(newValue)
        if (newValue) {
            glassService.startGlassCamera(lifecycleOwner, previewView)
        } else {
            glassService.stopGlassCamera()
        }
    }
}
