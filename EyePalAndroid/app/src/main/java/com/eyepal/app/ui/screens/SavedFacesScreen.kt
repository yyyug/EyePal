package com.eyepal.app.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.TextFields
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.eyepal.app.R
import com.eyepal.app.viewmodels.SavedFacesViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SavedFacesScreen(viewModel: SavedFacesViewModel = viewModel(), onBack: () -> Unit) {
    val profiles by viewModel.profiles
    val playingProfileId by viewModel.playingProfileId
    var renamingProfile by remember { mutableStateOf<SavedFacesViewModel.RenameTarget?>(null) }
    var draftName by remember { mutableStateOf("") }
    var editingNoteProfileId by remember { mutableStateOf<String?>(null) }
    var draftNote by remember { mutableStateOf("") }

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        TopAppBar(title = { Text(stringResource(R.string.tab_saved_faces)) }, navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.btn_back)) } })

        if (profiles.isEmpty()) {
            Spacer(modifier = Modifier.height(24.dp))
            Text(stringResource(R.string.status_no_faces_saved), color = MaterialTheme.colorScheme.outline)
        } else {
            LazyColumn {
                items(profiles) { profile ->
                    ListItem(
                        headlineContent = { Text(profile.name) },
                        supportingContent = {
                            Column {
                                Text(stringResource(R.string.label_samples_count, "${profile.embeddings.size}"))
                                profile.textNote?.takeIf { it.isNotBlank() }?.let {
                                    Text(stringResource(R.string.label_text_note, it), color = MaterialTheme.colorScheme.outline)
                                }
                            }
                        },
                        trailingContent = {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                IconButton(
                                    onClick = { viewModel.togglePlay(profile) },
                                    enabled = profile.soundFilename != null
                                ) {
                                    if (playingProfileId == profile.id) {
                                        Icon(Icons.Default.Stop, stringResource(R.string.btn_stop), tint = MaterialTheme.colorScheme.primary)
                                    } else {
                                        Icon(Icons.Default.PlayArrow, stringResource(R.string.btn_play_note), tint = if (profile.soundFilename != null) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline)
                                    }
                                }
                                IconButton(onClick = {
                                    draftNote = profile.textNote.orEmpty()
                                    editingNoteProfileId = profile.id
                                }) {
                                    Icon(Icons.Default.TextFields, stringResource(R.string.btn_enter_text_note), tint = MaterialTheme.colorScheme.primary)
                                }
                                IconButton(onClick = {
                                    draftName = profile.name
                                    renamingProfile = SavedFacesViewModel.RenameTarget(profile.id, profile.name)
                                }) {
                                    Icon(Icons.Default.Edit, stringResource(R.string.btn_edit), tint = MaterialTheme.colorScheme.primary)
                                }
                                IconButton(onClick = { viewModel.deleteFace(profile.id) }) {
                                    Icon(Icons.Default.Delete, stringResource(R.string.btn_delete), tint = MaterialTheme.colorScheme.error)
                                }
                            }
                        }
                    )
                    HorizontalDivider()
                }
            }
        }
    }

    if (renamingProfile != null) {
        AlertDialog(
            onDismissRequest = { renamingProfile = null; draftName = "" },
            title = { Text(stringResource(R.string.btn_rename_face)) },
            text = {
                OutlinedTextField(
                    value = draftName,
                    onValueChange = { draftName = it },
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text(stringResource(R.string.faces_person_name)) },
                    singleLine = true
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        renamingProfile?.let { target ->
                            viewModel.renameFace(target.id, draftName)
                        }
                        renamingProfile = null
                        draftName = ""
                    },
                    enabled = draftName.isNotBlank()
                ) { Text(stringResource(R.string.btn_save)) }
            },
            dismissButton = {
                TextButton(onClick = { renamingProfile = null; draftName = "" }) { Text(stringResource(R.string.btn_cancel)) }
            }
        )
    }

    if (editingNoteProfileId != null) {
        AlertDialog(
            onDismissRequest = { editingNoteProfileId = null; draftNote = "" },
            title = { Text(stringResource(R.string.btn_enter_text_note)) },
            text = {
                Column {
                    OutlinedTextField(
                        value = draftNote,
                        onValueChange = { draftNote = it },
                        modifier = Modifier.fillMaxWidth(),
                        placeholder = { Text(stringResource(R.string.text_note_prompt)) },
                        singleLine = false
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(stringResource(R.string.text_note_message), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.outline)
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    editingNoteProfileId?.let { id ->
                        viewModel.updateTextNote(id, draftNote)
                    }
                    editingNoteProfileId = null
                    draftNote = ""
                }) { Text(stringResource(R.string.btn_save)) }
            },
            dismissButton = {
                TextButton(onClick = { editingNoteProfileId = null; draftNote = "" }) { Text(stringResource(R.string.btn_cancel)) }
            }
        )
    }

    DisposableEffect(Unit) { onDispose { viewModel.stopPlayback() } }
}