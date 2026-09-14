package com.eyepal.app.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.eyepal.app.R
import com.eyepal.app.ui.Screen

@Composable
fun VisionNavigatorScreen(
    onNavigateTo: (Screen) -> Unit,
    onOpenSavedFaces: () -> Unit,
    onOpenSettings: () -> Unit,
) {
    Column(modifier = Modifier.fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(stringResource(R.string.tab_vision), style = MaterialTheme.typography.headlineSmall)
        Button(onClick = { onNavigateTo(Screen.QuickRecognition) }, modifier = Modifier.fillMaxWidth()) {
            Text(stringResource(R.string.vision_quick))
        }
        Button(onClick = { onNavigateTo(Screen.DetailsRecognition) }, modifier = Modifier.fillMaxWidth()) {
            Text(stringResource(R.string.vision_details))
        }
        Button(onClick = { onNavigateTo(Screen.ReadText) }, modifier = Modifier.fillMaxWidth()) {
            Text(stringResource(R.string.vision_text))
        }
        Button(onClick = { onNavigateTo(Screen.Faces) }, modifier = Modifier.fillMaxWidth()) {
            Text(stringResource(R.string.vision_faces))
        }
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedButton(onClick = onOpenSavedFaces, modifier = Modifier.weight(1f)) {
                Text(stringResource(R.string.vision_saved_faces))
            }
            OutlinedButton(onClick = onOpenSettings, modifier = Modifier.weight(1f)) {
                Text(stringResource(R.string.tab_settings))
            }
        }
    }
}

@Composable
fun AssistNavigatorScreen(
    onNavigateTo: (Screen) -> Unit,
) {
    Column(modifier = Modifier.fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(stringResource(R.string.tab_assist), style = MaterialTheme.typography.headlineSmall)
        Button(onClick = { onNavigateTo(Screen.FloorDetection) }, modifier = Modifier.fillMaxWidth()) {
            Text(stringResource(R.string.tab_floor))
        }
        Button(onClick = { onNavigateTo(Screen.LyricPrompter) }, modifier = Modifier.fillMaxWidth()) {
            Text(stringResource(R.string.tab_lyrics))
        }
        Button(onClick = { onNavigateTo(Screen.Chat) }, modifier = Modifier.fillMaxWidth()) {
            Text(stringResource(R.string.tab_chat))
        }
        OutlinedButton(onClick = { onNavigateTo(Screen.Settings) }, modifier = Modifier.fillMaxWidth()) {
            Text(stringResource(R.string.tab_settings))
        }
    }
}