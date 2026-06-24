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
        val DETAILS_MATCH_THRESHOLD = floatPreferencesKey("details_match_threshold")
        val FACE_MATCH_THRESHOLD = floatPreferencesKey("face_match_threshold")
        val FACE_MATCH_MARGIN = floatPreferencesKey("face_match_margin")
        val SUGGEST_UNKNOWN_FACES = booleanPreferencesKey("suggest_unknown_faces")
        val LYRIC_ADVANCE_OFFSET = doublePreferencesKey("lyric_advance_offset")
        val LYRIC_LLM_PROVIDER = stringPreferencesKey("lyric_llm_provider")
        val LYRIC_MODEL_ID = stringPreferencesKey("lyric_model_id")
        val LYRIC_API_KEY = stringPreferencesKey("lyric_api_key")
        val LYRIC_BASE_URL = stringPreferencesKey("lyric_base_url")
        val GOOGLE_GLASS_DEVICE_NAME = stringPreferencesKey("google_glass_device_name")
        val GOOGLE_GLASS_CONNECTED = booleanPreferencesKey("google_glass_connected")
    }

    val featureOrder: Flow<List<String>> = context.dataStore.data.map { prefs ->
        prefs[Keys.FEATURE_ORDER]?.split(",") ?: AppFeature.defaultOrder.map { it.name }
    }

    val quickMoondreamAPIKey: Flow<String> = context.dataStore.data.map { it[Keys.QUICK_MOONDREAM_API_KEY] ?: "" }
    val faceMatchThreshold: Flow<Float> = context.dataStore.data.map { it[Keys.FACE_MATCH_THRESHOLD] ?: 0.82f }
    val faceMatchMargin: Flow<Float> = context.dataStore.data.map { it[Keys.FACE_MATCH_MARGIN] ?: 0.015f }
    val suggestUnknownFaces: Flow<Boolean> = context.dataStore.data.map { it[Keys.SUGGEST_UNKNOWN_FACES] ?: true }
    val lyricAdvanceOffset: Flow<Double> = context.dataStore.data.map { it[Keys.LYRIC_ADVANCE_OFFSET] ?: 0.0 }
    val lyricLLMProvider: Flow<String> = context.dataStore.data.map { it[Keys.LYRIC_LLM_PROVIDER] ?: "CODEX" }
    val lyricModelID: Flow<String> = context.dataStore.data.map { it[Keys.LYRIC_MODEL_ID] ?: "gpt-5.4-mini" }
    val lyricAPIKey: Flow<String> = context.dataStore.data.map { it[Keys.LYRIC_API_KEY] ?: "" }
    val lyricBaseURL: Flow<String> = context.dataStore.data.map { it[Keys.LYRIC_BASE_URL] ?: "" }
    val googleGlassDeviceName: Flow<String> = context.dataStore.data.map { it[Keys.GOOGLE_GLASS_DEVICE_NAME] ?: "" }
    val googleGlassConnected: Flow<Boolean> = context.dataStore.data.map { it[Keys.GOOGLE_GLASS_CONNECTED] ?: false }

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

    suspend fun setLyricAdvanceOffset(value: Double) {
        context.dataStore.edit { it[Keys.LYRIC_ADVANCE_OFFSET] = value }
    }

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
