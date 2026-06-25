package com.eyepal.app.ui.screens

import android.graphics.Bitmap
import androidx.compose.foundation.Image
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
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.eyepal.app.viewmodels.GoogleGlassViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GoogleGlassScreen(onBack: () -> Unit, viewModel: GoogleGlassViewModel = viewModel()) {
    val isConnected by viewModel.isConnected
    val statusText by viewModel.statusText
    val pairedDevices by viewModel.pairedDevices
    val cameraFrame by viewModel.cameraFrame
    val useGlassCamera by viewModel.useGlassCamera
    var showPairDialog by remember { mutableStateOf(false) }

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        TopAppBar(title = { Text("Google Glass") }, navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") } })

        Card(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text("Audio Glasses", style = MaterialTheme.typography.titleMedium)
                Spacer(modifier = Modifier.height(8.dp))
                if (isConnected) {
                    Text("Connected", color = MaterialTheme.colorScheme.primary)
                    Spacer(modifier = Modifier.height(8.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(onClick = { viewModel.disconnect() }) { Text("Disconnect") }
                        Button(onClick = { viewModel.startReadingCamera() }) { Text("Start Camera") }
                    }
                } else {
                    Text(statusText, color = MaterialTheme.colorScheme.outline)
                    Spacer(modifier = Modifier.height(8.dp))
                    Button(onClick = { showPairDialog = true }) { Text("Pair Device") }
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
                        Text("Use glass camera for recognition")
                        Spacer(modifier = Modifier.weight(1f))
                        Switch(checked = useGlassCamera, onCheckedChange = { viewModel.useGlassCamera.value = it })
                    }
                    if (useGlassCamera && cameraFrame != null) {
                        Spacer(modifier = Modifier.height(8.dp))
                        Image(bitmap = cameraFrame!!.asImageBitmap(), contentDescription = "Glass camera view", modifier = Modifier.fillMaxWidth().height(200.dp), contentScale = ContentScale.Fit)
                    } else if (useGlassCamera) {
                        Spacer(modifier = Modifier.height(8.dp))
                        Text("Waiting for camera feed...", color = MaterialTheme.colorScheme.outline)
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(16.dp))
        Card(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text("How it works", style = MaterialTheme.typography.titleMedium)
                Spacer(modifier = Modifier.height(8.dp))
                Text("EyePal sends audio descriptions to your glasses via Bluetooth. Enable glass camera to use the glasses' camera for scene recognition.", style = MaterialTheme.typography.bodyMedium)
            }
        }
    }

    if (showPairDialog) {
        AlertDialog(
            onDismissRequest = { showPairDialog = false },
            title = { Text("Select Glasses") },
            text = {
                if (pairedDevices.isEmpty()) {
                    Text("No paired Bluetooth devices found. Pair your glasses in Android settings first.")
                } else {
                    LazyColumn {
                        items(pairedDevices) { device ->
                            ListItem(headlineContent = { Text(device.name ?: "Unknown") }, supportingContent = { Text(device.address ?: "") },
                                modifier = Modifier.clickable { viewModel.connect(device); showPairDialog = false })
                        }
                    }
                }
            },
            confirmButton = { TextButton(onClick = { showPairDialog = false }) { Text("Cancel") } }
        )
    }
}
