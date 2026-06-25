package com.eyepal.app.services

import android.content.Context
import com.eyepal.app.models.LyricSong
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File

object LyricStorage {
    private val json = Json { ignoreUnknownKeys = true; prettyPrint = true }

    fun getSongsFile(context: Context): File = File(context.filesDir, "lyrics.json")

    fun loadSongs(context: Context): List<LyricSong> {
        val file = getSongsFile(context)
        if (!file.exists()) return emptyList()
        return try {
            json.decodeFromString<List<LyricSong>>(file.readText())
        } catch (_: Exception) { emptyList() }
    }

    fun saveSongs(context: Context, songs: List<LyricSong>) {
        try {
            getSongsFile(context).writeText(json.encodeToString(songs))
        } catch (_: Exception) {}
    }

    fun addSong(context: Context, song: LyricSong) {
        val songs = loadSongs(context).toMutableList()
        songs.add(0, song)
        saveSongs(context, songs)
    }

    fun deleteSong(context: Context, songId: String) {
        val songs = loadSongs(context).toMutableList()
        songs.removeAll { it.id == songId }
        saveSongs(context, songs)
    }
}
