package com.eyepal.app.viewmodels

import android.app.Application
import android.media.AudioManager
import android.speech.tts.TextToSpeech
import androidx.compose.runtime.mutableStateOf
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.eyepal.app.data.SettingsRepository
import com.eyepal.app.models.*
import com.eyepal.app.services.LyricPrompterService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.Locale

class LyricPrompterViewModel(application: Application) : AndroidViewModel(application) {
    val searchText = mutableStateOf("")
    val searchResults = mutableStateOf<List<LyricSearchResult>>(emptyList())
    val currentSong = mutableStateOf<LyricSong?>(null)
    val isSearching = mutableStateOf(false)
    val isLoadingLyrics = mutableStateOf(false)
    val isPlaying = mutableStateOf(false)
    val errorMessage = mutableStateOf<String?>(null)
    val savedSongs = mutableStateOf<List<LyricSong>>(emptyList())

    private val service = LyricPrompterService()
    private val settings = SettingsRepository(application)
    private var playbackJob: Job? = null
    private var tts: TextToSpeech? = null

    init {
        tts = TextToSpeech(application) { status ->
            if (status == TextToSpeech.SUCCESS) {
                tts?.language = Locale.US
            }
        }
    }

    fun search() {
        val input = searchText.value.trim()
        if (input.isEmpty()) return
        isSearching.value = true
        viewModelScope.launch {
            try {
                val results = service.searchAllSources(input)
                if (results.isEmpty()) {
                    errorMessage.value = "No lyrics found."
                } else {
                    searchResults.value = results
                }
            } catch (e: Exception) {
                errorMessage.value = e.message
            }
            isSearching.value = false
        }
    }

    fun loadSelectedResult(result: LyricSearchResult) {
        isLoadingLyrics.value = true
        currentSong.value = service.loadLyrics(result)
        searchResults.value = emptyList()
        isLoadingLyrics.value = false
    }

    fun saveCurrentSong() {
        val song = currentSong.value ?: return
        savedSongs.value = savedSongs.value + song
    }

    fun playFromStart() {
        val song = currentSong.value ?: return
        if (!song.hasTimestamps) return
        stopPlayback()
        isPlaying.value = true
        playbackJob = viewModelScope.launch {
            val linesWithTime = song.lines.filter { it.startTime != null }
            val advanceOffset = settings.lyricAdvanceOffset.first()
            val firstTime = linesWithTime.firstOrNull()?.startTime ?: return@launch
            delay(((firstTime - advanceOffset).coerceAtLeast(0.0) * 1000).toLong())
            for (line in linesWithTime) {
                if (!isPlaying.value) break
                speak(line.text)
                val nextTime = linesWithTime.dropWhile { it.startTime!! <= line.startTime!! }.firstOrNull()?.startTime
                if (nextTime != null) {
                    delay(((nextTime - line.startTime!! - advanceOffset).coerceAtLeast(0.0) * 1000).toLong())
                }
            }
            isPlaying.value = false
        }
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
            speak(linesWithTime[0].text)
            for (i in 1 until linesWithTime.size) {
                if (!isPlaying.value) break
                val prev = linesWithTime[i - 1]
                val curr = linesWithTime[i]
                val delayMs = ((curr.startTime!! - prev.startTime!! - advanceOffset).coerceAtLeast(0.0) * 1000).toLong()
                delay(delayMs)
                speak(curr.text)
            }
            isPlaying.value = false
        }
    }

    fun stopPlayback() {
        playbackJob?.cancel()
        playbackJob = null
        isPlaying.value = false
        tts?.stop()
    }

    private fun speak(text: String) {
        tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "lyric_${System.currentTimeMillis()}")
    }

    override fun onCleared() {
        super.onCleared()
        tts?.stop()
        tts?.shutdown()
    }
}
