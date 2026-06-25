package com.eyepal.app.services

import android.app.Activity
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.AudioManager
import android.util.Log
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
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
    private val analysisExecutor = Executors.newSingleThreadExecutor()

    fun connect(activity: Activity) {
        audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioManager?.isBluetoothScoOn = true
        audioManager?.startBluetoothSco()
        GoogleGlassState.setConnected(true)
    }

    fun disconnect() {
        audioManager?.stopBluetoothSco()
        audioManager?.isBluetoothScoOn = false
        glassCameraProvider?.unbindAll()
        glassCameraProvider = null
        glassImageCapture = null
        GoogleGlassState.setConnected(false)
        GoogleGlassState.setUseGlassCamera(false)
    }

    fun startGlassCamera(lifecycleOwner: LifecycleOwner, previewView: PreviewView) {
        if (!GoogleGlassState.useGlassCamera.value || !GoogleGlassState.isConnected.value) return

        try {
            val cameraProviderFuture = ProcessCameraProvider.getInstance(context)
            cameraProviderFuture.addListener({
                try {
                    glassCameraProvider = cameraProviderFuture.get()
                    val preview = Preview.Builder().build().also { it.surfaceProvider = previewView.surfaceProvider }
                    glassImageCapture = ImageCapture.Builder().setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY).build()
                    glassCameraProvider?.unbindAll()
                    glassCameraProvider?.bindToLifecycle(lifecycleOwner, CameraSelector.DEFAULT_BACK_CAMERA, preview, glassImageCapture)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to bind glasses camera", e)
                }
            }, ContextCompat.getMainExecutor(context))
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start glasses camera", e)
        }
    }

    fun stopGlassCamera() {
        glassCameraProvider?.unbindAll()
        glassCameraProvider = null
    }

    suspend fun capturePhotoFromGlasses(): Bitmap? = withContext(Dispatchers.IO) {
        val imageCapture = glassImageCapture ?: return@withContext null
        try {
            var resultBitmap: Bitmap? = null
            val latch = java.util.concurrent.CountDownLatch(1)
            imageCapture.takePicture(analysisExecutor, object : ImageCapture.OnImageCapturedCallback() {
                override fun onCaptureSuccess(image: ImageProxy) { resultBitmap = imageProxyToBitmap(image); image.close(); latch.countDown() }
                override fun onError(exception: ImageCaptureException) { latch.countDown() }
            })
            latch.await()
            resultBitmap
        } catch (_: Exception) { null }
    }

    private fun imageProxyToBitmap(imageProxy: ImageProxy): Bitmap? {
        val buffer = imageProxy.planes[0].buffer
        val bytes = ByteArray(buffer.remaining())
        buffer.get(bytes)
        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return null
        val rotation = imageProxy.imageInfo.rotationDegrees
        return if (rotation != 0) { val m = Matrix().apply { postRotate(rotation.toFloat()) }; Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, m, true) } else bitmap
    }
}
