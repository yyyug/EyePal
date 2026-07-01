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
import com.eyepal.app.services.GoogleGlassState
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

class GoogleGlassViewModel(application: android.app.Application) : AndroidViewModel(application) {
    val isConnected = mutableStateOf(false)
    val statusText = mutableStateOf("Scanning for glasses...")
    val useGlassCamera = mutableStateOf(false)
    val cameraFrame = mutableStateOf<Bitmap?>(null)
    val isXRMode = mutableStateOf(false)

    private val glassService = GoogleGlassService(application)
    private val announcer = AccessibilityAnnouncer(application)

    init {
        viewModelScope.launch { GoogleGlassState.isConnected.collectLatest { isConnected.value = it; updateStatus() } }
        viewModelScope.launch { GoogleGlassState.useGlassCamera.collectLatest { useGlassCamera.value = it } }
        viewModelScope.launch { GoogleGlassState.cameraFrame.collectLatest { cameraFrame.value = it } }
        viewModelScope.launch { GoogleGlassState.isXRMode.collectLatest { isXRMode.value = it; updateStatus() } }
    }

    private fun updateStatus() {
        val connected = GoogleGlassState.isConnected.value
        val xr = GoogleGlassState.isXRMode.value
        statusText.value = when {
            !connected -> "No glasses connected."
            xr -> "Connected via XR Projected"
            else -> "Connected via Bluetooth HFP"
        }
    }

    /**
     * Auto-connect: called on app startup to attempt glasses connection.
     * For audio glasses, this sets up Bluetooth HFP or XR projected context.
     */
    fun autoConnect(activity: Activity) {
        if (!GoogleGlassState.isConnected.value) {
            connect(activity)
        }
    }

    fun connect(activity: Activity) {
        glassService.connect(activity)
        val mode = if (GoogleGlassState.isXRMode.value) "XR Projected" else "Bluetooth HFP"
        announcer.announce("Connected to glasses via $mode")
    }

    fun disconnect() {
        glassService.stopGlassCamera()
        glassService.disconnect()
        announcer.announce("Disconnected from glasses.")
    }

    fun toggleGlassCamera(lifecycleOwner: LifecycleOwner, previewView: PreviewView) {
        val newValue = !useGlassCamera.value
        GoogleGlassState.setUseGlassCamera(newValue)
        if (newValue) {
            glassService.startGlassCamera(lifecycleOwner, previewView)
        } else {
            glassService.stopGlassCamera()
        }
    }

    override fun onCleared() {
        super.onCleared()
        announcer.shutdown()
    }
}
