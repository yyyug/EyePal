package com.eyepal.app.ui.screens

import android.view.ViewGroup
import androidx.camera.view.PreviewView
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.eyepal.app.EyePalApplication
import com.eyepal.app.R
import com.eyepal.app.ui.Screen

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun VisionNavigatorScreen(
    onNavigateTo: (Screen) -> Unit,
    onOpenSavedFaces: () -> Unit,
    onOpenSettings: () -> Unit,
) {
    val context = LocalContext.current
    val camera = remember { (context.applicationContext as EyePalApplication).container.cameraService }
    val lifecycleOwner = LocalLifecycleOwner.current

    DisposableEffect(Unit) { onDispose { camera.stopCamera() } }

    Column(modifier = Modifier.fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(stringResource(R.string.tab_vision), style = MaterialTheme.typography.headlineSmall)
        Text(
            stringResource(R.string.vision_activate_hint),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        AndroidView(
            factory = { ctx ->
                PreviewView(ctx).apply {
                    layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                    scaleType = PreviewView.ScaleType.FILL_CENTER
                    implementationMode = PreviewView.ImplementationMode.COMPATIBLE
                }
            },
            modifier = Modifier
                .fillMaxWidth()
                .height(200.dp)
                .clip(RoundedCornerShape(14.dp)),
            update = { preview -> camera.startCamera(lifecycleOwner, preview) }
        )

        VisionActionButton(
            label = stringResource(R.string.vision_quick),
            onClick = { onNavigateTo(Screen.QuickRecognition) },
            menuItems = listOf(
                stringResource(R.string.tab_settings) to { onNavigateTo(Screen.QuickSettings) }
            )
        )
        VisionActionButton(
            label = stringResource(R.string.vision_details),
            onClick = { onNavigateTo(Screen.DetailsRecognition) },
            menuItems = listOf(
                stringResource(R.string.tab_settings) to { onNavigateTo(Screen.DetailsSettings) }
            )
        )
        VisionActionButton(
            label = stringResource(R.string.vision_text),
            onClick = { onNavigateTo(Screen.ReadText) },
            menuItems = listOf(
                stringResource(R.string.tab_settings) to { onNavigateTo(Screen.TextSettings) }
            )
        )
        VisionActionButton(
            label = stringResource(R.string.vision_faces),
            onClick = { onNavigateTo(Screen.Faces) },
            menuItems = listOf(
                stringResource(R.string.vision_saved_faces) to onOpenSavedFaces,
                stringResource(R.string.tab_settings) to { onNavigateTo(Screen.FacesSettings) }
            )
        )

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

/** Primary action button whose long-press reveals the extra options (iOS parity). */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun VisionActionButton(
    label: String,
    onClick: () -> Unit,
    menuItems: List<Pair<String, () -> Unit>>,
) {
    var expanded by remember { mutableStateOf(false) }

    Box(modifier = Modifier.fillMaxWidth()) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .clip(ButtonDefaults.shape)
                .background(MaterialTheme.colorScheme.primary)
                .combinedClickable(
                    onClick = onClick,
                    onLongClick = { expanded = true }
                )
                .padding(vertical = 14.dp),
            contentAlignment = Alignment.Center
        ) {
            Text(label, color = MaterialTheme.colorScheme.onPrimary, style = MaterialTheme.typography.labelLarge)
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            menuItems.forEach { (title, action) ->
                DropdownMenuItem(
                    text = { Text(title) },
                    onClick = {
                        expanded = false
                        action()
                    }
                )
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
