package com.eyepal.app.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.*
import androidx.datastore.preferences.preferencesDataStore
import com.eyepal.app.config.Defaults
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "settings")

class SettingsRepository(private val context: Context) {
    private object Keys {
        val FEATURE_ORDER = stringPreferencesKey("feature_order")
        val QUICK_MOONDREAM_API_KEY = stringPreferencesKey("quick_moondream_api_key")
        val QUICK_CAPTION_LENGTH = stringPreferencesKey("quick_caption_length")
        val QUICK_CONTINUOUS_INTERVAL = intPreferencesKey("quick_continuous_interval")
        val QUICK_TRANSLATION_ENABLED = booleanPreferencesKey("quick_translation_enabled")
        val QUICK_TRANSLATION_TARGET = stringPreferencesKey("quick_translation_target")
        val QUICK_PRESETS = stringPreferencesKey("quick_presets")
        val FACE_MATCH_THRESHOLD = floatPreferencesKey("face_match_threshold")
        val FACE_MATCH_MARGIN = floatPreferencesKey("face_match_margin")
        val FACE_MATCH_FRAME_THRESHOLD = intPreferencesKey("face_match_frame_threshold")
        val FACE_SPEECH_COOLDOWN = floatPreferencesKey("face_speech_cooldown")
        val READ_TEXT_SPEECH_COOLDOWN = floatPreferencesKey("read_text_speech_cooldown")
        val SUGGEST_UNKNOWN_FACES = booleanPreferencesKey("suggest_unknown_faces")
        val LYRIC_ADVANCE_OFFSET = floatPreferencesKey("lyric_advance_offset")
        val LYRIC_LLM_PROVIDER = stringPreferencesKey("lyric_llm_provider")
        val LYRIC_MODEL_ID = stringPreferencesKey("lyric_model_id")
        val LYRIC_API_KEY = stringPreferencesKey("lyric_api_key")
        val LYRIC_BASE_URL = stringPreferencesKey("lyric_base_url")
        val GOOGLE_GLASS_DEVICE_NAME = stringPreferencesKey("google_glass_device_name")
        val GOOGLE_GLASS_CONNECTED = booleanPreferencesKey("google_glass_connected")
        val CHAT_INTERPRETER_LANG_A = stringPreferencesKey("chat_interpreter_lang_a")
        val CHAT_INTERPRETER_LANG_B = stringPreferencesKey("chat_interpreter_lang_b")
        val DETAIL_BUTTONS = stringPreferencesKey("detail_buttons")
        val QUICK_ACTION_CONTROL_STYLE = stringPreferencesKey("quick_action_control_style")
        val DETAILS_ACTION_CONTROL_STYLE = stringPreferencesKey("details_action_control_style")
    }

    val featureOrder: Flow<List<String>> = context.dataStore.data.map { it[Keys.FEATURE_ORDER]?.split(",") ?: Defaults.FEATURE_ORDER }
    val quickMoondreamAPIKey: Flow<String> = context.dataStore.data.map { it[Keys.QUICK_MOONDREAM_API_KEY] ?: "" }
    val quickCaptionLength: Flow<String> = context.dataStore.data.map { it[Keys.QUICK_CAPTION_LENGTH] ?: Defaults.CAPTION_LENGTH }
    val quickContinuousInterval: Flow<Int> = context.dataStore.data.map { it[Keys.QUICK_CONTINUOUS_INTERVAL] ?: Defaults.CONTINUOUS_INTERVAL_MS }
    val quickTranslationEnabled: Flow<Boolean> = context.dataStore.data.map { it[Keys.QUICK_TRANSLATION_ENABLED] ?: false }
    val quickTranslationTarget: Flow<String> = context.dataStore.data.map { it[Keys.QUICK_TRANSLATION_TARGET] ?: Defaults.TRANSLATION_TARGET }
    val quickPresets: Flow<String> = context.dataStore.data.map { it[Keys.QUICK_PRESETS] ?: "" }
    val faceMatchThreshold: Flow<Float> = context.dataStore.data.map { it[Keys.FACE_MATCH_THRESHOLD] ?: Defaults.FACE_MATCH_THRESHOLD }
    val faceMatchMargin: Flow<Float> = context.dataStore.data.map { it[Keys.FACE_MATCH_MARGIN] ?: Defaults.FACE_MATCH_MARGIN }
    val faceMatchFrameThreshold: Flow<Int> = context.dataStore.data.map { it[Keys.FACE_MATCH_FRAME_THRESHOLD] ?: Defaults.FACE_MATCH_FRAME_THRESHOLD }
    val faceSpeechCooldown: Flow<Float> = context.dataStore.data.map { it[Keys.FACE_SPEECH_COOLDOWN] ?: Defaults.FACE_SPEECH_COOLDOWN }
    val readTextSpeechCooldown: Flow<Float> = context.dataStore.data.map { it[Keys.READ_TEXT_SPEECH_COOLDOWN] ?: Defaults.READ_TEXT_SPEECH_COOLDOWN }
    val suggestUnknownFaces: Flow<Boolean> = context.dataStore.data.map { it[Keys.SUGGEST_UNKNOWN_FACES] ?: Defaults.SUGGEST_UNKNOWN_FACES }
    val detailButtons: Flow<String> = context.dataStore.data.map { it[Keys.DETAIL_BUTTONS] ?: "" }
    val quickActionControlStyle: Flow<String> = context.dataStore.data.map { it[Keys.QUICK_ACTION_CONTROL_STYLE] ?: Defaults.QUICK_ACTION_CONTROL_STYLE }
    val detailsActionControlStyle: Flow<String> = context.dataStore.data.map { it[Keys.DETAILS_ACTION_CONTROL_STYLE] ?: Defaults.DETAILS_ACTION_CONTROL_STYLE }
    val lyricAdvanceOffset: Flow<Float> = context.dataStore.data.map { it[Keys.LYRIC_ADVANCE_OFFSET] ?: Defaults.LYRIC_ADVANCE_OFFSET }
    val lyricLLMProvider: Flow<String> = context.dataStore.data.map { it[Keys.LYRIC_LLM_PROVIDER] ?: Defaults.LYRIC_LLM_PROVIDER }
    val lyricModelID: Flow<String> = context.dataStore.data.map { it[Keys.LYRIC_MODEL_ID] ?: Defaults.MODEL_ID }
    val lyricAPIKey: Flow<String> = context.dataStore.data.map { it[Keys.LYRIC_API_KEY] ?: "" }
    val lyricBaseURL: Flow<String> = context.dataStore.data.map { it[Keys.LYRIC_BASE_URL] ?: "" }

    suspend fun setFeatureOrder(order: List<String>) { context.dataStore.edit { it[Keys.FEATURE_ORDER] = order.joinToString(",") } }
    suspend fun setQuickMoondreamAPIKey(key: String) { context.dataStore.edit { it[Keys.QUICK_MOONDREAM_API_KEY] = key } }
    suspend fun setQuickCaptionLength(value: String) { context.dataStore.edit { it[Keys.QUICK_CAPTION_LENGTH] = value } }
    suspend fun setQuickContinuousInterval(value: Int) { context.dataStore.edit { it[Keys.QUICK_CONTINUOUS_INTERVAL] = value } }
    suspend fun setQuickTranslationEnabled(value: Boolean) { context.dataStore.edit { it[Keys.QUICK_TRANSLATION_ENABLED] = value } }
    suspend fun setQuickTranslationTarget(value: String) { context.dataStore.edit { it[Keys.QUICK_TRANSLATION_TARGET] = value } }
    suspend fun setQuickPresets(value: String) { context.dataStore.edit { it[Keys.QUICK_PRESETS] = value } }
    suspend fun setFaceMatchThreshold(value: Float) { context.dataStore.edit { it[Keys.FACE_MATCH_THRESHOLD] = value } }
    suspend fun setFaceMatchMargin(value: Float) { context.dataStore.edit { it[Keys.FACE_MATCH_MARGIN] = value } }
    suspend fun setFaceMatchFrameThreshold(value: Int) { context.dataStore.edit { it[Keys.FACE_MATCH_FRAME_THRESHOLD] = value } }
    suspend fun setFaceSpeechCooldown(value: Float) { context.dataStore.edit { it[Keys.FACE_SPEECH_COOLDOWN] = value } }
    suspend fun setReadTextSpeechCooldown(value: Float) { context.dataStore.edit { it[Keys.READ_TEXT_SPEECH_COOLDOWN] = value } }
    suspend fun setSuggestUnknownFaces(value: Boolean) { context.dataStore.edit { it[Keys.SUGGEST_UNKNOWN_FACES] = value } }
    suspend fun setLyricAdvanceOffset(value: Float) { context.dataStore.edit { it[Keys.LYRIC_ADVANCE_OFFSET] = value } }
    suspend fun setLyricLLMProvider(value: String) { context.dataStore.edit { it[Keys.LYRIC_LLM_PROVIDER] = value } }
    suspend fun setLyricModelID(value: String) { context.dataStore.edit { it[Keys.LYRIC_MODEL_ID] = value } }
    suspend fun setLyricAPIKey(value: String) { context.dataStore.edit { it[Keys.LYRIC_API_KEY] = value } }
    suspend fun setLyricBaseURL(value: String) { context.dataStore.edit { it[Keys.LYRIC_BASE_URL] = value } }
    suspend fun setDetailButtons(value: String) { context.dataStore.edit { it[Keys.DETAIL_BUTTONS] = value } }
    suspend fun setQuickActionControlStyle(value: String) { context.dataStore.edit { it[Keys.QUICK_ACTION_CONTROL_STYLE] = value } }
    suspend fun setDetailsActionControlStyle(value: String) { context.dataStore.edit { it[Keys.DETAILS_ACTION_CONTROL_STYLE] = value } }
    val chatInterpreterLangA: Flow<String> = context.dataStore.data.map { it[Keys.CHAT_INTERPRETER_LANG_A] ?: Defaults.CHAT_INTERPRETER_LANG_A }
    val chatInterpreterLangB: Flow<String> = context.dataStore.data.map { it[Keys.CHAT_INTERPRETER_LANG_B] ?: Defaults.CHAT_INTERPRETER_LANG_B }

    suspend fun setChatInterpreterLangA(value: String) { context.dataStore.edit { it[Keys.CHAT_INTERPRETER_LANG_A] = value } }
    suspend fun setChatInterpreterLangB(value: String) { context.dataStore.edit { it[Keys.CHAT_INTERPRETER_LANG_B] = value } }

    suspend fun setGoogleGlassDeviceName(name: String) { context.dataStore.edit { it[Keys.GOOGLE_GLASS_DEVICE_NAME] = name } }
    suspend fun setGoogleGlassConnected(connected: Boolean) { context.dataStore.edit { it[Keys.GOOGLE_GLASS_CONNECTED] = connected } }
}
