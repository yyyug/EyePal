package com.eyepal.app.services

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.graphics.Bitmap
import android.media.AudioManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext
import java.io.IOException
import java.io.InputStream
import java.util.UUID

class GoogleGlassService(private val context: Context) {
    private val _isConnected = MutableStateFlow(false)
    val isConnected: StateFlow<Boolean> = _isConnected

    private val _statusText = MutableStateFlow("No glasses connected.")
    val statusText: StateFlow<String> = _statusText

    private val _cameraFrame = MutableStateFlow<Bitmap?>(null)
    val cameraFrame: StateFlow<Bitmap?> = _cameraFrame

    private var socket: BluetoothSocket? = null
    private var inputStream: InputStream? = null
    private var audioManager: AudioManager? = null

    fun connect(device: BluetoothDevice) {
        try {
            val uuid = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
            socket = device.createRfcommSocketToServiceRecord(uuid)
            socket?.connect()
            inputStream = socket?.inputStream
            _isConnected.value = true
            _statusText.value = "Connected to ${device.name}"

            audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            audioManager?.isBluetoothScoOn = true
            audioManager?.startBluetoothSco()
        } catch (e: IOException) {
            _statusText.value = "Connection failed: ${e.message}"
            _isConnected.value = false
        }
    }

    fun disconnect() {
        try {
            audioManager?.stopBluetoothSco()
            audioManager?.isBluetoothScoOn = false
            inputStream?.close()
            socket?.close()
        } catch (_: Exception) {}
        socket = null
        inputStream = null
        _isConnected.value = false
        _statusText.value = "Disconnected."
        _cameraFrame.value = null
    }

    suspend fun readCameraFrame() = withContext(Dispatchers.IO) {
        while (_isConnected.value) {
            try {
                val bytes = inputStream?.readBytes() ?: break
                if (bytes.isNotEmpty()) {
                    val bitmap = android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                    if (bitmap != null) _cameraFrame.value = bitmap
                }
            } catch (_: Exception) { break }
        }
    }

    fun getPairedDevices(): List<BluetoothDevice> {
        val btManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager ?: return emptyList()
        return try { btManager.adapter?.bondedDevices?.toList() ?: emptyList() } catch (_: SecurityException) { emptyList() }
    }
}
