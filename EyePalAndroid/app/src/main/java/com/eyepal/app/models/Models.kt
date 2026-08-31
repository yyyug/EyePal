package com.eyepal.app.models

import android.content.Context
import androidx.annotation.StringRes
import androidx.compose.runtime.Stable
import com.eyepal.app.R
import kotlinx.serialization.Serializable

@Serializable
data class FaceProfile(
    val id: String,
    val name: String,
    val sampleEmbeddings: List<List<Float>>,
    val sampleImagePath: String? = null,
    val createdAt: Long = System.currentTimeMillis()
)

    @Stable
    @Serializable
    data class LyricLine(
        @Stable val text: String,
        @Stable val startTime: Double? = null
    )

    @Stable
    @Serializable
    data class LyricSong(
        @Stable val id: String,
        @Stable val title: String,
        @Stable val artist: String,
        @Stable val lines: List<LyricLine>,
        @Stable val hasTimestamps: Boolean,
        @Stable val createdAt: Long = System.currentTimeMillis()
    )

    @Stable
    data class LyricSearchResult(
    val source: String,
    val trackName: String,
    val artistName: String,
    val albumName: String? = null,
    val hasSyncedLyrics: Boolean,
    val syncedLyrics: String? = null,
    val plainLyrics: String? = null
)

enum class LyricLLMProvider { CODEX, GEMINI, OPENAI }

data class LyricLLMResponse(
    val title: String,
    val artist: String,
    val hasTimestamps: Boolean,
    val lines: List<LyricLine>
)

enum class AppFeature(
    @StringRes val displayNameRes: Int,
    @StringRes val descriptionRes: Int,
    @StringRes val tabTitleRes: Int,
    val icon: String
) {
    QUICK_RECOGNITION(R.string.feature_quick_recognition, R.string.feature_desc_quick, R.string.tab_quick, "camera_alt"),
    DETAILS_RECOGNITION(R.string.feature_details_recognition, R.string.feature_desc_details, R.string.tab_details, "auto_awesome"),
    READ_TEXT(R.string.feature_read_text, R.string.feature_desc_read_text, R.string.tab_read_text, "text_fields"),
    FLOOR_DETECTION(R.string.feature_floor_detection, R.string.feature_desc_floor, R.string.tab_floor, "architecture"),
    LYRIC_PROMPTER(R.string.feature_lyric_prompter, R.string.feature_desc_lyrics, R.string.tab_lyrics, "music_note"),
    CHAT(R.string.feature_chat, R.string.feature_desc_chat, R.string.tab_chat, "mic"),
    FACES(R.string.tab_faces, R.string.feature_desc_faces, R.string.tab_faces, "person");

    fun getDisplayName(context: Context): String = context.getString(displayNameRes)
    fun getDescription(context: Context): String = context.getString(descriptionRes)
    fun getTabTitle(context: Context): String = context.getString(tabTitleRes)

    companion object {
        val defaultOrder = entries.toList()

        fun getDisplayNameByName(context: Context, name: String): String {
            val feature = entries.find { it.name == name }
            return feature?.getDisplayName(context) ?: name
        }
    }
}