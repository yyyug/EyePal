package com.eyepal.app.ui.screens

import android.view.ViewGroup
import androidx.camera.view.PreviewView
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.viewmodel.compose.viewModel
import com.eyepal.app.viewmodels.GoogleGlassViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GoogleGlassScreen(onBack: () -> Unit, viewModel: GoogleGlassViewModel = viewModel()) {
    val isConnected by viewModel.isConnected
    val statusText by viewModel.statusText
    val useGlassCamera by viewModel.useGlassCamera
    val isXRMode by viewModel.isXRMode
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        TopAppBar(title = { Text("Google Glass") }, navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") } })

        Card(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text("Audio Glasses", style = MaterialTheme.typography.titleMedium)
                Spacer(modifier = Modifier.height(8.dp))
                Text(statusText, color = if (isConnected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline)
                if (isConnected && isXRMode) {
                    Spacer(modifier = Modifier.height(4.dp))
                    AssistChip(
                        onClick = {},
                        label = { Text("XR Projected") },
                        leadingIcon = { Text("XR", style = MaterialTheme.typography.labelSmall) }
                    )
                }
                Spacer(modifier = Modifier.height(12.dp))
                if (isConnected) {
                    Button(onClick = { viewModel.disconnect() }, modifier = Modifier.fillMaxWidth()) { Text("Disconnect") }
                } else {
                    Button(onClick = {
                        val activity = context as? android.app.Activity
                        if (activity != null) viewModel.connect(activity)
                    }, modifier = Modifier.fillMaxWidth()) { Text("Connect Audio Glasses") }
                }
            }
        }

        if (isConnected) {
            Spacer(modifier = Modifier.height(16.dp))
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text("Glasses Camera", style = MaterialTheme.typography.titleMedium)
                    Spacer(modifier = Modifier.height(8.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("Use glasses camera in Quick/Details/ReadText")
                        Spacer(modifier = Modifier.weight(1f))
                        Switch(checked = useGlassCamera, onCheckedChange = {
                            viewModel.toggleGlassCamera(lifecycleOwner, PreviewView(context).apply {
                                layoutParams = ViewGroup.LayoutParams(1, 1)
                            })
                        })
                    }
                    if (isXRMode) {
                        Spacer(modifier = Modifier.height(8.dp))
                        Text("XR Mode: Camera accessed via projected context", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
                    }
                    if (useGlassCamera) {
                        Spacer(modifier = Modifier.height(8.dp))
                        AndroidView(
                            factory = { ctx ->
                                PreviewView(ctx).apply {
                                    layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 200)
                                    scaleType = PreviewView.ScaleType.FILL_CENTER
                                    implementationMode = PreviewView.ImplementationMode.COMPATIBLE
                                }
                            },
                            modifier = Modifier.fillMaxWidth().height(200.dp),
                            update = { preview -> viewModel.toggleGlassCamera(lifecycleOwner, preview) }
                        )
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(16.dp))
        Card(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text("How it works", style = MaterialTheme.typography.titleMedium)
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    if (isXRMode) "Connected via XR Projected context. Camera and audio are accessed directly from the glasses' hardware."
                    else "Connected via Bluetooth HFP. Audio is routed through Bluetooth. Enable 'Use glasses camera' to capture photos.",
                    style = MaterialTheme.typography.bodyMedium
                )
            }
        }
    }
}
