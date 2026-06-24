package com.eyepal.app.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.eyepal.app.models.LyricSearchResult
import com.eyepal.app.models.LyricSong
import com.eyepal.app.viewmodels.LyricPrompterViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LyricPrompterScreen(viewModel: LyricPrompterViewModel = viewModel()) {
    val searchText by viewModel.searchText
    val searchResults by viewModel.searchResults
    val currentSong by viewModel.currentSong
    val isSearching by viewModel.isSearching

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        TopAppBar(title = { Text("Lyric Prompter") })

        when {
            currentSong != null -> {
                LyricDisplayContent(
                    song = currentSong!!,
                    onBack = { viewModel.currentSong.value = null },
                    onSave = { viewModel.saveCurrentSong() },
                    onPlayFromStart = { viewModel.playFromStart() },
                    onPlayFromNow = { viewModel.playFromNow() },
                    onStopPlayback = { viewModel.stopPlayback() },
                    isPlaying = viewModel.isPlaying.value
                )
            }
            searchResults.isNotEmpty() -> {
                ResultsList(
                    results = searchResults,
                    onSelect = { viewModel.loadSelectedResult(it) },
                    onDismiss = { viewModel.searchResults.value = emptyList() }
                )
            }
            else -> {
                OutlinedTextField(
                    value = searchText,
                    onValueChange = { viewModel.searchText.value = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Song title or \"Song - Artist\"") },
                    singleLine = true
                )
                Spacer(modifier = Modifier.height(12.dp))
                Button(
                    onClick = { viewModel.search() },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !isSearching && searchText.isNotBlank()
                ) {
                    Text(if (isSearching) "Searching..." else "Search Lyrics")
                }
            }
        }
    }
}

@Composable
private fun ResultsList(results: List<LyricSearchResult>, onSelect: (LyricSearchResult) -> Unit, onDismiss: () -> Unit) {
    Column {
        Text("${results.size} results found", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(bottom = 8.dp))
        TextButton(onClick = onDismiss) { Text("Cancel") }
        LazyColumn {
            items(results) { result ->
                ListItem(
                    headlineContent = { Text(result.trackName) },
                    supportingContent = {
                        Column {
                            Text(result.artistName, style = MaterialTheme.typography.bodySmall)
                            if (result.albumName != null) Text(result.albumName, style = MaterialTheme.typography.labelSmall)
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                if (result.hasSyncedLyrics) Text("Synced", color = MaterialTheme.colorScheme.primary)
                                else Text("Plain", color = MaterialTheme.colorScheme.outline)
                            }
                        }
                    },
                    trailingContent = { SuggestionChip(onClick = {}, label = { Text(result.source) }) },
                    modifier = Modifier.clickable { onSelect(result) }
                )
                HorizontalDivider()
            }
        }
    }
}

@Composable
private fun LyricDisplayContent(song: LyricSong, onBack: () -> Unit, onSave: () -> Unit, onPlayFromStart: () -> Unit, onPlayFromNow: () -> Unit, onStopPlayback: () -> Unit, isPlaying: Boolean) {
    Column(modifier = Modifier.fillMaxSize()) {
        IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") }

        if (song.hasTimestamps) {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = { if (isPlaying) onStopPlayback() else onPlayFromStart() }, modifier = Modifier.weight(1f)) {
                    Text(if (isPlaying) "Stop" else "Play from Start")
                }
                Button(onClick = { if (isPlaying) onStopPlayback() else onPlayFromNow() }, modifier = Modifier.weight(1f)) {
                    Text(if (isPlaying) "Stop" else "Play from Now")
                }
            }
            Spacer(modifier = Modifier.height(8.dp))
        } else {
            Text("No timed lyrics available", style = MaterialTheme.typography.caption, color = MaterialTheme.colorScheme.outline, modifier = Modifier.padding(vertical = 4.dp))
        }

        LazyColumn(modifier = Modifier.weight(1f)) {
            items(song.lines) { line ->
                Text(line.text, modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
            }
        }

        Button(onClick = onSave, modifier = Modifier.fillMaxWidth()) { Text("Save Lyrics") }
    }
}
