package com.eyepal.app.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.eyepal.app.viewmodels.FacesViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SavedFacesScreen(viewModel: FacesViewModel, onBack: () -> Unit) {
    val profiles by viewModel.profiles

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        TopAppBar(title = { Text("Saved Faces") }, navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") } })

        if (profiles.isEmpty()) {
            Spacer(modifier = Modifier.height(24.dp))
            Text("No faces saved yet.", color = MaterialTheme.colorScheme.outline)
        } else {
            LazyColumn {
                items(profiles) { profile ->
                    ListItem(
                        headlineContent = { Text(profile.name) },
                        supportingContent = { Text("${profile.embeddings.size} samples") },
                        trailingContent = { IconButton(onClick = { viewModel.deleteFace(profile.id) }) { Icon(Icons.Default.Delete, "Delete", tint = MaterialTheme.colorScheme.error) } }
                    )
                    HorizontalDivider()
                }
            }
        }
    }
}
