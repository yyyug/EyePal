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
import androidx.xr.projected.ProjectedContext
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import java.util.concurrent.Executors

@Suppress("DEPRECATION")
class GoogleGlassService(private val context: Context) {
    companion object {
        private const val TAG = "GoogleGlassService"
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

    fun connect(activity: Activity) {
        audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

        // Try to create projected context for glasses hardware access
        // This will fail with IllegalStateException if no glasses are connected
        val projected = try {
            ProjectedContext.createProjectedDeviceContext(context)
        } catch (e: IllegalStateException) {
            Log.w(TAG, "No XR projected device available: ${e.message}")
            null
        } catch (e: SecurityException) {
            Log.w(TAG, "XR permission denied: ${e.message}")
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

        // Fallback: no XR glasses — use Bluetooth HFP
        connectBluetoothHFP()
        GoogleGlassState.setConnected(true)
        GoogleGlassState.setXRMode(false)
        Log.i(TAG, "No XR device — Bluetooth HFP fallback")
    }

    /**
     * Poll projected device availability. If glasses disconnect,
     * clean up camera and audio resources.
     */
    private fun startConnectionMonitoring() {
        connectionMonitor?.cancel()
        connectionMonitor = scope.launch {
            while (isActive) {
                delay(5000)
                val stillAvailable = try {
                    ProjectedContext.isProjectedDeviceConnected(context, Dispatchers.IO).first()
                } catch (_: Exception) {
                    false
                }
                if (!stillAvailable && _isXRDeviceAvailable.value) {
                    Log.i(TAG, "XR device disconnected")
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
