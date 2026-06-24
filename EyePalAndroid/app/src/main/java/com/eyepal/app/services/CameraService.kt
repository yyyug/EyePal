package com.eyepal.app.services

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

class CameraService(private val context: Context) {
    private var imageCapture: ImageCapture? = null
    private var cameraProvider: ProcessCameraProvider? = null
    private val analysisExecutor = Executors.newSingleThreadExecutor()

    fun startCamera(
        lifecycleOwner: LifecycleOwner,
        previewView: PreviewView,
        onFrameAvailable: ((Bitmap) -> Unit)? = null
    ) {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(context)
        cameraProviderFuture.addListener({
            cameraProvider = cameraProviderFuture.get()

            val preview = Preview.Builder().build().also {
                it.surfaceProvider = previewView.surfaceProvider
            }

            imageCapture = ImageCapture.Builder()
                .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
                .build()

            val imageAnalysis = ImageAnalysis.Builder()
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build()
                .also { analysis ->
                    analysis.setAnalyzer(analysisExecutor) { imageProxy ->
                        onFrameAvailable?.let { callback ->
                            val bitmap = imageProxyToBitmap(imageProxy)
                            if (bitmap != null) callback(bitmap)
                        }
                        imageProxy.close()
                    }
                }

            try {
                cameraProvider?.unbindAll()
                cameraProvider?.bindToLifecycle(
                    lifecycleOwner,
                    CameraSelector.DEFAULT_BACK_CAMERA,
                    preview,
                    imageCapture,
                    imageAnalysis
                )
            } catch (_: Exception) {}
        }, ContextCompat.getMainExecutor(context))
    }

    fun stopCamera() {
        cameraProvider?.unbindAll()
    }

    suspend fun capturePhoto(): Bitmap? {
        val imageCapture = imageCapture ?: return null
        return try {
            val outputOptions = ImageCapture.OutputFileOptions.Builder(
                ByteArrayOutputStream()
            ).build()

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
