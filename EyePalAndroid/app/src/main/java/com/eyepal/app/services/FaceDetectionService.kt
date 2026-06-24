package com.eyepal.app.services

import android.content.Context
import android.graphics.Bitmap
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

class FaceDetectionService(context: Context) {
    private val detector = FaceDetection.getClient(
        FaceDetectorOptions.Builder()
            .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
            .build()
    )

    suspend fun detectFaces(bitmap: Bitmap): List<DetectedFace> = suspendCancellableCoroutine { cont ->
        val image = InputImage.fromBitmap(bitmap, 0)
        detector.process(image)
            .addOnSuccessListener { faces ->
                val results = faces.map { face ->
                    val bounds = face.boundingBox
                    DetectedFace(
                        x = bounds.centerX(),
                        y = bounds.centerY(),
                        width = bounds.width(),
                        height = bounds.height(),
                        trackingId = face.trackingId
                    )
                }
                cont.resume(results)
            }
            .addOnFailureListener { cont.resumeWithException(it) }
    }

    fun close() { detector.close() }
}

data class DetectedFace(
    val x: Int,
    val y: Int,
    val width: Int,
    val height: Int,
    val trackingId: Int? = null
)
