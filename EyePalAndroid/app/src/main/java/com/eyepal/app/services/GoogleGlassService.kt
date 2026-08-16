package com.eyepal.app.services

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import androidx.xr.projected.ProjectedContext
import com.eyepal.app.GlassesProjectedActivity
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import java.util.concurrent.Executors

enum class GlassConnectionState {
    DISCONNECTED,
    SCANNING,
    PAIRING,
    CONNECTING,
    CONNECTED_XR,
    CONNECTED_BT,
    FAILED
}

data class DiscoveredGlass(
    val name: String,
    val address: String,
    val isPaired: Boolean,
    val device: BluetoothDevice
)

/**
 * Google Glass connectivity.
 *
 * Primary path (per Android XR / Jetpack XR SDK docs):
 *   1. Observe [ProjectedContext.isProjectedDeviceConnected] — the OS handles discovery,
 *      pairing and connection of the glasses device.
 *   2. When connected, create the projected device context via
 *      [ProjectedContext.createProjectedDeviceContext].
 *   3. Launch the projected activity onto the glasses display with
 *      [ProjectedContext.createProjectedActivityOptions].
 *
 * Fallback: standard Bluetooth discovery + pairing (HSP/HFP/A2DP), following the
 * Bluetooth docs. Only reports CONNECTED when a real active device is present.
 */
@Suppress("DEPRECATION")
class GoogleGlassService(private val context: Context) {
    companion object {
        private const val TAG = "GoogleGlassService"

        private val GLASS_NAME_HINTS = listOf("glass", "glasses", "xreal", "rayneo", "meta", "ray-ban", "frames", "eyewear", "audio", "even", "xr")

        /**
         * Check if a projected device (audio/display glasses) is currently connected.
         * Per Android XR docs, this is the source of truth for glasses connection.
         */
        @kotlinx.coroutines.ExperimentalCoroutinesApi
        @SuppressLint("NewApi")
        suspend fun isProjectedDeviceAvailable(context: Context): Boolean {
            if (Build.VERSION.SDK_INT < 34) return false
            return try {
                withContext(Dispatchers.IO) {
                    if (Build.VERSION.SDK_INT >= 36) {
                        ProjectedContext.isProjectedDeviceConnected(context, Dispatchers.IO).first()
                    } else {
                        // Older API: the create call throws IllegalStateException when no device is connected.
                        ProjectedContext.createProjectedDeviceContext(context)
                        true
                    }
                }
            } catch (e: Exception) {
                Log.d(TAG, "No projected device connected: ${e.message}")
                false
            }
        }
    }

    private val audioManager: AudioManager? = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager?
    private val bluetoothAdapter: BluetoothAdapter? =
        (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
            ?: BluetoothAdapter.getDefaultAdapter()
    private var glassCameraProvider: ProcessCameraProvider? = null
    private var glassImageCapture: ImageCapture? = null
    private var projectedContext: Context? = null
    private val analysisExecutor = Executors.newSingleThreadExecutor()
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private var xrMonitorJob: Job? = null
    private var deviceReceiver: BroadcastReceiver? = null
    private var connectedDeviceAddress: String? = null

    private val _connectionState = MutableStateFlow(GlassConnectionState.DISCONNECTED)
    val connectionState: StateFlow<GlassConnectionState> = _connectionState

    private val _statusMessage = MutableStateFlow<String?>(null)
    val statusMessage: StateFlow<String?> = _statusMessage

    private val _isXRDeviceAvailable = MutableStateFlow(false)
    val isXRDeviceAvailable: StateFlow<Boolean> = _isXRDeviceAvailable

    private val _bluetoothNeedsEnable = MutableStateFlow(false)
    val bluetoothNeedsEnable: StateFlow<Boolean> = _bluetoothNeedsEnable

    private val _bluetoothPairingNeeded = MutableStateFlow(false)
    val bluetoothPairingNeeded: StateFlow<Boolean> = _bluetoothPairingNeeded

    private val _bluetoothPermissionDenied = MutableStateFlow(false)
    val bluetoothPermissionDenied: StateFlow<Boolean> = _bluetoothPermissionDenied

    private val _discoveredDevices = MutableStateFlow<List<DiscoveredGlass>>(emptyList())
    val discoveredDevices: StateFlow<List<DiscoveredGlass>> = _discoveredDevices

    private val _pairingDevice = MutableStateFlow<String?>(null)
    val pairingDevice: StateFlow<String?> = _pairingDevice

    private val _connectedDeviceName = MutableStateFlow<String?>(null)
    val connectedDeviceName: StateFlow<String?> = _connectedDeviceName

    private fun hasBtPermission(): Boolean =
        context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED

    fun isBluetoothEnabled(): Boolean {
        val adapter = bluetoothAdapter ?: return false
        return try {
            adapter.isEnabled
        } catch (e: SecurityException) {
            false
        }
    }

    @SuppressLint("MissingPermission")
    fun requestBluetoothEnable(activity: Activity) {
        val adapter = bluetoothAdapter
        if (adapter != null && !adapter.isEnabled) {
            activity.startActivity(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE))
        }
    }

    fun openBluetoothSettings(activity: Activity) {
        activity.startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
    }

    fun resetPairingState() {
        _bluetoothNeedsEnable.value = false
        _bluetoothPairingNeeded.value = false
    }

    /**
     * Connect to glasses. Tries the Android XR projected flow first (per docs),
     * then falls back to an active Bluetooth HFP device or prompts to scan.
     */
    @OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
    fun connect(activity: Activity) {
        resetPairingState()
        scope.launch {
            if (isProjectedDeviceAvailable(context)) {
                connectXR(activity)
            } else {
                connectBluetooth()
            }
        }
    }

    @SuppressLint("NewApi")
    private fun connectXR(activity: Activity) {
        val ctx = try {
            ProjectedContext.createProjectedDeviceContext(context)
        } catch (e: Exception) {
            Log.w(TAG, "XR projected context could not be created: ${e.message}")
            connectBluetooth()
            return
        }
        projectedContext = ctx
        _isXRDeviceAvailable.value = true
        _connectedDeviceName.value = "Android XR Glasses"
        _connectionState.value = GlassConnectionState.CONNECTED_XR
        GoogleGlassState.setConnected(true)
        GoogleGlassState.setXRMode(true)
        Log.i(TAG, "Connected via XR projected context")
        launchGlassesProjectedActivity(activity)
        startXRMonitoring()
    }

    @SuppressLint("NewApi")
    private fun launchGlassesProjectedActivity(activity: Activity) {
        if (Build.VERSION.SDK_INT < 35) return
        try {
            val options = ProjectedContext.createProjectedActivityOptions(context)
            val intent = Intent(context, GlassesProjectedActivity::class.java)
            activity.startActivity(intent, options.toBundle())
            Log.i(TAG, "Launched GlassesProjectedActivity on the glasses display")
        } catch (e: Exception) {
            Log.w(TAG, "Could not launch projected activity: ${e.message}")
        }
    }

    @SuppressLint("NewApi")
    @OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
    private fun startXRMonitoring() {
        xrMonitorJob?.cancel()
        xrMonitorJob = scope.launch {
            try {
                if (Build.VERSION.SDK_INT >= 36) {
                    ProjectedContext.isProjectedDeviceConnected(context, Dispatchers.IO).collect { connected ->
                        if (!connected && _connectionState.value == GlassConnectionState.CONNECTED_XR) {
                            Log.i(TAG, "XR device disconnected")
                            handleDisconnect()
                        }
                    }
                } else {
                    while (isActive) {
                        delay(5000)
                        if (!isProjectedDeviceAvailable(context)) {
                            handleDisconnect()
                            break
                        }
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "XR monitoring stopped: ${e.message}")
            }
        }
    }

    private fun connectBluetooth() {
        if (!isBluetoothEnabled()) {
            _bluetoothNeedsEnable.value = true
            _connectionState.value = GlassConnectionState.DISCONNECTED
            return
        }
        if (!hasBtPermission()) {
            _bluetoothPermissionDenied.value = true
            _connectionState.value = GlassConnectionState.DISCONNECTED
            return
        }
        val am = audioManager
        val hfpDevice = am?.getDevices(AudioManager.GET_DEVICES_INPUTS)?.find { it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO }
        if (hfpDevice != null) {
            routeToHfpDevice(am, hfpDevice)
            connectedDeviceAddress = null
            _connectedDeviceName.value = hfpDevice.productName?.toString() ?: "Bluetooth glasses"
            _connectionState.value = GlassConnectionState.CONNECTED_BT
            GoogleGlassState.setConnected(true)
            GoogleGlassState.setXRMode(false)
            registerDeviceReceiver()
            Log.i(TAG, "Connected via active Bluetooth HFP device")
        } else {
            _bluetoothPairingNeeded.value = true
            _connectionState.value = GlassConnectionState.DISCONNECTED
            _statusMessage.value = "No connected glasses found. Scan for glasses and pair."
            Log.i(TAG, "No active Bluetooth HFP device — user should scan and pair")
        }
    }

    @SuppressLint("NewApi")
    private fun routeToHfpDevice(am: AudioManager, device: AudioDeviceInfo) {
        try {
            if (Build.VERSION.SDK_INT >= 31) {
                am.setCommunicationDevice(device)
            } else {
                am.startBluetoothSco()
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to route audio to HFP device: ${e.message}")
        }
    }

    /** Start Bluetooth discovery for nearby glasses (requires BLUETOOTH_CONNECT). */
    @SuppressLint("MissingPermission")
    fun startDiscovery() {
        val adapter = bluetoothAdapter
        if (adapter == null) {
            _statusMessage.value = "Bluetooth is unavailable on this device."
            return
        }
        if (!adapter.isEnabled) {
            _bluetoothNeedsEnable.value = true
            return
        }
        if (!hasBtPermission()) {
            _bluetoothPermissionDenied.value = true
            return
        }
        registerDeviceReceiver()
        _discoveredDevices.value = loadBondedDevices()
        _statusMessage.value = null
        _connectionState.value = GlassConnectionState.SCANNING
        try {
            if (adapter.isDiscovering) adapter.cancelDiscovery()
            val started = adapter.startDiscovery()
            Log.i(TAG, "Bluetooth discovery started: $started")
        } catch (e: SecurityException) {
            _bluetoothPermissionDenied.value = true
        }
    }

    @SuppressLint("MissingPermission")
    fun stopDiscovery() {
        val adapter = bluetoothAdapter
        try {
            if (adapter?.isDiscovering == true) adapter.cancelDiscovery()
        } catch (e: SecurityException) {
            // ignore
        }
        if (_connectionState.value == GlassConnectionState.SCANNING) {
            _connectionState.value = GlassConnectionState.DISCONNECTED
        }
    }

    /** Pair with a discovered glasses device, then connect audio via HFP. */
    @SuppressLint("MissingPermission")
    fun pairWith(device: BluetoothDevice) {
        stopDiscovery()
        registerDeviceReceiver()
        _pairingDevice.value = device.address
        _statusMessage.value = null
        _connectionState.value = GlassConnectionState.PAIRING
        if (device.bondState == BluetoothDevice.BOND_BONDED) {
            connectToDevice(device)
            return
        }
        try {
            val created = device.createBond()
            if (!created) {
                _pairingDevice.value = null
                _connectionState.value = GlassConnectionState.FAILED
                _statusMessage.value = "Pairing is already in progress on this device."
            }
        } catch (e: SecurityException) {
            _pairingDevice.value = null
            _bluetoothPermissionDenied.value = true
        }
    }

    @SuppressLint("NewApi", "MissingPermission")
    private fun connectToDevice(device: BluetoothDevice) {
        _connectionState.value = GlassConnectionState.CONNECTING
        connectedDeviceAddress = device.address
        _connectedDeviceName.value = device.name
        val am = audioManager
        val hfpDevice = am?.getDevices(AudioManager.GET_DEVICES_INPUTS)?.find { it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO }
        if (hfpDevice != null) {
            routeToHfpDevice(am, hfpDevice)
            markBluetoothConnected()
        } else {
            // SCO may take a moment to come up after bonding; ACL_CONNECTED finalizes it.
            Log.i(TAG, "Bonded with ${device.name}, waiting for audio route")
        }
    }

    private fun markBluetoothConnected() {
        _pairingDevice.value = null
        _bluetoothPairingNeeded.value = false
        _connectionState.value = GlassConnectionState.CONNECTED_BT
        _isXRDeviceAvailable.value = false
        GoogleGlassState.setConnected(true)
        GoogleGlassState.setXRMode(false)
        Log.i(TAG, "Bluetooth glasses connected")
    }

    @SuppressLint("MissingPermission")
    private fun loadBondedDevices(): List<DiscoveredGlass> {
        return try {
            bluetoothAdapter?.bondedDevices?.map { device ->
                DiscoveredGlass(
                    name = device.name ?: "Unknown device",
                    address = device.address,
                    isPaired = true,
                    device = device
                )
            }?.toList() ?: emptyList()
        } catch (e: SecurityException) {
            emptyList()
        }
    }

    @Suppress("DEPRECATION")
    private fun deviceFromIntent(intent: Intent): BluetoothDevice? =
        intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)

    @SuppressLint("MissingPermission")
    private fun registerDeviceReceiver() {
        unregisterDeviceReceiver()
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                when (intent.action) {
                    BluetoothDevice.ACTION_FOUND -> {
                        val device = deviceFromIntent(intent) ?: return
                        val name = device.name ?: return
                        if (GLASS_NAME_HINTS.any { name.lowercase().contains(it) }) {
                            val current = _discoveredDevices.value.toMutableList()
                            if (current.none { it.address == device.address }) {
                                current.add(DiscoveredGlass(name, device.address, device.bondState == BluetoothDevice.BOND_BONDED, device))
                                _discoveredDevices.value = current
                                Log.i(TAG, "Found glass device: $name")
                            }
                        }
                    }
                    BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> {
                        if (_connectionState.value == GlassConnectionState.SCANNING) {
                            _statusMessage.value = if (_discoveredDevices.value.isEmpty()) {
                                "No glasses found. Make sure your glasses are in pairing mode."
                            } else {
                                null
                            }
                            _connectionState.value = GlassConnectionState.DISCONNECTED
                            Log.i(TAG, "Bluetooth discovery finished")
                        }
                    }
                    BluetoothDevice.ACTION_BOND_STATE_CHANGED -> {
                        val device = deviceFromIntent(intent) ?: return
                        val state = intent.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, BluetoothDevice.ERROR)
                        when (state) {
                            BluetoothDevice.BOND_BONDED -> {
                                Log.i(TAG, "Bonded: ${device.name}")
                                connectToDevice(device)
                            }
                            BluetoothDevice.BOND_NONE -> {
                                if (_pairingDevice.value == device.address) {
                                    _pairingDevice.value = null
                                    _connectionState.value = GlassConnectionState.FAILED
                                    _statusMessage.value = "Pairing failed. Put your glasses in pairing mode and try again."
                                }
                            }
                        }
                    }
                    BluetoothDevice.ACTION_ACL_CONNECTED -> {
                        val device = deviceFromIntent(intent) ?: return
                        val current = _connectionState.value
                        if (current == GlassConnectionState.PAIRING || current == GlassConnectionState.CONNECTING) {
                            Log.i(TAG, "ACL connected: ${device.name}")
                            markBluetoothConnected()
                        }
                    }
                    BluetoothDevice.ACTION_ACL_DISCONNECTED -> {
                        val device = deviceFromIntent(intent) ?: return
                        val isOurs = connectedDeviceAddress == null || connectedDeviceAddress == device.address
                        if (isOurs && _connectionState.value == GlassConnectionState.CONNECTED_BT) {
                            val am = audioManager
                            val stillActive = am?.getDevices(AudioManager.GET_DEVICES_INPUTS)
                                ?.any { it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO } == true
                            if (!stillActive) {
                                Log.i(TAG, "Bluetooth glasses disconnected: ${device.name}")
                                handleDisconnect()
                            }
                        }
                    }
                    AudioManager.ACTION_SCO_AUDIO_STATE_UPDATED -> {
                        val state = intent.getIntExtra(AudioManager.EXTRA_SCO_AUDIO_STATE, AudioManager.SCO_AUDIO_STATE_DISCONNECTED)
                        if (state == AudioManager.SCO_AUDIO_STATE_DISCONNECTED &&
                            _connectionState.value == GlassConnectionState.CONNECTED_BT) {
                            val am = audioManager
                            val stillActive = am?.getDevices(AudioManager.GET_DEVICES_INPUTS)
                                ?.any { it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO } == true
                            if (!stillActive) {
                                Log.i(TAG, "SCO audio disconnected")
                                handleDisconnect()
                            }
                        }
                    }
                }
            }
        }
        val filter = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_FOUND)
            addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
            addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
            addAction(BluetoothDevice.ACTION_ACL_CONNECTED)
            addAction(BluetoothDevice.ACTION_ACL_DISCONNECTED)
            addAction(AudioManager.ACTION_SCO_AUDIO_STATE_UPDATED)
        }
        ContextCompat.registerReceiver(context, receiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED)
        deviceReceiver = receiver
    }

    private fun unregisterDeviceReceiver() {
        val receiver = deviceReceiver ?: return
        try {
            context.unregisterReceiver(receiver)
        } catch (e: IllegalArgumentException) {
            // Already unregistered
        }
        deviceReceiver = null
    }

    private fun handleDisconnect() {
        xrMonitorJob?.cancel()
        xrMonitorJob = null
        connectedDeviceAddress = null
        _connectedDeviceName.value = null
        _isXRDeviceAvailable.value = false
        _connectionState.value = GlassConnectionState.DISCONNECTED
        GoogleGlassState.setConnected(false)
        GoogleGlassState.setUseGlassCamera(false)
        GoogleGlassState.setXRMode(false)
    }

    fun disconnect() {
        xrMonitorJob?.cancel()
        xrMonitorJob = null
        stopDiscovery()
        unregisterDeviceReceiver()
        if (GoogleGlassState.isXRMode.value) {
            projectedContext = null
        } else {
            try {
                if (Build.VERSION.SDK_INT >= 31) audioManager?.clearCommunicationDevice()
            } catch (e: Exception) {
                Log.w(TAG, "Failed to clear communication device: ${e.message}")
            }
        }
        glassCameraProvider?.unbindAll()
        glassCameraProvider = null
        glassImageCapture = null
        handleDisconnect()
    }

    /**
     * Start camera on glasses.
     *
     * Per XR SDK docs ("Capture an image with the glasses' camera"):
     * - Get ProcessCameraProvider using the projected context
     * - DEFAULT_BACK_CAMERA maps to the glasses' outward camera
     * - Bind ImageCapture use case
     */
    fun startGlassCamera(lifecycleOwner: LifecycleOwner, previewView: PreviewView) {
        if (!GoogleGlassState.useGlassCamera.value || !GoogleGlassState.isConnected.value) return

        val ctx = if (GoogleGlassState.isXRMode.value) {
            projectedContext ?: run {
                Log.e(TAG, "Projected context is null")
                return
            }
        } else {
            context
        }

        try {
            val cameraProviderFuture = ProcessCameraProvider.getInstance(ctx)
            cameraProviderFuture.addListener({
                try {
                    glassCameraProvider = cameraProviderFuture.get()
                    if (!glassCameraProvider!!.hasCamera(CameraSelector.DEFAULT_BACK_CAMERA)) {
                        Log.w(TAG, "Glasses camera not available")
                        return@addListener
                    }
                    val preview = Preview.Builder().build().also {
                        it.surfaceProvider = previewView.surfaceProvider
                    }
                    glassImageCapture = ImageCapture.Builder()
                        .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
                        .build()
                    glassCameraProvider?.unbindAll()
                    glassCameraProvider?.bindToLifecycle(
                        lifecycleOwner,
                        CameraSelector.DEFAULT_BACK_CAMERA,
                        preview,
                        glassImageCapture
                    )
                    Log.i(TAG, "Glasses camera started")
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to bind glasses camera", e)
                }
            }, ContextCompat.getMainExecutor(ctx))
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start glasses camera", e)
        }
    }

    fun stopGlassCamera() {
        glassCameraProvider?.unbindAll()
        glassCameraProvider = null
        glassImageCapture = null
    }

    suspend fun capturePhotoFromGlasses(): Bitmap? = withContext(Dispatchers.IO) {
        val imageCapture = glassImageCapture ?: return@withContext null
        try {
            var resultBitmap: Bitmap? = null
            val latch = java.util.concurrent.CountDownLatch(1)
            imageCapture.takePicture(
                analysisExecutor,
                object : ImageCapture.OnImageCapturedCallback() {
                    override fun onCaptureSuccess(image: ImageProxy) {
                        resultBitmap = imageProxyToBitmap(image)
                        image.close()
                        latch.countDown()
                    }
                    override fun onError(exception: ImageCaptureException) {
                        Log.e(TAG, "Photo capture failed", exception)
                        latch.countDown()
                    }
                }
            )
            latch.await()
            resultBitmap
        } catch (e: Exception) {
            Log.e(TAG, "Exception capturing from glasses", e)
            null
        }
    }

    private fun imageProxyToBitmap(imageProxy: ImageProxy): Bitmap? {
        val buffer = imageProxy.planes[0].buffer
        val bytes = ByteArray(buffer.remaining())
        buffer.get(bytes)
        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return null
        val rotation = imageProxy.imageInfo.rotationDegrees
        return if (rotation != 0) {
            val m = Matrix().apply { postRotate(rotation.toFloat()) }
            Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, m, true)
        } else {
            bitmap
        }
    }
}
