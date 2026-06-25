package com.eyepal.app.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.*
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "settings")

class SettingsRepository(private val context: Context) {

    private object Keys {
        val FEATURE_ORDER = stringPreferencesKey("feature_order")
        val QUICK_MOONDREAM_API_KEY = stringPreferencesKey("quick_moondream_api_key")
        val QUICK_CAPTION_LENGTH = stringPreferencesKey("quick_caption_length")
        val QUICK_CONTINUOUS_INTERVAL = intPreferencesKey("quick_continuous_interval")
        val QUICK_ACTION_CONTROL_STYLE = stringPreferencesKey("quick_action_control_style")
        val FACE_MATCH_THRESHOLD = floatPreferencesKey("face_match_threshold")
        val FACE_MATCH_MARGIN = floatPreferencesKey("face_match_margin")
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
        val MAPS_MAX_DISTANCE = floatPreferencesKey("maps_max_distance")
        val MAPS_REVERB_BLEND = floatPreferencesKey("maps_reverb_blend")
        val MAPS_HEAD_TRACKING = booleanPreferencesKey("maps_head_tracking")
        val MAPS_AUTO_CALLOUTS = booleanPreferencesKey("maps_auto_callouts")
        val MAPS_BEACON_STYLE = stringPreferencesKey("maps_beacon_style")
        val MAPS_BEACON_VOLUME = floatPreferencesKey("maps_beacon_volume")
        val MAPS_OTHER_VOLUME = floatPreferencesKey("maps_other_volume")
        val MAPS_METRIC_UNITS = booleanPreferencesKey("maps_metric_units")
        val MAPS_MIX_AUDIO = booleanPreferencesKey("maps_mix_audio")
        val MAPS_BACKGROUND_AUDIO = booleanPreferencesKey("maps_background_audio")
    }

    val featureOrder: Flow<List<String>> = context.dataStore.data.map { it[Keys.FEATURE_ORDER]?.split(",") ?: AppFeature.defaultOrder.map { it.name } }
    val quickMoondreamAPIKey: Flow<String> = context.dataStore.data.map { it[Keys.QUICK_MOONDREAM_API_KEY] ?: "" }
    val faceMatchThreshold: Flow<Float> = context.dataStore.data.map { it[Keys.FACE_MATCH_THRESHOLD] ?: 0.82f }
    val faceMatchMargin: Flow<Float> = context.dataStore.data.map { it[Keys.FACE_MATCH_MARGIN] ?: 0.015f }
    val faceSpeechCooldown: Flow<Float> = context.dataStore.data.map { it[Keys.FACE_SPEECH_COOLDOWN] ?: 2.5f }
    val readTextSpeechCooldown: Flow<Float> = context.dataStore.data.map { it[Keys.READ_TEXT_SPEECH_COOLDOWN] ?: 2.5f }
    val suggestUnknownFaces: Flow<Boolean> = context.dataStore.data.map { it[Keys.SUGGEST_UNKNOWN_FACES] ?: true }
    val lyricAdvanceOffset: Flow<Float> = context.dataStore.data.map { it[Keys.LYRIC_ADVANCE_OFFSET] ?: 0f }
    val lyricLLMProvider: Flow<String> = context.dataStore.data.map { it[Keys.LYRIC_LLM_PROVIDER] ?: "CODEX" }
    val lyricModelID: Flow<String> = context.dataStore.data.map { it[Keys.LYRIC_MODEL_ID] ?: "gpt-5.4-mini" }
    val lyricAPIKey: Flow<String> = context.dataStore.data.map { it[Keys.LYRIC_API_KEY] ?: "" }
    val lyricBaseURL: Flow<String> = context.dataStore.data.map { it[Keys.LYRIC_BASE_URL] ?: "" }
    val mapsMaxDistance: Flow<Float> = context.dataStore.data.map { it[Keys.MAPS_MAX_DISTANCE] ?: 500f }
    val mapsReverbBlend: Flow<Float> = context.dataStore.data.map { it[Keys.MAPS_REVERB_BLEND] ?: 0.15f }
    val mapsHeadTracking: Flow<Boolean> = context.dataStore.data.map { it[Keys.MAPS_HEAD_TRACKING] ?: true }
    val mapsAutoCallouts: Flow<Boolean> = context.dataStore.data.map { it[Keys.MAPS_AUTO_CALLOUTS] ?: true }
    val mapsBeaconStyle: Flow<String> = context.dataStore.data.map { it[Keys.MAPS_BEACON_STYLE] ?: "current" }
    val mapsBeaconVolume: Flow<Float> = context.dataStore.data.map { it[Keys.MAPS_BEACON_VOLUME] ?: 0.75f }
    val mapsOtherVolume: Flow<Float> = context.dataStore.data.map { it[Keys.MAPS_OTHER_VOLUME] ?: 0.75f }
    val mapsMetricUnits: Flow<Boolean> = context.dataStore.data.map { it[Keys.MAPS_METRIC_UNITS] ?: true }
    val mapsMixAudio: Flow<Boolean> = context.dataStore.data.map { it[Keys.MAPS_MIX_AUDIO] ?: true }
    val mapsBackgroundAudio: Flow<Boolean> = context.dataStore.data.map { it[Keys.MAPS_BACKGROUND_AUDIO] ?: true }

    suspend fun setFeatureOrder(order: List<String>) {
        context.dataStore.edit { it[Keys.FEATURE_ORDER] = order.joinToString(",") }
    }

    suspend fun setQuickMoondreamAPIKey(key: String) {
        context.dataStore.edit { it[Keys.QUICK_MOONDREAM_API_KEY] = key }
    }

    suspend fun setFaceMatchThreshold(value: Float) {
        context.dataStore.edit { it[Keys.FACE_MATCH_THRESHOLD] = value }
    }

    suspend fun setFaceMatchMargin(value: Float) {
        context.dataStore.edit { it[Keys.FACE_MATCH_MARGIN] = value }
    }

    suspend fun setSuggestUnknownFaces(value: Boolean) {
        context.dataStore.edit { it[Keys.SUGGEST_UNKNOWN_FACES] = value }
    }

    suspend fun setLyricAdvanceOffset(value: Float) {
        context.dataStore.edit { it[Keys.LYRIC_ADVANCE_OFFSET] = value }
    }

    suspend fun setMapsMaxDistance(value: Float) { context.dataStore.edit { it[Keys.MAPS_MAX_DISTANCE] = value } }
    suspend fun setMapsReverbBlend(value: Float) { context.dataStore.edit { it[Keys.MAPS_REVERB_BLEND] = value } }
    suspend fun setMapsHeadTracking(value: Boolean) { context.dataStore.edit { it[Keys.MAPS_HEAD_TRACKING] = value } }
    suspend fun setMapsAutoCallouts(value: Boolean) { context.dataStore.edit { it[Keys.MAPS_AUTO_CALLOUTS] = value } }
    suspend fun setMapsBeaconStyle(value: String) { context.dataStore.edit { it[Keys.MAPS_BEACON_STYLE] = value } }
    suspend fun setMapsBeaconVolume(value: Float) { context.dataStore.edit { it[Keys.MAPS_BEACON_VOLUME] = value } }
    suspend fun setMapsOtherVolume(value: Float) { context.dataStore.edit { it[Keys.MAPS_OTHER_VOLUME] = value } }
    suspend fun setMapsMetricUnits(value: Boolean) { context.dataStore.edit { it[Keys.MAPS_METRIC_UNITS] = value } }
    suspend fun setMapsMixAudio(value: Boolean) { context.dataStore.edit { it[Keys.MAPS_MIX_AUDIO] = value } }
    suspend fun setMapsBackgroundAudio(value: Boolean) { context.dataStore.edit { it[Keys.MAPS_BACKGROUND_AUDIO] = value } }

    suspend fun setLyricLLMProvider(value: String) {
        context.dataStore.edit { it[Keys.LYRIC_LLM_PROVIDER] = value }
    }

    suspend fun setLyricModelID(value: String) {
        context.dataStore.edit { it[Keys.LYRIC_MODEL_ID] = value }
    }

    suspend fun setLyricAPIKey(value: String) {
        context.dataStore.edit { it[Keys.LYRIC_API_KEY] = value }
    }

    suspend fun setLyricBaseURL(value: String) {
        context.dataStore.edit { it[Keys.LYRIC_BASE_URL] = value }
    }

    suspend fun setGoogleGlassDeviceName(name: String) {
        context.dataStore.edit { it[Keys.GOOGLE_GLASS_DEVICE_NAME] = name }
    }

    suspend fun setGoogleGlassConnected(connected: Boolean) {
        context.dataStore.edit { it[Keys.GOOGLE_GLASS_CONNECTED] = connected }
    }
}

import com.eyepal.app.models.AppFeature
