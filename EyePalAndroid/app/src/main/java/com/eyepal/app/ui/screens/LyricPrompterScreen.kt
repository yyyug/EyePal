package com.eyepal.app.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.eyepal.app.R
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
    val savedSongs by viewModel.savedSongs

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        TopAppBar(title = { Text(stringResource(R.string.feature_lyric_prompter)) })

        when {
            currentSong != null -> {
                LyricDisplayContent(
                    song = currentSong!!,
                    currentLineIndex = viewModel.currentLineIndex.value,
                    onBack = { viewModel.currentSong.value = null },
                    onSave = { viewModel.saveCurrentSong() },
                    onPlayFromStart = { viewModel.playFromStart() },
                    onPlayFromNow = { viewModel.playFromNow() },
                    onStopPlayback = { viewModel.stopPlayback() },
                    onPlayFromLine = { viewModel.playFromLine(it) },
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
                if (savedSongs.isNotEmpty()) {
                    Text(stringResource(R.string.label_saved_songs), style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(bottom = 8.dp))
                    LazyColumn(modifier = Modifier.weight(1f)) {
                        items(savedSongs, key = { it.id }) { song ->
                            ListItem(
                                headlineContent = { Text(song.title) },
                                supportingContent = { Text(song.artist, style = MaterialTheme.typography.bodySmall) },
                                trailingContent = {
                                    IconButton(onClick = { viewModel.deleteSong(song.id) }) {
                                        Icon(Icons.Filled.Delete, contentDescription = stringResource(R.string.btn_delete), tint = MaterialTheme.colorScheme.error)
                                    }
                                },
                                modifier = Modifier.clickable { viewModel.loadSavedSong(song) }
                            )
                            HorizontalDivider()
                        }
                    }
                    Spacer(modifier = Modifier.height(16.dp))
                }

                OutlinedTextField(
                    value = searchText,
                    onValueChange = { viewModel.searchText.value = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(stringResource(R.string.label_search_hint)) },
                    singleLine = true
                )
                Spacer(modifier = Modifier.height(12.dp))
                Button(
                    onClick = { viewModel.search() },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !isSearching && searchText.isNotBlank()
                ) {
                    Text(if (isSearching) stringResource(R.string.btn_searching) else stringResource(R.string.btn_search_lyrics))
                }
            }
        }
    }
}

@Composable
private fun ResultsList(results: List<LyricSearchResult>, onSelect: (LyricSearchResult) -> Unit, onDismiss: () -> Unit) {
    Column {
        Text(stringResource(R.string.label_results_count, results.size), style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(bottom = 8.dp))
        TextButton(onClick = onDismiss) { Text(stringResource(R.string.btn_cancel)) }
        LazyColumn {
            items(results) { result ->
                ListItem(
                    headlineContent = { Text(result.trackName) },
                    supportingContent = {
                        Column {
                            Text(result.artistName, style = MaterialTheme.typography.bodySmall)
                            if (result.albumName != null) Text(result.albumName, style = MaterialTheme.typography.labelSmall)
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                if (result.hasSyncedLyrics) Text(stringResource(R.string.label_synced), color = MaterialTheme.colorScheme.primary)
                                else Text(stringResource(R.string.label_plain), color = MaterialTheme.colorScheme.outline)
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
private fun LyricDisplayContent(song: LyricSong, currentLineIndex: Int, onBack: () -> Unit, onSave: () -> Unit, onPlayFromStart: () -> Unit, onPlayFromNow: () -> Unit, onStopPlayback: () -> Unit, onPlayFromLine: (Int) -> Unit, isPlaying: Boolean) {
    Column(modifier = Modifier.fillMaxSize()) {
        IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.btn_back)) }

        if (song.hasTimestamps) {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = { if (isPlaying) onStopPlayback() else onPlayFromStart() }, modifier = Modifier.weight(1f)) {
                    Text(if (isPlaying) stringResource(R.string.btn_stop) else stringResource(R.string.btn_play_from_start))
                }
                Button(onClick = { if (isPlaying) onStopPlayback() else onPlayFromNow() }, modifier = Modifier.weight(1f)) {
                    Text(if (isPlaying) stringResource(R.string.btn_stop) else stringResource(R.string.btn_play_from_now))
                }
            }
            Spacer(modifier = Modifier.height(8.dp))
        } else {
            Text(stringResource(R.string.label_no_timed_lyrics), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.outline, modifier = Modifier.padding(vertical = 4.dp))
        }

        LazyColumn(modifier = Modifier.weight(1f)) {
            itemsIndexed(song.lines) { index, line ->
                val isCurrentLine = index == currentLineIndex
                val bgColor = if (isCurrentLine) MaterialTheme.colorScheme.primaryContainer
                else MaterialTheme.colorScheme.surface
                Surface(
                    color = bgColor,
                    shape = MaterialTheme.shapes.small,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 8.dp, vertical = 1.dp)
                        .then(
                            if (song.hasTimestamps) Modifier.clickable {
                                if (isPlaying) onStopPlayback()
                                onPlayFromLine(index)
                            } else Modifier
                        )
                ) {
                    Text(
                        line.text,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp),
                        color = if (isCurrentLine) MaterialTheme.colorScheme.onPrimaryContainer
                        else MaterialTheme.colorScheme.onSurface
                    )
                }
            }
        }

        Button(onClick = onSave, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.btn_save_lyrics)) }
    }
}
