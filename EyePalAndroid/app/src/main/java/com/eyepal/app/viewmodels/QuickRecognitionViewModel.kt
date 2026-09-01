package com.eyepal.app.viewmodels

import android.app.Application
import android.content.Context
import android.graphics.Bitmap
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.SystemClock
import androidx.camera.view.PreviewView
import androidx.compose.runtime.mutableStateOf
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.viewModelScope
import com.eyepal.app.EyePalApplication
import com.eyepal.app.R
import com.eyepal.app.config.Defaults
import com.eyepal.app.services.GoogleGlassState
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONArray
import kotlin.math.abs

enum class QuickPresetKind(val typeName: String, val defaultName: String, val defaultPrompt: String) {
    PRODUCT("Product", "Product", "Describe the main product with brand, name and function"),
    DISH("Dish", "Dish", "Describe the food layout on the plate using clock positions"),
    SHORT_TEXT("Short Text", "Short Text", "Read the visible text in the image"),
    CUSTOM("Custom", "Custom", "");

    companion object {
        fun fromTypeName(name: String): QuickPresetKind = entries.find { it.typeName == name } ?: CUSTOM
    }
}

class QuickRecognitionViewModel(application: Application) : AndroidViewModel(application), SensorEventListener {
    private fun str(resId: Int): String = getApplication<Application>().getString(resId)
    private fun str(resId: Int, vararg args: Any?): String = getApplication<Application>().getString(resId, *args)

    val statusText = mutableStateOf(str(R.string.instructions_describe))
    val responseText = mutableStateOf("")
    val isProcessing = mutableStateOf(false)
    val isContinuousCapture = mutableStateOf(false)
    val capturedImage = mutableStateOf<Bitmap?>(null)
    val errorMessage = mutableStateOf<String?>(null)
    val apiKey = mutableStateOf("")
    val quickModelProvider = mutableStateOf(Defaults.QUICK_MODEL_PROVIDER)

    val presets = mutableStateOf<List<QuickPresetConfig>>(emptyList())
    val captionLength = mutableStateOf<QuickCaptionLength>(QuickCaptionLength.SHORT)
    val captureInterval = mutableStateOf(QuickContinuousInterval._3S)
    val triggerMode = mutableStateOf(QuickTriggerMode.TIME)

    private val container = (application as EyePalApplication).container
    val camera = container.cameraService
    private val moondream = container.moondreamService
    private val gemmaManager = container.gemmaModelManager
    private val gemmaService = container.gemmaTextRecognitionService
    private val translationService = container.translationService
    private val glassService = container.glassService
    private val announcer = container.announcer
    private val settings = container.settingsRepository
    private val sensorManager = getApplication<Application>().getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private var continuousJob: Job? = null
    private var motionAccumulatedMs: Long = 0
    private var lastMotionSampleTime: Long = 0
    private val motionActivityThreshold = 3.5f
    private var lastPrompt = "Describe what you see briefly"
    private var storedLifecycleOwner: LifecycleOwner? = null
    private var storedPreview: PreviewView? = null
    private var cameraStarted = false

    init {
        viewModelScope.launch { loadSettings() }
    }

    suspend fun loadSettings() {
        val savedPresetsJson = settings.quickPresets.first()
        presets.value = try {
            if (savedPresetsJson.isNotEmpty()) {
                val arr = JSONArray(savedPresetsJson)
                (0 until arr.length()).map { i ->
                    val obj = arr.getJSONObject(i)
                    QuickPresetConfig(
                        obj.optString("name", ""),
                        obj.optString("prompt", ""),
                        obj.optString("type", "Custom")
                    )
                }.take(4)
            } else {
                defaultPresets()
            }
        } catch (_: Exception) { defaultPresets() }

        captionLength.value = QuickCaptionLength.entries.find {
            it.value == settings.quickCaptionLength.first()
        } ?: QuickCaptionLength.SHORT

        captureInterval.value = QuickContinuousInterval.fromValue(
            settings.quickContinuousInterval.first()
        )

        triggerMode.value = QuickTriggerMode.fromValue(
            settings.quickTriggerMode.first()
        )

        apiKey.value = settings.quickMoondreamAPIKey.first()
        quickModelProvider.value = settings.quickModelProvider.first()
    }

    private fun defaultPresets() = listOf(
        QuickPresetConfig("Custom", "Tell me how many men and women there are and describe them; if not found, say No people found", "Custom"),
        QuickPresetConfig("Product", "Describe the main product in this image with 1 or 2 sentences, including its brand, name and primary function", "Product"),
        QuickPresetConfig("Dish", "Describe the layout of the food on the plate or tray. Use clock positions or spatial terms", "Dish"),
        QuickPresetConfig("Short Text", "Describe the alphanumeric text visible in the image", "Short Text")
    )

    fun startCamera(previewView: android.view.View) {
        if (GoogleGlassState.useGlassCamera.value || cameraStarted) return
        val lo = (previewView.context as? LifecycleOwner) ?: return
        storedLifecycleOwner = lo
        storedPreview = previewView as? PreviewView ?: return
        cameraStarted = true
        camera.startCamera(lo, storedPreview!!)
    }

    fun startCamera() {
        if (cameraStarted) return
        val lo = storedLifecycleOwner ?: return
        val pv = storedPreview ?: return
        if (GoogleGlassState.useGlassCamera.value) return
        cameraStarted = true
        camera.startCamera(lo, pv)
    }

    fun stopCamera() { cameraStarted = false; camera.stopCamera() }

    fun takePhoto() { lastPrompt = "Describe what you see briefly"; capture() }

    fun takePresetPhoto(prompt: String) { lastPrompt = prompt; capture() }

    fun startContinuousMode() {
        if (isContinuousCapture.value) return
        isContinuousCapture.value = true
        statusText.value = str(R.string.status_continuous_running)
        if (triggerMode.value == QuickTriggerMode.ON_THE_MOVE) {
            startOnTheMoveLoop()
            return
        }
        continuousJob = viewModelScope.launch {
            while (isContinuousCapture.value) { capture(); delay(captureInterval.value.value.toLong()) }
        }
    }

    fun stopContinuous() {
        stopOnTheMoveLoop()
        continuousJob?.cancel()
        continuousJob = null
        isContinuousCapture.value = false
        if (!isProcessing.value) statusText.value = str(R.string.status_ready)
    }

    private fun startOnTheMoveLoop() {
        motionAccumulatedMs = 0
        lastMotionSampleTime = 0
        val accel = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        if (accel == null) {
            isContinuousCapture.value = false
            statusText.value = str(R.string.quick_motion_sensor_unavailable)
            return
        }
        sensorManager.registerListener(this, accel, SensorManager.SENSOR_DELAY_NORMAL)
    }

    private fun stopOnTheMoveLoop() {
        sensorManager.unregisterListener(this)
        motionAccumulatedMs = 0
        lastMotionSampleTime = 0
    }

    override fun onSensorChanged(event: SensorEvent?) {
        event ?: return
        if (event.sensor.type != Sensor.TYPE_ACCELEROMETER) return
        if (!isContinuousCapture.value || isProcessing.value) return

        val values = event.values
        val magnitude = abs(values[0]) + abs(values[1]) + abs(values[2])
        val now = SystemClock.elapsedRealtimeNanos()
        if (lastMotionSampleTime == 0L) { lastMotionSampleTime = now; return }
        val deltaMs = (now - lastMotionSampleTime) / 1_000_000L
        lastMotionSampleTime = now

        if (magnitude > motionActivityThreshold) {
            motionAccumulatedMs += deltaMs
            if (motionAccumulatedMs >= captureInterval.value.value.toLong()) {
                motionAccumulatedMs = 0
                capture()
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    private fun capture() {
        if (isProcessing.value) return
        isProcessing.value = true
        statusText.value = str(R.string.status_analyzing_scene)
        viewModelScope.launch {
            try {
                var bitmap: Bitmap? = null
                for (attempt in 1..3) {
                    bitmap = if (GoogleGlassState.useGlassCamera.value) glassService.capturePhotoFromGlasses() else camera.capturePhoto()
                    if (bitmap != null) break
                    delay(500)
                }
                if (bitmap == null) throw Exception(str(R.string.error_camera_not_ready))
                capturedImage.value = bitmap
                val useGemmaOffline = settings.quickModelProvider.first() == "gemma" && gemmaService.canRun()
                val result: String
                if (useGemmaOffline) {
                    result = gemmaService.generateCaption(bitmap, captionLength.value)
                } else {
                    val apiKey = settings.quickMoondreamAPIKey.first()
                    if (apiKey.isEmpty()) { responseText.value = str(R.string.quick_no_api_key); isProcessing.value = false; return@launch }
                    result = moondream.describeImage(bitmap, apiKey, applyCaptionLength(lastPrompt))
                }
                val translationEnabled = settings.quickTranslationEnabled.first()
                val targetLanguage = settings.quickTranslationTarget.first()
                if (translationEnabled) {
                    translationService.setLanguages("en", targetLanguage)
                    val translated = translationService.translate(result)
                    responseText.value = translated
                    announcer.announce(translated)
                } else {
                    responseText.value = result
                    announcer.announce(result)
                }
                statusText.value = str(R.string.status_result_ready)
            } catch (e: Exception) { errorMessage.value = e.message; statusText.value = str(R.string.status_failed, e.message) }
            isProcessing.value = false
        }
    }

    private fun applyCaptionLength(prompt: String): String {
        val suffix = captionLength.value.promptSuffix
        return if (suffix.isNotEmpty()) "$prompt $suffix" else prompt
    }

    fun clearError() { errorMessage.value = null }

    fun gemmaCanRunOffline(): Boolean = gemmaService.canRun()

    override fun onCleared() {
        super.onCleared()
        translationService.close()
        gemmaService.close()
    }
}

data class QuickPresetConfig(
    val name: String,
    val prompt: String,
    val type: String = "Custom"
)

enum class QuickCaptionLength(val value: String, val labelRes: Int, val promptSuffix: String) {
    SHORT("short", R.string.caption_short, "Be very brief, one sentence."),
    NORMAL("normal", R.string.caption_normal, ""),
    DETAILED("detailed", R.string.caption_detailed, "Describe in detail, including colors, positions, and context.")
}

enum class RecognitionActionControlStyle(val value: String, val labelRes: Int) {
    ON_SCREEN_BUTTONS("onScreenButtons", R.string.control_style_buttons),
    SINGLE_ADJUSTABLE_CONTROL("singleAdjustableControl", R.string.control_style_single);

    companion object {
        fun fromValue(value: String): RecognitionActionControlStyle =
            entries.find { it.value == value } ?: ON_SCREEN_BUTTONS
    }
}

enum class QuickContinuousInterval(val value: Int, val labelRes: Int) {
    _1S(1000, R.string.interval_1_second),
    _2S(2000, R.string.interval_2_seconds),
    _3S(3000, R.string.interval_3_seconds),
    _5S(5000, R.string.interval_5_seconds),
    _10S(10000, R.string.interval_10_seconds),
    _30S(30000, R.string.interval_30_seconds),
    _1M(60000, R.string.interval_1_minute),
    _2M(120000, R.string.interval_2_minutes);

    companion object {
        fun fromValue(ms: Int): QuickContinuousInterval = entries.find { it.value == ms } ?: _3S
        val optionValues: List<Int> get() = entries.map { it.value }
        val optionLabelRes: List<Int> get() = entries.map { it.labelRes }
    }
}

enum class QuickTriggerMode(val value: String, val labelRes: Int) {
    TIME("time", R.string.trigger_mode_time),
    ON_THE_MOVE("onTheMove", R.string.trigger_mode_on_the_move);

    companion object {
        fun fromValue(value: String): QuickTriggerMode = entries.find { it.value == value } ?: TIME
    }
}