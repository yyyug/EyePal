package com.eyepal.app.viewmodels

import android.app.Application
import androidx.compose.runtime.mutableStateOf
import androidx.lifecycle.AndroidViewModel
import kotlinx.coroutines.flow.first
import androidx.lifecycle.viewModelScope
import com.eyepal.app.data.SettingsRepository
import com.eyepal.app.models.LyricSong
import com.eyepal.app.services.AccessibilityAnnouncer
import com.eyepal.app.services.LyricPrompterService
import com.eyepal.app.services.LyricStorage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class LyricPrompterViewModel(application: Application) : AndroidViewModel(application) {
    val searchText = mutableStateOf("")
    val searchResults = mutableStateOf<List<com.eyepal.app.models.LyricSearchResult>>(emptyList())
    val currentSong = mutableStateOf<LyricSong?>(null)
    val isSearching = mutableStateOf(false)
    val isLoadingLyrics = mutableStateOf(false)
    val isPlaying = mutableStateOf(false)
    val currentLineIndex = mutableStateOf(-1)
    val errorMessage = mutableStateOf<String?>(null)
    val savedSongs = mutableStateOf<List<LyricSong>>(emptyList())

    private val service = LyricPrompterService(context = application)
    private val settings = SettingsRepository(application)
    private val announcer = AccessibilityAnnouncer(application)
    private var playbackJob: Job? = null

    init {
        savedSongs.value = LyricStorage.loadSongs(application)
    }

    fun search() {
        val input = searchText.value.trim()
        if (input.isEmpty()) return
        isSearching.value = true
        viewModelScope.launch(Dispatchers.IO) {
            try {
                val results = service.searchAllSources(input)
                if (results.isEmpty()) { errorMessage.value = "No lyrics found." }
                else { searchResults.value = results }
            } catch (e: Exception) { errorMessage.value = e.message }
            isSearching.value = false
        }
    }

    fun loadSelectedResult(result: com.eyepal.app.models.LyricSearchResult) {
        isLoadingLyrics.value = true
        currentSong.value = service.loadLyrics(result)
        isLoadingLyrics.value = false
    }

    fun loadSavedSong(song: LyricSong) {
        currentSong.value = song
    }

    fun loadSavedSongs() {
        savedSongs.value = LyricStorage.loadSongs(getApplication())
    }

    fun saveCurrentSong() {
        val song = currentSong.value ?: return
        val savedSong = song.copy(id = System.currentTimeMillis().toString())
        savedSongs.value = listOf(savedSong) + savedSongs.value
        LyricStorage.addSong(getApplication(), savedSong)
        announcer.announce("${song.title} by ${song.artist} saved.")
    }

    fun deleteSong(songId: String) {
        savedSongs.value = savedSongs.value.filter { it.id != songId }
        LyricStorage.deleteSong(getApplication(), songId)
    }

    fun playFromStart() {
        val song = currentSong.value ?: return
        if (!song.hasTimestamps) return
        playFromLine(0)
    }

    fun playFromNow() {
        val song = currentSong.value ?: return
        if (!song.hasTimestamps) return
        stopPlayback()
        isPlaying.value = true
        playbackJob = viewModelScope.launch {
            val linesWithTime = song.lines.filter { it.startTime != null }
            val advanceOffset = settings.lyricAdvanceOffset.first()
            if (linesWithTime.isEmpty()) { isPlaying.value = false; return@launch }
            currentLineIndex.value = song.lines.indexOf(linesWithTime[0])
            announcer.announce(linesWithTime[0].text)
            for (i in 1 until linesWithTime.size) {
                if (!isPlaying.value) break
                val prev = linesWithTime[i - 1]
                val curr = linesWithTime[i]
                delay(((curr.startTime!! - prev.startTime!! - advanceOffset).coerceAtLeast(0.0) * 1000).toLong())
                currentLineIndex.value = song.lines.indexOf(curr)
                announcer.announce(curr.text)
            }
            currentLineIndex.value = -1
            isPlaying.value = false
        }
    }

    fun playFromLine(index: Int) {
        val song = currentSong.value ?: return
        if (!song.hasTimestamps) return
        stopPlayback()
        isPlaying.value = true
        playbackJob = viewModelScope.launch {
            val linesWithTime = song.lines.filter { it.startTime != null }
            val advanceOffset = settings.lyricAdvanceOffset.first()
            if (linesWithTime.isEmpty()) { isPlaying.value = false; return@launch }

            // Find the timed line closest to or at the given index
            val targetLine = linesWithTime.firstOrNull { song.lines.indexOf(it) >= index }
                ?: linesWithTime.lastOrNull()
                ?: return@launch
            val startIndex = linesWithTime.indexOf(targetLine)

            currentLineIndex.value = song.lines.indexOf(targetLine)
            announcer.announce(targetLine.text)

            for (i in (startIndex + 1) until linesWithTime.size) {
                if (!isPlaying.value) break
                val prev = linesWithTime[i - 1]
                val curr = linesWithTime[i]
                delay(((curr.startTime!! - prev.startTime!! - advanceOffset).coerceAtLeast(0.0) * 1000).toLong())
                currentLineIndex.value = song.lines.indexOf(curr)
                announcer.announce(curr.text)
            }
            currentLineIndex.value = -1
            isPlaying.value = false
        }
    }

    fun stopPlayback() {
        playbackJob?.cancel()
        playbackJob = null
        isPlaying.value = false
        currentLineIndex.value = -1
    }
}
