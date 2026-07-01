package com.eyepal.app.services

import android.app.Activity
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.util.Log
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import java.util.concurrent.Executors

@Suppress("DEPRECATION")
class GoogleGlassService(private val context: Context) {
    companion object {
        private const val TAG = "GoogleGlassService"

        /**
         * Check if a projected device (audio/display glasses) is currently connected.
         * Uses the XR SDK's flow-based API to poll connection status.
         */
        suspend fun isProjectedDeviceAvailable(context: Context): Boolean {
            return try {
                val connected = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                    androidx.xr.projected.ProjectedContext.isProjectedDeviceConnected(context, kotlinx.coroutines.Dispatchers.IO).first()
                }
                Log.i(TAG, "Projected device connected: $connected")
                connected
            } catch (e: Exception) {
                Log.w(TAG, "Failed to check projected device: ${e.message}")
                false
            }
        }
    }

    private var audioManager: AudioManager? = null
    private var glassCameraProvider: ProcessCameraProvider? = null
    private var glassImageCapture: ImageCapture? = null
    private var projectedContext: Context? = null
    private val analysisExecutor = Executors.newSingleThreadExecutor()
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private var connectionMonitor: Job? = null

    private val _isXRDeviceAvailable = MutableStateFlow(false)
    val isXRDeviceAvailable: StateFlow<Boolean> = _isXRDeviceAvailable

    /**
     * Connect to audio glasses.
     *
     * Per XR SDK docs, the correct flow is:
     * 1. Check if projected device is connected via isProjectedDeviceConnected()
     * 2. Request glasses-specific permissions via ProjectedPermissionsResultContract
     * 3. Create projected context via createProjectedDeviceContext()
     * 4. Use projected context for camera and audio access
     *
     * Fallback: Bluetooth HFP via AudioManager.setCommunicationDevice()
     */
    fun connect(activity: Activity) {
        audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

        // Step 1: Check if XR projected device (glasses) is connected
        // We check this synchronously first — the real check is async via isProjectedDeviceConnected()
        // For the initial connection, we attempt to create the projected context directly.
        // If it fails, the device is not connected and we fall back.
        //
        // NOTE: On a real glasses device, this will succeed if the glasses are paired.
        // On the Audio_Glasses AVD, this may fail because the emulator doesn't
        // fully implement ProjectedContext — this is expected.
        //
        // The correct permissions flow per docs:
        // - From glasses activity: use ProjectedPermissionsResultContract
        // - From phone activity: use Activity.requestPermissions(permissions, requestCode, deviceId)
        //   where deviceId comes from ProjectedContext.createProjectedDeviceContext(context)
        //
        // We attempt to create the projected context here. If it fails with
        // IllegalStateException, we fall back to Bluetooth HFP.
        val projected = try {
            // This will throw IllegalStateException if no XR device is connected
            // or SecurityException if permissions are missing
            val ctx = androidx.xr.projected.ProjectedContext.createProjectedDeviceContext(context)

            // If we got here, the XR device is connected.
            // Now we should request glasses-specific permissions using the deviceId
            // from the projected context, per the docs:
            // Activity#requestPermissions(permissions, requestCode, deviceId)
            Log.i(TAG, "XR projected context created successfully")
            ctx
        } catch (e: IllegalStateException) {
            Log.w(TAG, "XR device not available: ${e.message}")
            null
        } catch (e: SecurityException) {
            Log.w(TAG, "XR permission denied: ${e.message}. Need glasses-specific permissions.")
            null
        } catch (e: Exception) {
            Log.w(TAG, "Unexpected error creating projected context: ${e.message}")
            null
        }

        if (projected != null) {
            projectedContext = projected
            _isXRDeviceAvailable.value = true
            GoogleGlassState.setConnected(true)
            GoogleGlassState.setXRMode(true)
            Log.i(TAG, "Connected via XR projected context")
            startConnectionMonitoring()
            return
        }

        // Step 4: Fallback — no XR glasses connected, use Bluetooth HFP
        connectBluetoothHFP()
        GoogleGlassState.setConnected(true)
        GoogleGlassState.setXRMode(false)
        Log.i(TAG, "No XR device — Bluetooth HFP fallback")
    }

    /**
     * Poll projected device connection every 5 seconds.
     * If glasses disconnect, automatically clean up resources.
     */
    private fun startConnectionMonitoring() {
        connectionMonitor?.cancel()
        connectionMonitor = scope.launch {
            while (isActive) {
                delay(5000)
                val stillAvailable = isProjectedDeviceAvailable(context)
                if (!stillAvailable && _isXRDeviceAvailable.value) {
                    Log.i(TAG, "XR device disconnected — cleaning up")
                    cleanupXRResources()
                }
            }
        }
    }

    private fun cleanupXRResources() {
        _isXRDeviceAvailable.value = false
        glassCameraProvider?.unbindAll()
        glassCameraProvider = null
        glassImageCapture = null
        projectedContext = null
        GoogleGlassState.setConnected(false)
        GoogleGlassState.setUseGlassCamera(false)
        GoogleGlassState.setXRMode(false)
    }

    private fun connectBluetoothHFP() {
        val am = audioManager ?: return
        val devices = am.getDevices(AudioManager.GET_DEVICES_INPUTS)
        val hfpDevice = devices.find { it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO }

        if (hfpDevice != null) {
            @Suppress("DEPRECATION")
            am.setCommunicationDevice(hfpDevice)
            Log.i(TAG, "Bluetooth HFP device set: ${hfpDevice.productName}")
        } else {
            Log.w(TAG, "No Bluetooth SCO device found")
        }
    }

    fun disconnect() {
        connectionMonitor?.cancel()
        connectionMonitor = null

        if (GoogleGlassState.isXRMode.value) {
            projectedContext = null
        } else {
            @Suppress("DEPRECATION")
            audioManager?.clearCommunicationDevice()
        }

        glassCameraProvider?.unbindAll()
        glassCameraProvider = null
        glassImageCapture = null
        _isXRDeviceAvailable.value = false
        GoogleGlassState.setConnected(false)
        GoogleGlassState.setUseGlassCamera(false)
        GoogleGlassState.setXRMode(false)
    }

    /**
     * Start camera on glasses.
     *
     * Per XR SDK docs ("Capture an image with the glasses' camera"):
     * - Get ProcessCameraProvider using the projected context
     * - DEFAULT_BACK_CAMERA maps to glasses' outward camera
     * - Bind ImageCapture use case
     */
    fun startGlassCamera(lifecycleOwner: LifecycleOwner, previewView: PreviewView) {
        if (!GoogleGlassState.useGlassCamera.value || !GoogleGlassState.isConnected.value) return

        // Use projected context for glasses, or phone context for Bluetooth fallback
        val ctx = if (GoogleGlassState.isXRMode.value) {
            projectedContext ?: run {
                Log.e(TAG, "Projected context is null")
                return
            }
        } else {
            context
        }

        try {
            // Per XR SDK docs: ProcessCameraProvider.getInstance(projectedContext)
            // DEFAULT_BACK_CAMERA maps to the glasses' camera when using projected context
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
