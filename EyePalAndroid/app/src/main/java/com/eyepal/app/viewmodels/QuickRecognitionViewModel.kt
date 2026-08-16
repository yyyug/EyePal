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
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONArray

enum class QuickPresetKind(val typeName: String, val defaultName: String, val defaultPrompt: String) {
    PRODUCT("Product", "Product", "Describe the main product with brand, name and function"),
    DISH("Dish", "Dish", "Describe the food layout on the plate using clock positions"),
    SHORT_TEXT("Short Text", "Short Text", "Read the visible text in the image"),
    CUSTOM("Custom", "Custom", "");

    companion object {
        fun fromTypeName(name: String): QuickPresetKind = entries.find { it.typeName == name } ?: CUSTOM
    }
}

class QuickRecognitionViewModel(application: Application) : AndroidViewModel(application) {
    private fun str(resId: Int): String = getApplication<Application>().getString(resId)
    private fun str(resId: Int, vararg args: Any?): String = getApplication<Application>().getString(resId, *args)

    val statusText = mutableStateOf(str(R.string.instructions_describe))
    val responseText = mutableStateOf("")
    val isProcessing = mutableStateOf(false)
    val isContinuousCapture = mutableStateOf(false)
    val capturedImage = mutableStateOf<Bitmap?>(null)
    val errorMessage = mutableStateOf<String?>(null)
    val apiKey = mutableStateOf("")

    val presets = mutableStateOf<List<QuickPresetConfig>>(emptyList())
    val captionLength = mutableStateOf<QuickCaptionLength>(QuickCaptionLength.SHORT)
    val captureInterval = mutableStateOf(QuickContinuousInterval._3S)

    private val container = (application as EyePalApplication).container
    val camera = container.cameraService
    private val moondream = container.moondreamService
    private val translationService = container.translationService
    private val glassService = container.glassService
    private val announcer = container.announcer
    private val settings = container.settingsRepository
    private var continuousJob: Job? = null
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

        apiKey.value = settings.quickMoondreamAPIKey.first()
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
        continuousJob = viewModelScope.launch {
            while (isContinuousCapture.value) { capture(); delay(captureInterval.value.value.toLong()) }
        }
    }

    fun stopContinuous() { continuousJob?.cancel(); continuousJob = null; isContinuousCapture.value = false; if (!isProcessing.value) statusText.value = str(R.string.status_ready) }

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
                val apiKey = settings.quickMoondreamAPIKey.first()
                if (apiKey.isEmpty()) { responseText.value = str(R.string.quick_no_api_key); isProcessing.value = false; return@launch }
                val result = moondream.describeImage(bitmap, apiKey, applyCaptionLength(lastPrompt))
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

    override fun onCleared() {
        super.onCleared()
        translationService.close()
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