package com.eyepal.app.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.*
import androidx.compose.runtime.*
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
    var renamingProfile by remember { mutableStateOf<SavedFacesViewModel.RenameTarget?>(null) }
    var draftName by remember { mutableStateOf("") }

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
                        supportingContent = { Text(stringResource(R.string.label_samples_count, "${profile.embeddings.size}")) },
                        trailingContent = {
                            Row {
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
}
