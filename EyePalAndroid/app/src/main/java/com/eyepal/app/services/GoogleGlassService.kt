package com.eyepal.app.services

import android.app.Presentation
import android.content.Context
import android.graphics.Bitmap
import android.hardware.display.DisplayManager
import android.media.AudioManager
import android.os.Bundle
import android.view.Display
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

class GoogleGlassService(private val context: Context) {
    private val _isConnected = MutableStateOf(false)
    val isConnected: StateFlow<Boolean> = _isConnected

    private val _statusText = MutableStateOf("No glasses connected.")
    val statusText: StateFlow<String> = _statusText

    private val _cameraFrame = MutableStateOf<Bitmap?>(null)
    val cameraFrame: StateFlow<Bitmap?> = _cameraFrame

    private val _useGlassCamera = MutableStateOf(false)
    val useGlassCamera: StateFlow<Boolean> = _useGlassCamera

    private var audioManager: AudioManager? = null
    private var presentation: Presentation? = null

    fun connect() {
        audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioManager?.isBluetoothScoOn = true
        audioManager?.startBluetoothSco()
        _isConnected.value = true
        _statusText.value = "Connected to audio glasses"

        val displayManager = context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        val displays = displayManager.getDisplays(Display.TYPE_WIFI)
        if (displays.isNotEmpty()) {
            _statusText.value = "Connected. Display available on glasses."
        }
    }

    fun disconnect() {
        audioManager?.stopBluetoothSco()
        audioManager?.isBluetoothScoOn = false
        presentation?.dismiss()
        presentation = null
        _isConnected.value = false
        _useGlassCamera.value = false
        _statusText.value = "Disconnected."
        _cameraFrame.value = null
    }

    fun setUseGlassCamera(enabled: Boolean) {
        _useGlassCamera.value = enabled
    }

    fun updateCameraFrame(bitmap: Bitmap) {
        _cameraFrame.value = bitmap
    }

    fun getAudioManager(): AudioManager? = audioManager
}
