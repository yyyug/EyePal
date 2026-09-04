package com.eyepal.app.viewmodels

import android.app.Application
import android.graphics.Bitmap
import androidx.camera.view.PreviewView
import androidx.compose.runtime.mutableStateOf
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.viewModelScope
import com.eyepal.app.EyePalApplication
import com.eyepal.app.R
import com.eyepal.app.services.GoogleGlassState
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlin.math.max
import java.util.concurrent.atomic.AtomicBoolean

class ReadTextViewModel(application: Application) : AndroidViewModel(application) {
    private fun str(resId: Int): String = getApplication<Application>().getString(resId)
    private fun str(resId: Int, vararg args: Any?): String = getApplication<Application>().getString(resId, *args)

    val statusText = mutableStateOf(str(R.string.instructions_text))
    val recognizedText = mutableStateOf("")
    val isProcessing = mutableStateOf(false)
    private val processingLock = AtomicBoolean(false)
    val errorMessage = mutableStateOf<String?>(null)
    val detectedLanguage = mutableStateOf("")
    val isDocumentMode = mutableStateOf(false)
    val showCaptureDialog = mutableStateOf(false)
    val capturedTextForDisplay = mutableStateOf("")

    private val container = (application as EyePalApplication).container
    val camera = container.cameraService
    private val ocr = container.ocrService
    private val glassService = container.glassService
    private val announcer = container.announcer
    private val settings = container.settingsRepository
    private var lastAnnouncedText = ""
    private var lastFrameText = ""
    private var stableCount = 0
    private var documentStableCount = 0
    private var storedLifecycleOwner: LifecycleOwner? = null
    private var storedPreview: PreviewView? = null
    private var cameraStarted = false

    companion object {
        private const val TAG = "ReadTextVM"
        private const val STABILITY_THRESHOLD = 0.8f
        private const val STABLE_ANNOUNCE_COUNT = 2
        private const val DOCUMENT_FRAME_WIDTH = 1080
        private const val DOCUMENT_FRAME_HEIGHT = 1920
        private const val DOCUMENT_TEXT_COVERAGE_THRESHOLD = 0.5f
        private const val DOCUMENT_STABLE_COUNT_THRESHOLD = 3
    }

    fun startCamera(previewView: android.view.View) {
        if (GoogleGlassState.useGlassCamera.value || cameraStarted) return
        val lo = (previewView.context as? LifecycleOwner) ?: return
        storedLifecycleOwner = lo
        storedPreview = previewView as? PreviewView
        cameraStarted = true
        camera.startCamera(lo, storedPreview!!) { bitmap ->
            if (!isProcessing.value) recognizeFrame(bitmap)
        }
    }

    fun startCamera() {
        if (cameraStarted) return
        val lo = storedLifecycleOwner ?: return
        val pv = storedPreview ?: return
        if (GoogleGlassState.useGlassCamera.value) return
        cameraStarted = true
        camera.startCamera(lo, pv) { bitmap ->
            if (!isProcessing.value) recognizeFrame(bitmap)
        }
    }

    fun stopCamera() { cameraStarted = false; camera.stopCamera() }

    fun captureAndRecognize() {
        if (!processingLock.compareAndSet(false, true)) {
            android.util.Log.w(TAG, "captureAndRecognize skipped: already processing")
            return
        }
        isProcessing.value = true
        statusText.value = str(R.string.status_capturing_text)
        android.util.Log.i(TAG, "captureAndRecognize: start")
        viewModelScope.launch {
            try {
                var bitmap: Bitmap? = null
                for (attempt in 1..3) {
                    bitmap = if (GoogleGlassState.useGlassCamera.value) glassService.capturePhotoFromGlasses() else camera.capturePhoto()
                    android.util.Log.i(TAG, "captureAndRecognize: attempt=$attempt got bitmap=${bitmap != null}")
                    if (bitmap != null) break
                    kotlinx.coroutines.delay(500)
                }
                if (bitmap == null) {
                    android.util.Log.w(TAG, "captureAndRecognize: camera not ready after 3 attempts")
                    throw Exception(str(R.string.error_camera_not_ready))
                }
                val startMs = System.currentTimeMillis()
                val result = ocr.recognizeText(bitmap)
                android.util.Log.i(TAG, "captureAndRecognize: ocr done in ${System.currentTimeMillis() - startMs}ms engine=${ocr.currentEngine} text=${result.text.take(120)}")
                recognizedText.value = result.text
                detectedLanguage.value = result.detectedLanguage
                statusText.value = str(R.string.status_text_recognized)
                capturedTextForDisplay.value = result.text
                showCaptureDialog.value = true
                announcer.announce(result.text)
            } catch (e: Exception) {
                android.util.Log.e(TAG, "captureAndRecognize error: ${e.message}")
                errorMessage.value = e.message; statusText.value = str(R.string.status_failed, e.message)
            }
            isProcessing.value = false
            processingLock.set(false)
        }
    }

    private fun recognizeFrame(bitmap: Bitmap) {
        if (!processingLock.compareAndSet(false, true)) return
        isProcessing.value = true
        viewModelScope.launch {
            try {
                val startMs = System.currentTimeMillis()
                val result = ocr.recognizeText(bitmap)
                val elapsed = System.currentTimeMillis() - startMs
                errorMessage.value = null
                val text = result.text
                android.util.Log.i(TAG, "frame: engine=${ocr.currentEngine} ${elapsed}ms text='${text.take(80)}' stable=$stableCount lastAnnounced='${lastAnnouncedText.take(40)}'")
                if (text.isNotBlank() && text != lastAnnouncedText) {
                    detectedLanguage.value = result.detectedLanguage

                    val similarity = textSimilarity(text, lastFrameText)
                    if (similarity >= STABILITY_THRESHOLD) {
                        stableCount++
                    } else {
                        stableCount = 1
                        lastFrameText = text
                    }

                    recognizedText.value = text

                    if (stableCount >= STABLE_ANNOUNCE_COUNT) {
                        lastAnnouncedText = text
                        stableCount = 0
                        val textCooldownMs = (settings.readTextSpeechCooldown.first() * 1000).toLong()
                        android.util.Log.i(TAG, "ANNOUNCING: '${text.take(80)}'")
                        announcer.announce(text, minimumInterval = textCooldownMs)
                    }

                    if (isDocumentMode.value) {
                        val coverage = calculateTextCoverage(result.textBlocks, bitmap.width, bitmap.height)
                        if (coverage > DOCUMENT_TEXT_COVERAGE_THRESHOLD) {
                            documentStableCount++
                            if (documentStableCount >= DOCUMENT_STABLE_COUNT_THRESHOLD) {
                                documentStableCount = 0
                                capturedTextForDisplay.value = text
                                showCaptureDialog.value = true
                                android.util.Log.i(TAG, "DOCUMENT auto-capture: '${text.take(80)}'")
                            }
                        } else {
                            documentStableCount = 0
                        }
                    }
                } else if (text.isBlank()) {
                    lastAnnouncedText = ""
                    lastFrameText = ""
                    stableCount = 0
                } else {
                    // text is not blank but equals lastAnnouncedText -> intentional anti-repeat
                    android.util.Log.i(TAG, "anti-repeat: text == lastAnnouncedText (not re-announcing)")
                }
            } catch (e: Exception) {
                android.util.Log.i(TAG, "recognizeFrame error: ${e.message}")
                if (errorMessage.value != e.message) {
                    errorMessage.value = e.message
                    statusText.value = str(R.string.status_recognition_error, e.message)
                }
            }
            isProcessing.value = false
            processingLock.set(false)
        }
    }

    private fun textSimilarity(a: String, b: String): Float {
        if (a.isEmpty() && b.isEmpty()) return 1.0f
        if (a.isEmpty() || b.isEmpty()) return 0.0f
        val distance = levenshteinDistance(a, b)
        return 1.0f - distance.toFloat() / max(a.length, b.length)
    }

    private fun levenshteinDistance(s1: String, s2: String): Int {
        val len1 = s1.length
        val len2 = s2.length
        val dp = Array(len1 + 1) { IntArray(len2 + 1) }
        for (i in 0..len1) dp[i][0] = i
        for (j in 0..len2) dp[0][j] = j
        for (i in 1..len1) {
            for (j in 1..len2) {
                val cost = if (s1[i - 1] == s2[j - 1]) 0 else 1
                dp[i][j] = minOf(
                    dp[i - 1][j] + 1,
                    dp[i][j - 1] + 1,
                    dp[i - 1][j - 1] + cost
                )
            }
        }
        return dp[len1][len2]
    }

    private fun calculateTextCoverage(blocks: List<com.eyepal.app.services.TextBlockInfo>, frameWidth: Int, frameHeight: Int): Float {
        if (blocks.isEmpty()) return 0f
        val frameArea = (frameWidth * frameHeight).toFloat()
        if (frameArea <= 0f) return 0f
        val totalTextArea = blocks.sumOf { it.bounds.width().toLong() * it.bounds.height().toLong() }.toFloat()
        return totalTextArea / frameArea
    }

    override fun onCleared() { super.onCleared(); ocr.close() }
}