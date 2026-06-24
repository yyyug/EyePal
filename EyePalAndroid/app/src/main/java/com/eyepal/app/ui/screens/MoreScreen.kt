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
import com.eyepal.app.data.SettingsRepository
import com.eyepal.app.models.AppFeature

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MoreScreen(
    onNavigateToSettings: () -> Unit,
    onNavigateToFeatureOrder: () -> Unit,
    onNavigateToFloorDetection: () -> Unit,
    onNavigateToChat: () -> Unit,
    onNavigateToLyricPrompter: () -> Unit,
    onNavigateToGoogleGlass: () -> Unit
) {
    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        TopAppBar(title = { Text("More") })
        Spacer(modifier = Modifier.height(8.dp))

        ListItem(headlineContent = { Text("Floor Detection") }, supportingContent = { Text("Helps locate which floor you are on") },
            modifier = Modifier.clickable { onNavigateToFloorDetection() })
        HorizontalDivider()
        ListItem(headlineContent = { Text("Chat") }, supportingContent = { Text("Real-time voice translation") },
            modifier = Modifier.clickable { onNavigateToChat() })
        HorizontalDivider()
        ListItem(headlineContent = { Text("Lyric Prompter") }, supportingContent = { Text("Search and listen to song lyrics") },
            modifier = Modifier.clickable { onNavigateToLyricPrompter() })
        HorizontalDivider()
        ListItem(headlineContent = { Text("Settings") }, supportingContent = { Text("App configuration") },
            modifier = Modifier.clickable { onNavigateToSettings() })
        HorizontalDivider()
        ListItem(headlineContent = { Text("Feature Order") }, supportingContent = { Text("Customize tab layout") },
            modifier = Modifier.clickable { onNavigateToFeatureOrder() })
        HorizontalDivider()
        ListItem(headlineContent = { Text("Google Glass") }, supportingContent = { Text("Audio glasses settings") },
            modifier = Modifier.clickable { onNavigateToGoogleGlass() })
    }
}
