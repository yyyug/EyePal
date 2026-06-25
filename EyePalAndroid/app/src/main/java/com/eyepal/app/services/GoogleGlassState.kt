package com.eyepal.app.services

import android.graphics.Bitmap
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

object GoogleGlassState {
    private val _isConnected = MutableStateFlow(false)
    val isConnected: StateFlow<Boolean> = _isConnected

    private val _useGlassCamera = MutableStateFlow(false)
    val useGlassCamera: StateFlow<Boolean> = _useGlassCamera

    private val _cameraFrame = MutableStateFlow<Bitmap?>(null)
    val cameraFrame: StateFlow<Bitmap?> = _cameraFrame

    fun setConnected(value: Boolean) { _isConnected.value = value }
    fun setUseGlassCamera(value: Boolean) { _useGlassCamera.value = value }
    fun updateCameraFrame(bitmap: Bitmap) { _cameraFrame.value = bitmap }
}
