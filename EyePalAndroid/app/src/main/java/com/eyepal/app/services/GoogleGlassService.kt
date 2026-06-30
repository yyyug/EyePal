package com.eyepal.app.services

import android.app.Activity
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.AudioDeviceType
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.MediaRecorder
import android.util.Log
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import androidx.xr.projected.ExperimentalProjectedApi
import androidx.xr.projected.ProjectedContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.concurrent.Executors

class GoogleGlassService(private val context: Context) {
    companion object {
        private const val TAG = "GoogleGlassService"
    }

    private var audioManager: AudioManager? = null
    private var glassCameraProvider: ProcessCameraProvider? = null
    private var glassImageCapture: ImageCapture? = null
    private var projectedContext: Context? = null
    private val analysisExecutor = Executors.newSingleThreadExecutor()

    @OptIn(ExperimentalProjectedApi::class)
    fun connect(activity: Activity) {
        audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

        val projected = try {
            ProjectedContext.createProjectedDeviceContext(context)
        } catch (e: IllegalStateException) {
            Log.w(TAG, "XR projected context not available, falling back to Bluetooth HFP", e)
            null
        }

        if (projected != null) {
            projectedContext = projected
            GoogleGlassState.setConnected(true)
            GoogleGlassState.setXRMode(true)
            Log.i(TAG, "Connected via XR projected context")
        } else {
            connectBluetoothHFP()
            GoogleGlassState.setConnected(true)
            GoogleGlassState.setXRMode(false)
            Log.i(TAG, "Connected via Bluetooth HFP")
        }
    }

    private fun connectBluetoothHFP() {
        val am = audioManager ?: return
        val devices = am.getDevices(AudioManager.GET_DEVICES_INPUTS)
        val hfpDevice = devices.find { it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO }

        if (hfpDevice != null) {
            am.setCommunicationDevice(hfpDevice)
            Log.i(TAG, "Bluetooth HFP device set: ${hfpDevice.productName}")
        } else {
            Log.w(TAG, "No Bluetooth SCO device found")
        }
    }

    @OptIn(ExperimentalProjectedApi::class)
    fun disconnect() {
        val am = audioManager
        if (GoogleGlassState.isXRMode.value) {
            // Projected context is tied to device lifecycle, just clear our reference
            projectedContext = null
        } else {
            am?.let {
                it.clearCommunicationDevice()
            }
        }
        glassCameraProvider?.unbindAll()
        glassCameraProvider = null
        glassImageCapture = null
        GoogleGlassState.setConnected(false)
        GoogleGlassState.setUseGlassCamera(false)
        GoogleGlassState.setXRMode(false)
    }

    @OptIn(ExperimentalProjectedApi::class)
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

                    val preview = Preview.Builder().build().also { it.surfaceProvider = previewView.surfaceProvider }
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
                    Log.i(TAG, "Glasses camera started successfully")
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
            imageCapture.takePicture(analysisExecutor, object : ImageCapture.OnImageCapturedCallback() {
                override fun onCaptureSuccess(image: ImageProxy) {
                    resultBitmap = imageProxyToBitmap(image)
                    image.close()
                    latch.countDown()
                }
                override fun onError(exception: ImageCaptureException) {
                    Log.e(TAG, "Glasses photo capture failed", exception)
                    latch.countDown()
                }
            })
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
