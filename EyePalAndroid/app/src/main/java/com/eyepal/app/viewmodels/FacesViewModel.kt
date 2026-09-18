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
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import java.io.File
import java.util.Locale
import java.util.concurrent.atomic.AtomicBoolean

class FacesViewModel(application: Application) : AndroidViewModel(application) {
    data class RenameTarget(val id: String, val currentName: String)

    enum class EnrollmentState { IDLE, PENDING, RECORDING, RECORDED }

    private fun str(resId: Int): String = getApplication<Application>().getString(resId)
    private fun str(resId: Int, vararg args: Any?): String = getApplication<Application>().getString(resId, *args)

    val statusText = mutableStateOf(str(R.string.instructions_face))
    val recognizedName = mutableStateOf<String?>(null)
    val isProcessing = mutableStateOf(false)
    private val processingLock = AtomicBoolean(false)
    val errorMessage = mutableStateOf<String?>(null)
    val profiles = mutableStateOf<List<FaceRecognitionService.SavedFaceProfile>>(emptyList())
    val enrollmentState = mutableStateOf(EnrollmentState.IDLE)
    val enrollmentProgressText = mutableStateOf<String?>(null)
    val pendingSampleCount = mutableStateOf(0)
    val sampleTarget = 4
    private val pendingSampleEmbeddings = mutableListOf<FloatArray>()
    private var pendingAudioFile: File? = null
    private var autoStopJob: kotlinx.coroutines.Job? = null
    private val recordingDurationMs = 5000L

    private val container = (application as EyePalApplication).container
    val camera = container.cameraService
    private val faceService = container.faceRecognitionService
    private val announcer = container.announcer
    private val settings = container.settingsRepository
    private val recorder = com.eyepal.app.services.FaceAudioRecorder(
        File(getApplication<Application>().filesDir, "face_audio")
    )
    private val playbackPlayer = com.eyepal.app.services.FaceAudioPlayer(getApplication())
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
        val pv = previewView as? PreviewView ?: return
        storedLifecycleOwner = lo
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
                    announceRecognized(result.match.name, faceCooldownMs)
                    logEntries.value = faceService.logStore.getEntries()
                    pendingSampleEmbeddings.clear()
                    pendingSampleCount.value = 0
                    if (enrollmentState.value != EnrollmentState.IDLE) {
                        cancelEnrollment()
                    }
                } else if (result.pendingSamples != null) {
                    recognizedName.value = null
                    val count = result.pendingSamples.count
                    val target = result.pendingSamples.target
                    pendingSampleEmbeddings.clear()
                    pendingSampleEmbeddings.addAll(result.pendingSamples.embeddings)
                    pendingSampleCount.value = count
                    if (result.pendingSamples.suggestNow) {
                        val tooSimilar = faceService.tooSimilarProfile(pendingSampleEmbeddings.toList())
                        if (tooSimilar != null) {
                            faceService.logStore.append(
                                "Not offering save: too similar to '${tooSimilar.first}' (${String.format(Locale.US, "%.4f", tooSimilar.second)})"
                            )
                            pendingSampleEmbeddings.clear()
                            pendingSampleCount.value = 0
                            faceService.resetSampleCollection()
                        } else {
                            beginEnrollment(pendingSampleEmbeddings.toList())
                        }
                    } else {
                        if (enrollmentState.value == EnrollmentState.IDLE) {
                            statusText.value = str(R.string.label_capturing_samples, count, target)
                            announcer.announce(str(R.string.status_capturing_samples_announce, count, target), minimumInterval = 2000)
                        }
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

    private fun announceRecognized(name: String, cooldownMs: Long) {
        val profile = profiles.value.firstOrNull { it.name == name }
        val note = profile?.textNote?.trim().orEmpty()
        if (note.isNotEmpty()) {
            announcer.announce(note, minimumInterval = cooldownMs)
            return
        }
        val file = profile?.soundFilename?.let { faceService.recordingFile(it) }
        if (file?.exists() == true) {
            playbackPlayer.play(file)
            return
        }
        announcer.announce(str(R.string.status_recognized, name), minimumInterval = cooldownMs)
    }

    // MARK: - No-dialog enrollment

    fun beginEnrollment(embeddings: List<FloatArray>) {
        if (enrollmentState.value != EnrollmentState.IDLE) return
        if (embeddings.isEmpty()) return
        pendingSampleEmbeddings.clear()
        pendingSampleEmbeddings.addAll(embeddings)
        pendingAudioFile = null
        enrollmentState.value = EnrollmentState.PENDING
        enrollmentProgressText.value = str(R.string.status_new_face_ready)
        statusText.value = str(R.string.status_new_face_save_hint)
        announcer.announce(str(R.string.status_new_face_save_hint), minimumInterval = 0)
    }

    fun triggerEnrollment() {
        when (enrollmentState.value) {
            EnrollmentState.IDLE -> Unit
            EnrollmentState.PENDING -> startRecording()
            EnrollmentState.RECORDING, EnrollmentState.RECORDED -> completeSave()
        }
    }

    fun reRecord() {
        if (enrollmentState.value != EnrollmentState.RECORDING && enrollmentState.value != EnrollmentState.RECORDED) return
        autoStopJob?.cancel()
        autoStopJob = null
        recorder.cancel()
        pendingAudioFile = null
        startRecording()
    }

    fun cancelEnrollment() {
        autoStopJob?.cancel()
        autoStopJob = null
        recorder.cancel()
        pendingAudioFile = null
        pendingSampleEmbeddings.clear()
        pendingSampleCount.value = 0
        faceService.resetSampleCollection()
        enrollmentState.value = EnrollmentState.IDLE
        enrollmentProgressText.value = null
        statusText.value = str(R.string.status_face_cancelled)
        announcer.announce(str(R.string.status_face_cancelled), minimumInterval = 0)
    }

    fun dismissSave() = cancelEnrollment()

    fun cancelCollection() {
        if (enrollmentState.value != EnrollmentState.IDLE) {
            cancelEnrollment()
            return
        }
        faceService.resetSampleCollection()
        statusText.value = str(R.string.status_collection_cancelled)
    }

    private fun startRecording() {
        if (enrollmentState.value != EnrollmentState.PENDING) return
        if (!recorder.start()) {
            val msg = recorder.lastError?.let { str(R.string.status_face_failed) } ?: str(R.string.status_mic_required)
            enrollmentProgressText.value = msg
            statusText.value = msg
            announcer.announce(msg, minimumInterval = 0)
            return
        }
        enrollmentState.value = EnrollmentState.RECORDING
        enrollmentProgressText.value = str(R.string.status_recording_prompt)
        statusText.value = str(R.string.status_recording_started)
        announcer.announce(str(R.string.status_recording_started), minimumInterval = 0)
        autoStopJob = viewModelScope.launch {
            delay(recordingDurationMs)
            autoStopJob = null
            finishRecording()
        }
    }

    private fun finishRecording() {
        if (enrollmentState.value != EnrollmentState.RECORDING) return
        val file = recorder.stop()
        pendingAudioFile = file
        enrollmentState.value = EnrollmentState.RECORDED
        enrollmentProgressText.value = str(R.string.status_recorded_ready)
        if (file == null) {
            enrollmentProgressText.value = recorder.lastError ?: str(R.string.status_face_failed)
            statusText.value = enrollmentProgressText.value ?: ""
            announcer.announce(enrollmentProgressText.value ?: "", minimumInterval = 0)
            return
        }
        statusText.value = str(R.string.status_recorded_prompt)
        announcer.announce(str(R.string.status_recorded_ready), minimumInterval = 0)
    }

    private fun completeSave(textName: String? = null) {
        val state = enrollmentState.value
        val canSaveWithText = state == EnrollmentState.PENDING && textName != null
        if (state != EnrollmentState.RECORDING && state != EnrollmentState.RECORDED && !canSaveWithText) return
        if (state == EnrollmentState.RECORDING) {
            autoStopJob?.cancel()
            autoStopJob = null
            pendingAudioFile = recorder.stop()
        }
        val embeddings = pendingSampleEmbeddings.toList()
        val audio = pendingAudioFile
        if (embeddings.isEmpty()) {
            cancelEnrollment()
            return
        }
        val resolvedName = textName?.trim()?.takeIf { it.isNotEmpty() } ?: unnamedName()
        viewModelScope.launch {
            try {
                val reason = faceService.saveFaceMultiple(resolvedName, embeddings, audio)
                if (reason != null) {
                    enrollmentProgressText.value = reason
                    statusText.value = reason
                    announcer.announce(reason, minimumInterval = 0)
                } else {
                    profiles.value = faceService.getProfiles()
                    logEntries.value = faceService.logStore.getEntries()
                    val done = str(R.string.status_saved_with_note, resolvedName)
                    enrollmentProgressText.value = done
                    statusText.value = done
                    announcer.announce(done, minimumInterval = 0)
                }
                pendingAudioFile = null
                pendingSampleEmbeddings.clear()
                pendingSampleCount.value = 0
                faceService.resetSampleCollection()
                enrollmentState.value = EnrollmentState.IDLE
            } catch (e: Exception) {
                val failed = str(R.string.status_face_failed)
                enrollmentProgressText.value = failed
                statusText.value = failed
                announcer.announce(failed, minimumInterval = 0)
            }
        }
    }

    /** Saves the pending face with a typed name and no voice note. */
    fun saveWithTextName(name: String) {
        completeSave(name)
    }

    /** Default name for a face saved without a typed name; kept unique so a new
     *  face never overwrites an existing profile. */
    private fun unnamedName(): String {
        val base = str(R.string.face_unnamed_name)
        if (profiles.value.none { it.name.equals(base, ignoreCase = true) }) return base
        var index = 2
        while (profiles.value.any { it.name.equals("$base $index", ignoreCase = true) }) index++
        return "$base $index"
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

    override fun onCleared() {
        super.onCleared()
        autoStopJob?.cancel()
        autoStopJob = null
        runCatching { recorder.cancel() }
        playbackPlayer.release()
        faceService.close()
    }
}