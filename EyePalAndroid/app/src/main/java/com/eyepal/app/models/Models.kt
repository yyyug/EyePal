package com.eyepal.app.models

import kotlinx.serialization.Serializable

@Serializable
data class FaceProfile(
    val id: String,
    val name: String,
    val sampleEmbeddings: List<List<Float>>,
    val sampleImagePath: String? = null,
    val createdAt: Long = System.currentTimeMillis()
)

@Serializable
data class LyricLine(
    val text: String,
    val startTime: Double? = null
)

@Serializable
data class LyricSong(
    val id: String,
    val title: String,
    val artist: String,
    val lines: List<LyricLine>,
    val hasTimestamps: Boolean,
    val createdAt: Long = System.currentTimeMillis()
)

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
    val displayName: String,
    val description: String,
    val tabTitle: String,
    val icon: String
) {
    FLOOR_DETECTION("Floor Detection", "Helps locate which floor you are on", "Floor", "architecture"),
    CHAT("Chat", "Real-time voice translation", "Chat", "mic"),
    FACES("Faces", "Face recognition and memory", "Faces", "person"),
    QUICK_RECOGNITION("Quick Recognition", "Snap a photo for instant scene description", "Quick", "camera_alt"),
    DETAILS_RECOGNITION("Details Recognition", "Detailed scene description with follow-up chat", "Details", "auto_awesome"),
    READ_TEXT("Read Text", "OCR text recognition in multiple languages", "Read Text", "text_fields"),
    LYRIC_PROMPTER("Lyric Prompter", "Search and listen to song lyrics", "Lyrics", "music_note");

    companion object {
        val defaultOrder = entries.toList()
    }
}
