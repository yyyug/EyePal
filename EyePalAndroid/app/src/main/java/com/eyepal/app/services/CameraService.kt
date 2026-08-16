package com.eyepal.app.services

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.YuvImage
import android.util.Size
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlin.coroutines.resume

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
                .setTargetResolution(Size(1280, 720))
                .build()
                .also { analysis ->
                    analysis.setAnalyzer(analysisExecutor) { imageProxy ->
                        onFrameAvailable?.let { callback ->
                            val bitmap = imageProxyToBitmap(imageProxy)
                            if (bitmap != null) {
                                callback(bitmap)
                            } else {
                                android.util.Log.w("CameraService", "Frame decode failed (${imageProxy.width}x${imageProxy.height}, planes=${imageProxy.planes.size}, rotation=${imageProxy.imageInfo.rotationDegrees})")
                            }
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
            withContext(Dispatchers.IO) {
                suspendCancellableCoroutine { cont ->
                    imageCapture.takePicture(
                        ContextCompat.getMainExecutor(context),
                        object : ImageCapture.OnImageCapturedCallback() {
                            override fun onCaptureSuccess(image: ImageProxy) {
                                try {
                                    val bitmap = imageProxyToBitmap(image)
                                    image.close()
                                    if (cont.isActive) cont.resume(bitmap) {}
                                } catch (e: Exception) {
                                    image.close()
                                    if (cont.isActive) cont.resume(null) {}
                                }
                            }
                            override fun onError(exception: ImageCaptureException) {
                                if (cont.isActive) cont.resume(null) {}
                            }
                        }
                    )
                }
            }
        } catch (_: Exception) { null }
    }

    private fun imageProxyToBitmap(imageProxy: ImageProxy): Bitmap? {
        // ImageAnalysis produces YUV_420_888 (3 planes), ImageCapture produces JPEG (1 plane)
        if (imageProxy.planes.size >= 3) {
            return yuv420ToBitmap(imageProxy)
        }
        // JPEG format (ImageCapture) - plane 0 contains complete JPEG data
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

    private fun yuv420ToBitmap(imageProxy: ImageProxy): Bitmap? {
        val planes = imageProxy.planes
        val yPlane = planes[0]
        val uPlane = planes[1]
        val vPlane = planes[2]
        val yBuffer = yPlane.buffer
        val uBuffer = uPlane.buffer
        val vBuffer = vPlane.buffer
        val yPixelStride = yPlane.pixelStride
        val uPixelStride = uPlane.pixelStride
        val vPixelStride = vPlane.pixelStride
        val yRowStride = yPlane.rowStride
        val uRowStride = uPlane.rowStride
        val vRowStride = vPlane.rowStride
        val width = imageProxy.width
        val height = imageProxy.height
        val uvWidth = width / 2
        val uvHeight = height / 2
        val nv21 = ByteArray(width * height * 3 / 2)

        var offset = 0
        if (yPixelStride == 1) {
            for (row in 0 until height) {
                yBuffer.position(row * yRowStride)
                yBuffer.get(nv21, offset, width)
                offset += width
            }
        } else {
            for (row in 0 until height) {
                val rowStart = row * yRowStride
                for (col in 0 until width) {
                    nv21[offset++] = yBuffer.get(rowStart + col * yPixelStride)
                }
            }
        }
        for (row in 0 until uvHeight) {
            for (col in 0 until uvWidth) {
                val vIdx = row * vRowStride + col * vPixelStride
                val uIdx = row * uRowStride + col * uPixelStride
                if (vIdx < vBuffer.capacity() && uIdx < uBuffer.capacity()) {
                    nv21[offset++] = vBuffer.get(vIdx)
                    nv21[offset++] = uBuffer.get(uIdx)
                }
            }
        }
        val yuvImage = YuvImage(nv21, ImageFormat.NV21, width, height, null)
        val out = ByteArrayOutputStream()
        yuvImage.compressToJpeg(Rect(0, 0, width, height), 90, out)
        val jpegData = out.toByteArray()
        val bitmap = BitmapFactory.decodeByteArray(jpegData, 0, jpegData.size)
        val rotation = imageProxy.imageInfo.rotationDegrees
        return bitmap?.let {
            if (rotation != 0) {
                val matrix = Matrix().apply { postRotate(rotation.toFloat()) }
                Bitmap.createBitmap(it, 0, 0, it.width, it.height, matrix, true)
            } else it
        }
    }
}
