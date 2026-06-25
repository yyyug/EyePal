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
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

class GoogleGlassService(private val context: Context) {
    companion object {
        private const val TAG = "GoogleGlassService"
    }

    private val _isConnected = MutableStateOf(false)
    val isConnected: StateFlow<Boolean> = _isConnected

    private val _statusText = MutableStateOf("No glasses connected.")
    val statusText: StateFlow<String> = _statusText

    private val _useGlassCamera = MutableStateOf(false)
    val useGlassCamera: StateFlow<Boolean> = _useGlassCamera

    private val _cameraFrame = MutableStateOf<Bitmap?>(null)
    val cameraFrame: StateFlow<Bitmap?> = _cameraFrame

    private var audioManager: AudioManager? = null
    private var glassCameraProvider: ProcessCameraProvider? = null
    private var glassImageCapture: ImageCapture? = null
    private val analysisExecutor = Executors.newSingleThreadExecutor()

    fun connect(activity: Activity) {
        audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioManager?.isBluetoothScoOn = true
        audioManager?.startBluetoothSco()
        _isConnected.value = true
        _statusText.value = "Connected to audio glasses"
    }

    fun disconnect() {
        audioManager?.stopBluetoothSco()
        audioManager?.isBluetoothScoOn = false
        glassCameraProvider?.unbindAll()
        glassCameraProvider = null
        glassImageCapture = null
        _isConnected.value = false
        _useGlassCamera.value = false
        _statusText.value = "Disconnected."
        _cameraFrame.value = null
    }

    fun setUseGlassCamera(enabled: Boolean) {
        _useGlassCamera.value = enabled
    }

    fun startGlassCamera(lifecycleOwner: LifecycleOwner, previewView: PreviewView) {
        if (!_useGlassCamera.value || !_isConnected.value) return

        try {
            val projectedContext = getProjectedContext() ?: run {
                _statusText.value = "Cannot access glasses camera."
                return
            }

            val cameraProviderFuture = ProcessCameraProvider.getInstance(projectedContext)
            cameraProviderFuture.addListener({
                try {
                    glassCameraProvider = cameraProviderFuture.get()

                    val preview = Preview.Builder().build().also {
                        it.surfaceProvider = previewView.surfaceProvider
                    }

                    glassImageCapture = ImageCapture.Builder()
                        .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
                        .build()

                    glassCameraProvider?.unbindAll()
                    // When using projected context, DEFAULT_BACK_CAMERA maps to glasses' camera
                    glassCameraProvider?.bindToLifecycle(
                        lifecycleOwner,
                        CameraSelector.DEFAULT_BACK_CAMERA,
                        preview,
                        glassImageCapture
                    )

                    _statusText.value = "Glasses camera active."
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to bind glasses camera", e)
                    _statusText.value = "Glasses camera failed: ${e.message}"
                }
            }, ContextCompat.getMainExecutor(projectedContext))
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get projected context for camera", e)
            _statusText.value = "Cannot access glasses camera: ${e.message}"
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

            imageCapture.takePicture(
                analysisExecutor,
                object : ImageCapture.OnImageCapturedCallback() {
                    override fun onCaptureSuccess(image: ImageProxy) {
                        resultBitmap = imageProxyToBitmap(image)
                        image.close()
                        latch.countDown()
                    }
                    override fun onError(exception: ImageCaptureException) {
                        latch.countDown()
                    }
                }
            )

            latch.await()
            resultBitmap
        } catch (_: Exception) { null }
    }

    private fun getProjectedContext(): Context? {
        return try {
            // ProjectedContext.createProjectedDeviceContext requires the XR SDK
            // This will be available when the XR SDK dependency is properly resolved
            // For now, return the phone context as fallback
            context
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create projected context", e)
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
            val matrix = Matrix().apply { postRotate(rotation.toFloat()) }
            Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        } else bitmap
    }
}
