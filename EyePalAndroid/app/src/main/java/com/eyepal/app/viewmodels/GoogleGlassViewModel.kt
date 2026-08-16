package com.eyepal.app.viewmodels

import android.app.Activity
import android.bluetooth.BluetoothDevice
import android.graphics.Bitmap
import androidx.compose.runtime.mutableStateOf
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.camera.view.PreviewView
import androidx.lifecycle.LifecycleOwner
import com.eyepal.app.EyePalApplication
import com.eyepal.app.R
import com.eyepal.app.services.DiscoveredGlass
import com.eyepal.app.services.GlassConnectionState
import com.eyepal.app.services.GoogleGlassState
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

class GoogleGlassViewModel(application: android.app.Application) : AndroidViewModel(application) {
    private fun str(resId: Int): String = getApplication<android.app.Application>().getString(resId)
    private fun str(resId: Int, vararg args: Any?): String = getApplication<android.app.Application>().getString(resId, *args)

    val isConnected = mutableStateOf(false)
    val statusText = mutableStateOf(str(R.string.glass_no_glasses))
    val useGlassCamera = mutableStateOf(false)
    val cameraFrame = mutableStateOf<Bitmap?>(null)
    val isXRMode = mutableStateOf(false)
    val bluetoothNeedsEnable = mutableStateOf(false)
    val bluetoothPairingNeeded = mutableStateOf(false)
    val bluetoothPermissionDenied = mutableStateOf(false)
    val connectionState = mutableStateOf(GlassConnectionState.DISCONNECTED)
    val discoveredDevices = mutableStateOf<List<DiscoveredGlass>>(emptyList())
    val pairingDevice = mutableStateOf<String?>(null)
    val connectedDeviceName = mutableStateOf<String?>(null)
    val statusDetail = mutableStateOf<String?>(null)

    private val container = (application as EyePalApplication).container
    private val glassService = container.glassService
    private val announcer = container.announcer

    init {
        viewModelScope.launch { GoogleGlassState.isConnected.collectLatest { isConnected.value = it; updateStatus() } }
        viewModelScope.launch { GoogleGlassState.useGlassCamera.collectLatest { useGlassCamera.value = it } }
        viewModelScope.launch { GoogleGlassState.cameraFrame.collectLatest { cameraFrame.value = it } }
        viewModelScope.launch { GoogleGlassState.isXRMode.collectLatest { isXRMode.value = it; updateStatus() } }
        viewModelScope.launch { glassService.bluetoothNeedsEnable.collectLatest { bluetoothNeedsEnable.value = it; updateStatus() } }
        viewModelScope.launch { glassService.bluetoothPairingNeeded.collectLatest { bluetoothPairingNeeded.value = it; updateStatus() } }
        viewModelScope.launch { glassService.bluetoothPermissionDenied.collectLatest { bluetoothPermissionDenied.value = it; updateStatus() } }
        viewModelScope.launch { glassService.connectionState.collectLatest { handleConnectionState(it) } }
        viewModelScope.launch { glassService.discoveredDevices.collectLatest { discoveredDevices.value = it } }
        viewModelScope.launch { glassService.pairingDevice.collectLatest { pairingDevice.value = it; updateStatus() } }
        viewModelScope.launch { glassService.connectedDeviceName.collectLatest { connectedDeviceName.value = it } }
        viewModelScope.launch { glassService.statusMessage.collectLatest { statusDetail.value = it; updateStatus() } }
    }

    private fun handleConnectionState(state: GlassConnectionState) {
        val previous = connectionState.value
        connectionState.value = state
        val nowConnected = state == GlassConnectionState.CONNECTED_XR || state == GlassConnectionState.CONNECTED_BT
        val wasConnected = previous == GlassConnectionState.CONNECTED_XR || previous == GlassConnectionState.CONNECTED_BT
        if (nowConnected && !wasConnected) {
            val mode = if (state == GlassConnectionState.CONNECTED_XR) "Android XR" else "Bluetooth"
            announcer.announce(str(R.string.glass_connected_announce, mode))
        } else if (wasConnected && !nowConnected) {
            announcer.announce(str(R.string.glass_disconnected_announce))
        }
        updateStatus()
    }

    private fun updateStatus() {
        val state = connectionState.value
        statusText.value = when {
            bluetoothPermissionDenied.value -> str(R.string.glass_permission_needed)
            bluetoothNeedsEnable.value -> str(R.string.glass_status_bluetooth_off)
            state == GlassConnectionState.SCANNING -> str(R.string.glass_scanning)
            state == GlassConnectionState.PAIRING -> str(R.string.glass_status_pairing)
            state == GlassConnectionState.CONNECTING -> str(R.string.glass_connecting)
            state == GlassConnectionState.CONNECTED_XR -> str(R.string.glass_connected_xr)
            state == GlassConnectionState.CONNECTED_BT -> str(R.string.glass_connected_bt)
            state == GlassConnectionState.FAILED -> statusDetail.value ?: str(R.string.glass_status_could_not_connect)
            !isConnected.value -> str(R.string.glass_no_glasses)
            isXRMode.value -> str(R.string.glass_connected_xr)
            else -> str(R.string.glass_connected_bt)
        }
    }

    fun autoConnect(activity: Activity) {
        if (!GoogleGlassState.isConnected.value) {
            connect(activity)
        }
    }

    fun connect(activity: Activity) {
        glassService.connect(activity)
    }

    fun scan() {
        glassService.startDiscovery()
    }

    fun stopScan() {
        glassService.stopDiscovery()
    }

    fun pairWith(device: BluetoothDevice) {
        glassService.pairWith(device)
    }

    fun requestBluetoothEnable(activity: Activity) {
        glassService.requestBluetoothEnable(activity)
    }

    fun openBluetoothSettings(activity: Activity) {
        glassService.openBluetoothSettings(activity)
        glassService.resetPairingState()
    }

    fun disconnect() {
        glassService.stopGlassCamera()
        glassService.disconnect()
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
