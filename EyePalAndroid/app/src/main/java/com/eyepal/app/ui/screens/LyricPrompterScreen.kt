package com.eyepal.app.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.eyepal.app.models.LyricSearchResult
import com.eyepal.app.viewmodels.LyricPrompterViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LyricPrompterScreen(viewModel: LyricPrompterViewModel = viewModel()) {
    val searchText by viewModel.searchText
    val searchResults by viewModel.searchResults
    val currentSong by viewModel.currentSong
    val isSearching by viewModel.isSearching
    val isLoading by viewModel.isLoadingLyrics

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        TopAppBar(title = { Text("Lyric Prompter") })

        if (currentSong != null) {
            LyricDisplayContent(
                song = currentSong!!,
                onBack = { viewModel.currentSong.value = null },
                onSave = { viewModel.saveCurrentSong() },
                onPlayFromStart = { viewModel.playFromStart() },
                onPlayFromNow = { viewModel.playFromNow() },
                onStopPlayback = { viewModel.stopPlayback() },
                isPlaying = viewModel.isPlaying.value
            )
        } else if (searchResults.isNotEmpty()) {
            ResultsList(
                results = searchResults,
                onSelect = { viewModel.loadSelectedResult(it) },
                onDismiss = { viewModel.searchResults.value = emptyList() }
            )
        } else {
            Column {
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
private fun ResultsList(
    results: List<LyricSearchResult>,
    onSelect: (LyricSearchResult) -> Unit,
    onDismiss: () -> Unit
) {
    Column {
        TopAppBar(
            title = { Text("${results.size} results found") },
            navigationIcon = {
                IconButton(onClick = onDismiss) { Text("Cancel") }
            }
        )
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
                    trailingContent = {
                        SuggestionChip(onClick = {}, label = { Text(result.source) })
                    },
                    modifier = Modifier.clickable { onSelect(result) }
                )
                HorizontalDivider()
            }
        }
    }
}

@Composable
private fun LyricDisplayContent(
    song: com.eyepal.app.models.LyricSong,
    onBack: () -> Unit,
    onSave: () -> Unit,
    onPlayFromStart: () -> Unit,
    onPlayFromNow: () -> Unit,
    onStopPlayback: () -> Unit,
    isPlaying: Boolean
) {
    Column(modifier = Modifier.fillMaxSize()) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            TextButton(onClick = onBack) { Text("Back") }
        }

        if (song.hasTimestamps) {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(
                    onClick = { if (isPlaying) onStopPlayback() else onPlayFromStart() },
                    modifier = Modifier.weight(1f)
                ) {
                    Text(if (isPlaying) "Stop" else "Play from Start")
                }
                Button(
                    onClick = { if (isPlaying) onStopPlayback() else onPlayFromNow() },
                    modifier = Modifier.weight(1f)
                ) {
                    Text(if (isPlaying) "Stop" else "Play from Now")
                }
            }
        }

        LazyColumn(modifier = Modifier.weight(1f)) {
            items(song.lines) { line ->
                Text(line.text, modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
            }
        }

        Button(onClick = onSave, modifier = Modifier.fillMaxWidth()) {
            Text("Save Lyrics")
        }
    }
}
