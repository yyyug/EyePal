package com.eyepal.app.viewmodels

import android.app.Application
import android.bluetooth.BluetoothDevice
import android.graphics.Bitmap
import androidx.compose.runtime.mutableStateOf
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.eyepal.app.services.AccessibilityAnnouncer
import com.eyepal.app.services.GoogleGlassService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class GoogleGlassViewModel(application: Application) : AndroidViewModel(application) {
    val isConnected = mutableStateOf(false)
    val statusText = mutableStateOf("No glasses connected.")
    val pairedDevices = mutableStateOf<List<BluetoothDevice>>(emptyList())
    val selectedDevice = mutableStateOf<BluetoothDevice?>(null)
    val cameraFrame = mutableStateOf<Bitmap?>(null)
    val useGlassCamera = mutableStateOf(false)

    private val glassService = GoogleGlassService(application)
    private val announcer = AccessibilityAnnouncer(application)

    init {
        pairedDevices.value = glassService.getPairedDevices()
        viewModelScope.launch {
            glassService.isConnected.collect { isConnected.value = it }
        }
        viewModelScope.launch {
            glassService.statusText.collect { statusText.value = it }
        }
        viewModelScope.launch {
            glassService.cameraFrame.collect { cameraFrame.value = it }
        }
    }

    fun connect(device: BluetoothDevice) {
        selectedDevice.value = device
        glassService.connect(device)
        announcer.announce("Connected to ${device.name}")
    }

    fun disconnect() {
        glassService.disconnect()
        selectedDevice.value = null
        useGlassCamera.value = false
        announcer.announce("Disconnected from glasses.")
    }

    fun startReadingCamera() {
        viewModelScope.launch { glassService.readCameraFrame() }
    }
}
