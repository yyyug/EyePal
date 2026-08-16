package com.eyepal.app.viewmodels

import android.app.Application
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Bitmap
import androidx.camera.view.PreviewView
import androidx.compose.runtime.mutableStateOf
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.viewModelScope
import com.eyepal.app.EyePalApplication
import com.eyepal.app.R
import com.eyepal.app.config.Defaults
import com.eyepal.app.services.GoogleGlassState
import com.eyepal.app.services.FaceRecognitionService
import com.eyepal.app.services.FaceRecognitionLogStore
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import java.util.Locale
import java.util.concurrent.atomic.AtomicBoolean

class FacesViewModel(application: Application) : AndroidViewModel(application) {
    data class RenameTarget(val id: String, val currentName: String)

    private fun str(resId: Int): String = getApplication<Application>().getString(resId)
    private fun str(resId: Int, vararg args: Any?): String = getApplication<Application>().getString(resId, *args)

    val statusText = mutableStateOf(str(R.string.instructions_face))
    val recognizedName = mutableStateOf<String?>(null)
    val isProcessing = mutableStateOf(false)
    private val processingLock = AtomicBoolean(false)
    val errorMessage = mutableStateOf<String?>(null)
    val profiles = mutableStateOf<List<FaceRecognitionService.SavedFaceProfile>>(emptyList())
    val pendingSaveName = mutableStateOf<String?>(null)
    val pendingEmbedding = mutableStateOf<FloatArray?>(null)
    val pendingSampleCount = mutableStateOf(0)
    val sampleTarget = 4
    private val pendingSampleEmbeddings = mutableListOf<FloatArray>()

    private val container = (application as EyePalApplication).container
    val camera = container.cameraService
    private val faceService = container.faceRecognitionService
    private val announcer = container.announcer
    private val settings = container.settingsRepository
    private var storedLifecycleOwner: LifecycleOwner? = null
    private var storedPreview: PreviewView? = null
    private var cameraStarted = false
    private var faceSpeechCooldown = Defaults.FACE_SPEECH_COOLDOWN

    val logEntries = mutableStateOf<List<FaceRecognitionLogStore.LogEntry>>(emptyList())

    init {
        viewModelScope.launch {
            faceService.recognitionThreshold = settings.faceMatchThreshold.first()
            faceService.minimumTopMatchMargin = settings.faceMatchMargin.first()
            faceService.knownMatchFrameThreshold = settings.faceMatchFrameThreshold.first()
            faceService.suggestUnknownFaces = settings.suggestUnknownFaces.first()
        }
        viewModelScope.launch {
            settings.faceMatchThreshold.collect { faceService.recognitionThreshold = it }
        }
        viewModelScope.launch {
            settings.faceMatchMargin.collect { faceService.minimumTopMatchMargin = it }
        }
        viewModelScope.launch {
            settings.faceMatchFrameThreshold.collect { faceService.knownMatchFrameThreshold = it }
        }
        viewModelScope.launch {
            settings.suggestUnknownFaces.collect { faceService.suggestUnknownFaces = it }
        }
        viewModelScope.launch {
            settings.faceSpeechCooldown.collect { faceSpeechCooldown = it }
        }
        viewModelScope.launch {
            try {
                faceService.load()
                profiles.value = faceService.getProfiles()
                logEntries.value = faceService.logStore.getEntries()
                if (!faceService.isEmbeddingReady) {
                    val detail = faceService.embeddingEngineError ?: str(R.string.error_onnx_failed)
                    statusText.value = str(R.string.status_face_engine_unavailable, detail)
                    errorMessage.value = statusText.value
                    android.util.Log.e("FacesVM", "Face engine unavailable: $detail")
                    announcer.announceForced(str(R.string.status_face_engine_unavailable, detail))
                } else {
                    statusText.value = str(R.string.status_face_engine_loaded)
                }
            } catch (e: Exception) {
                android.util.Log.e("FacesVM", "Failed to load face engine: ${e.message}", e)
                statusText.value = str(R.string.status_face_engine_error, e.message)
            }
        }
    }

    fun startCamera(previewView: android.view.View) {
        if (GoogleGlassState.useGlassCamera.value || cameraStarted) return
        val lo = (previewView.context as? LifecycleOwner) ?: return
        storedLifecycleOwner = lo
        val pv = previewView as? PreviewView ?: return
        storedPreview = pv
        cameraStarted = true
        camera.startCamera(lo, pv) { bitmap ->
            processFrame(bitmap)
        }
    }

    fun startCamera() {
        if (cameraStarted) return
        val lo = storedLifecycleOwner ?: return
        val pv = storedPreview ?: return
        if (GoogleGlassState.useGlassCamera.value) return
        cameraStarted = true
        camera.startCamera(lo, pv) { bitmap ->
            processFrame(bitmap)
        }
    }

    fun stopCamera() { cameraStarted = false; camera.stopCamera() }

    private fun processFrame(bitmap: Bitmap) {
        if (!processingLock.compareAndSet(false, true)) return
        isProcessing.value = true
        viewModelScope.launch {
            try {
                val result = faceService.processFrame(bitmap)
                if (result.match != null) {
                    recognizedName.value = result.match.name
                    statusText.value = str(R.string.status_recognized_with_confidence, result.match.name, String.format(Locale.US, "%.3f", result.match.confidence))
                    val faceCooldownMs = (faceSpeechCooldown * 1000).toLong()
                    announcer.announce(str(R.string.status_recognized, result.match.name), minimumInterval = faceCooldownMs)
                    logEntries.value = faceService.logStore.getEntries()
                    pendingSampleEmbeddings.clear()
                    pendingSampleCount.value = 0
                    if (pendingSaveName.value != null) {
                        pendingSaveName.value = null
                        faceService.resetSampleCollection()
                    }
                } else if (result.pendingSamples != null) {
                    recognizedName.value = null
                    val count = result.pendingSamples.count
                    val target = result.pendingSamples.target
                    pendingSampleEmbeddings.clear()
                    pendingSampleEmbeddings.addAll(result.pendingSamples.embeddings)
                    pendingSampleCount.value = count
                    if (count >= target || result.pendingSamples.suggestNow) {
                        pendingSaveName.value = ""
                        statusText.value = str(R.string.status_unknown_face_enter_name)
                        val faceCooldownMs = (faceSpeechCooldown * 1000).toLong()
                        announcer.announce(str(R.string.status_unknown_face_save), minimumInterval = faceCooldownMs)
                    } else {
                        statusText.value = str(R.string.label_capturing_samples, count, target)
                        announcer.announce(str(R.string.status_capturing_samples_announce, count, target), minimumInterval = 2000)
                    }
                } else {
                    if (recognizedName.value != null) {
                        recognizedName.value = null
                    }
                }
            } catch (e: Exception) {
                android.util.Log.e("FacesVM", "processFrame error: ${e.message}", e)
                statusText.value = str(R.string.status_error_prefix, e.message)
            }
            isProcessing.value = false
            processingLock.set(false)
        }
    }

    fun saveFace(name: String) {
        viewModelScope.launch {
            if (pendingSampleEmbeddings.isEmpty()) {
                pendingSaveName.value = null
                pendingEmbedding.value = null
                pendingSampleCount.value = 0
                faceService.resetSampleCollection()
                statusText.value = str(R.string.status_no_samples)
                return@launch
            }
            faceService.saveFaceMultiple(name, pendingSampleEmbeddings.toList())?.let { reason ->
                statusText.value = reason
                return@launch
            }
            profiles.value = faceService.getProfiles()
            logEntries.value = faceService.logStore.getEntries()
            pendingSaveName.value = null
            pendingEmbedding.value = null
            pendingSampleEmbeddings.clear()
            pendingSampleCount.value = 0
            statusText.value = str(R.string.status_saved_samples, name)
        }
    }

    fun dismissSave() {
        pendingSaveName.value = null
        pendingEmbedding.value = null
        pendingSampleEmbeddings.clear()
        pendingSampleCount.value = 0
        faceService.resetSampleCollection()
    }

    fun cancelCollection() {
        pendingSaveName.value = null
        pendingEmbedding.value = null
        pendingSampleEmbeddings.clear()
        pendingSampleCount.value = 0
        faceService.resetSampleCollection()
        statusText.value = str(R.string.status_collection_cancelled)
    }

    fun renameFace(id: String, newName: String) {
        viewModelScope.launch {
            faceService.renameFace(id, newName)
            profiles.value = faceService.getProfiles()
        }
    }

    fun deleteFace(id: String) {
        viewModelScope.launch {
            faceService.deleteFace(id)
            profiles.value = faceService.getProfiles()
        }
    }

    fun clearLog() {
        faceService.logStore.clear()
        logEntries.value = emptyList()
    }

    fun copyLog(context: Context) {
        val text = faceService.logStore.copyAll()
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("Face Log", text))
    }

    override fun onCleared() { super.onCleared(); faceService.close() }
}