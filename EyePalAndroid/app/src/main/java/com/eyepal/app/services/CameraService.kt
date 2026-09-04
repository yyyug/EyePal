package com.eyepal.app.services

import android.content.Context
import android.content.ContextWrapper
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.YuvImage
import android.os.SystemClock
import android.util.Size
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import kotlinx.coroutines.delay
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlin.coroutines.resume

/**
 * Shared camera service bound once to the **Activity** lifecycle so the camera stays alive and
 * correctly configured across bottom-tab switches. Switching tabs changes which [PreviewView]
 * receives the preview (and which frame callback is active) but never tears down and re-wires the
 * whole camera from scratch, which previously raced and left [imageCapture] unset — causing
 * `capturePhoto` to report "camera fail" right after switching from the Text tab to the Quick tab.
 */
class CameraService(private val context: Context) {
    private var imageCapture: ImageCapture? = null
    private var preview: Preview? = null
    private var cameraProvider: ProcessCameraProvider? = null
    private var boundOwner: LifecycleOwner? = null
    private var analyzerCallback: ((Bitmap) -> Unit)? = null
    private val analysisExecutor = Executors.newSingleThreadExecutor()

    fun startCamera(
        owner: LifecycleOwner,
        previewView: PreviewView,
        onFrameAvailable: ((Bitmap) -> Unit)? = null
    ) {
        analyzerCallback = onFrameAvailable
        val activityOwner: LifecycleOwner = resolveActivity(previewView) ?: owner

        val cameraProviderFuture = ProcessCameraProvider.getInstance(context)
        cameraProviderFuture.addListener({
            val provider = try {
                cameraProviderFuture.get()
            } catch (_: Exception) {
                return@addListener
            }
            cameraProvider = provider
            bindTo(provider, activityOwner, previewView, onFrameAvailable)
        }, ContextCompat.getMainExecutor(context))
    }

    private fun bindTo(
        provider: ProcessCameraProvider,
        owner: LifecycleOwner,
        previewView: PreviewView,
        onFrameAvailable: ((Bitmap) -> Unit)?
    ) {
        // Already bound to this (activity) lifecycle: just swap the preview surface + analyzer.
        if (boundOwner === owner && provider == cameraProvider && preview != null) {
            preview?.surfaceProvider = previewView.surfaceProvider
            analyzerCallback = onFrameAvailable
            return
        }

        val p = Preview.Builder().build().also { it.surfaceProvider = previewView.surfaceProvider }

        val ic = ImageCapture.Builder()
            .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
            .build()

        val analysis = ImageAnalysis.Builder()
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .setTargetResolution(Size(1280, 720))
            .build()
            .also { a ->
                a.setAnalyzer(analysisExecutor) { imageProxy ->
                    val cb = analyzerCallback
                    if (cb != null) {
                        val bitmap = imageProxyToBitmap(imageProxy)
                        if (bitmap != null) {
                            cb(bitmap)
                        } else {
                            android.util.Log.w("CameraService", "Frame decode failed (${imageProxy.width}x${imageProxy.height}, planes=${imageProxy.planes.size}, rotation=${imageProxy.imageInfo.rotationDegrees})")
                        }
                    }
                    imageProxy.close()
                }
            }

        preview = p
        boundOwner = owner

        try {
            provider.unbindAll()
            provider.bindToLifecycle(
                owner,
                CameraSelector.DEFAULT_BACK_CAMERA,
                p,
                ic,
                analysis
            )
            imageCapture = ic
        } catch (e: Exception) {
            android.util.Log.e("CameraService", "bindToLifecycle failed", e)
        }
    }

    fun stopCamera() {
        imageCapture = null
        preview = null
        analyzerCallback = null
        cameraProvider?.unbindAll()
        boundOwner = null
    }

    /**
     * Captures a photo, waiting briefly for the camera to be bound before giving up. On a tab
     * switch the rebind can still be in flight, so rather than returning null immediately (which
     * the callers interpret as "camera fail"), we wait up to ~1.5s for a ready [imageCapture].
     */
    suspend fun capturePhoto(): Bitmap? {
        val deadline = SystemClock.elapsedRealtime() + 1500L
        while (imageCapture == null && SystemClock.elapsedRealtime() < deadline) {
            delay(50)
        }
        val capture = imageCapture
        if (capture == null) {
            android.util.Log.w("CameraService", "capturePhoto: imageCapture not ready after 1500ms (preview=${preview != null}, boundOwner=${boundOwner != null})")
            return null
        }
        return try {
            withContext(Dispatchers.IO) {
                suspendCancellableCoroutine { cont ->
                    capture.takePicture(
                        ContextCompat.getMainExecutor(context),
                        object : ImageCapture.OnImageCapturedCallback() {
                            override fun onCaptureSuccess(image: ImageProxy) {
                                try {
                                    val bitmap = imageProxyToBitmap(image)
                                    image.close()
                                    android.util.Log.i("CameraService", "capturePhoto success ${bitmap?.width}x${bitmap?.height}")
                                    if (cont.isActive) cont.resume(bitmap) {}
                                } catch (e: Exception) {
                                    image.close()
                                    android.util.Log.w("CameraService", "capturePhoto decode failed: ${e.message}")
                                    if (cont.isActive) cont.resume(null) {}
                                }
                            }
                            override fun onError(exception: ImageCaptureException) {
                                android.util.Log.w("CameraService", "capturePhoto onError: ${exception.message}")
                                if (cont.isActive) cont.resume(null) {}
                            }
                        }
                    )
                }
            }
        } catch (e: Exception) {
            android.util.Log.w("CameraService", "capturePhoto exception: ${e.message}")
            null
        }
    }

    private fun resolveActivity(view: android.view.View?): LifecycleOwner? {
        var ctx = view?.context
        while (ctx is ContextWrapper) {
            if (ctx is LifecycleOwner) return ctx
            ctx = ctx.baseContext
        }
        return ctx as? LifecycleOwner
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
