package com.eyepal.app.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.eyepal.app.viewmodels.GoogleGlassViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GoogleGlassScreen(onBack: () -> Unit, viewModel: GoogleGlassViewModel = viewModel()) {
    val isConnected by viewModel.isConnected
    val statusText by viewModel.statusText
    val useGlassCamera by viewModel.useGlassCamera
    val cameraFrame by viewModel.cameraFrame

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        TopAppBar(title = { Text("Google Glass") }, navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") } })

        Card(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text("Audio Glasses", style = MaterialTheme.typography.titleMedium)
                Spacer(modifier = Modifier.height(8.dp))
                Text(statusText, color = if (isConnected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline)
                Spacer(modifier = Modifier.height(12.dp))
                if (isConnected) {
                    Button(onClick = { viewModel.disconnect() }, modifier = Modifier.fillMaxWidth()) { Text("Disconnect") }
                } else {
                    Button(onClick = { viewModel.connect() }, modifier = Modifier.fillMaxWidth()) { Text("Connect Audio Glasses") }
                }
            }
        }

        if (isConnected) {
            Spacer(modifier = Modifier.height(16.dp))
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text("Glass Camera", style = MaterialTheme.typography.titleMedium)
                    Spacer(modifier = Modifier.height(8.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("Use phone camera, display on glasses")
                        Spacer(modifier = Modifier.weight(1f))
                        Switch(checked = useGlassCamera, onCheckedChange = { viewModel.toggleGlassCamera() })
                    }
                    if (useGlassCamera && cameraFrame != null) {
                        Spacer(modifier = Modifier.height(8.dp))
                        Text("Camera active. Feed displayed on glasses.", color = MaterialTheme.colorScheme.primary)
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(16.dp))
        Card(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text("How it works", style = MaterialTheme.typography.titleMedium)
                Spacer(modifier = Modifier.height(8.dp))
                Text("EyePal routes audio descriptions to your glasses via Bluetooth SCO. Enable glass camera to display the phone camera feed on the glasses screen.", style = MaterialTheme.typography.bodyMedium)
                Spacer(modifier = Modifier.height(4.dp))
                Text("Pair your glasses in Android Bluetooth settings first, then connect here.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.outline)
            }
        }
    }
}
