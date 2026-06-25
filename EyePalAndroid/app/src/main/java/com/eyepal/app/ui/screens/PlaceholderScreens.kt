package com.eyepal.app.ui.screens

import android.view.ViewGroup
import androidx.camera.view.PreviewView
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.viewmodel.compose.viewModel
import com.eyepal.app.viewmodels.ReadTextViewModel
import com.eyepal.app.viewmodels.FacesViewModel
import com.eyepal.app.viewmodels.FloorDetectionViewModel
import com.eyepal.app.viewmodels.ChatViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReadTextScreen(viewModel: ReadTextViewModel = viewModel()) {
    val statusText by viewModel.statusText
    val recognizedText by viewModel.recognizedText
    val isProcessing by viewModel.isProcessing
    val isContinuous by viewModel.isContinuous

    DisposableEffect(Unit) { onDispose { viewModel.stopContinuous(); viewModel.stopCamera() } }

    Column(modifier = Modifier.fillMaxSize()) {
        AndroidView(factory = { ctx -> PreviewView(ctx).apply { layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT); scaleType = PreviewView.ScaleType.FILL_CENTER; implementationMode = PreviewView.ImplementationMode.COMPATIBLE } },
            modifier = Modifier.fillMaxWidth().weight(1f), update = { preview -> viewModel.startCamera(preview) })

        Card(modifier = Modifier.fillMaxWidth().padding(16.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.9f))) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text(statusText, style = MaterialTheme.typography.bodyLarge)
                if (recognizedText.isNotEmpty()) {
                    Spacer(modifier = Modifier.height(8.dp))
                    Card(modifier = Modifier.fillMaxWidth()) { Text(recognizedText, modifier = Modifier.padding(12.dp)) }
                }
                Spacer(modifier = Modifier.height(12.dp))
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = { viewModel.captureAndRecognize() }, modifier = Modifier.weight(1f), enabled = !isProcessing && !isContinuous) { Text("Capture") }
                    Button(onClick = { if (isContinuous) viewModel.stopContinuous() else viewModel.startContinuous() }, modifier = Modifier.weight(1f), colors = ButtonDefaults.buttonColors(containerColor = if (isContinuous) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.secondary)) { Text(if (isContinuous) "Stop" else "Continuous") }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FacesScreen(viewModel: FacesViewModel = viewModel(), onNavigateToSavedFaces: () -> Unit = {}, savedFacesViewModel: FacesViewModel = viewModel) {
    val statusText by viewModel.statusText
    val isProcessing by viewModel.isProcessing
    val pendingSaveName by viewModel.pendingSaveName
    var nameInput by remember { mutableStateOf("") }

    DisposableEffect(Unit) { onDispose { viewModel.stopCamera() } }

    Column(modifier = Modifier.fillMaxSize()) {
        AndroidView(factory = { ctx -> PreviewView(ctx).apply { layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT); scaleType = PreviewView.ScaleType.FILL_CENTER; implementationMode = PreviewView.ImplementationMode.COMPATIBLE } },
            modifier = Modifier.fillMaxWidth().weight(1f), update = { preview -> viewModel.startCamera(preview) })

        Card(modifier = Modifier.fillMaxWidth().padding(16.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.9f))) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text(statusText, style = MaterialTheme.typography.bodyLarge)
                Spacer(modifier = Modifier.height(12.dp))
                Button(onClick = { viewModel.detectFaces() }, modifier = Modifier.fillMaxWidth(), enabled = !isProcessing) { Text(if (isProcessing) "Detecting..." else "Detect Faces") }
                Spacer(modifier = Modifier.height(8.dp))
                OutlinedButton(onClick = onNavigateToSavedFaces, modifier = Modifier.fillMaxWidth()) { Text("Manage Saved Faces") }
            }
        }
    }

    if (pendingSaveName != null) {
        AlertDialog(onDismissRequest = { viewModel.dismissSave() }, title = { Text("Add Person") },
            text = { OutlinedTextField(value = nameInput, onValueChange = { nameInput = it }, modifier = Modifier.fillMaxWidth(), placeholder = { Text("Person's name") }, singleLine = true) },
            confirmButton = { TextButton(onClick = { viewModel.saveFace(nameInput); nameInput = "" }, enabled = nameInput.isNotBlank()) { Text("Save") } },
            dismissButton = { TextButton(onClick = { nameInput = ""; viewModel.dismissSave() }) { Text("Not Now") } })
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FloorDetectionScreen(viewModel: FloorDetectionViewModel = viewModel()) {
    val currentFloor by viewModel.currentFloor
    val statusText by viewModel.statusText
    val records by viewModel.records
    var showSaveDialog by remember { mutableStateOf(false) }
    var noteText by remember { mutableStateOf("") }

    DisposableEffect(Unit) { onDispose { viewModel.stop() } }

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        TopAppBar(title = { Text("Floor Detection") })
        Spacer(modifier = Modifier.height(16.dp))

        Text("Floor Level", style = MaterialTheme.typography.headlineLarge)
        Text("$currentFloor", style = MaterialTheme.typography.displayLarge, color = MaterialTheme.colorScheme.primary)
        Spacer(modifier = Modifier.height(8.dp))
        Text(statusText, style = MaterialTheme.typography.bodyLarge)
        Spacer(modifier = Modifier.height(16.dp))

        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = { viewModel.calibrate() }, modifier = Modifier.weight(1f)) { Text("Calibrate") }
            Button(onClick = { viewModel.start() }, modifier = Modifier.weight(1f), colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.secondary)) { Text("Start") }
            Button(onClick = { showSaveDialog = true }, modifier = Modifier.weight(1f)) { Text("Save") }
        }

        if (records.isNotEmpty()) {
            Spacer(modifier = Modifier.height(16.dp))
            Text("Saved Records", style = MaterialTheme.typography.titleMedium)
            LazyColumn(modifier = Modifier.weight(1f)) {
                items(records) { record ->
                    ListItem(headlineContent = { Text("Floor ${record.floor}") },
                        supportingContent = { Text(if (record.note.isNotEmpty()) record.note else java.text.SimpleDateFormat("MMM dd, HH:mm").format(java.util.Date(record.timestamp))) },
                        trailingContent = { IconButton(onClick = { viewModel.deleteRecord(record.id) }) { Icon(Icons.Default.Delete, "Delete", tint = MaterialTheme.colorScheme.error) } })
                    HorizontalDivider()
                }
            }
        } else {
            Spacer(modifier = Modifier.weight(1f))
            Text("No saved records.", color = MaterialTheme.colorScheme.outline)
        }
    }

    if (showSaveDialog) {
        AlertDialog(onDismissRequest = { showSaveDialog = false }, title = { Text("Save Floor Record") },
            text = { OutlinedTextField(value = noteText, onValueChange = { noteText = it }, modifier = Modifier.fillMaxWidth(), placeholder = { Text("Note (optional)") }) },
            confirmButton = { TextButton(onClick = { viewModel.saveCurrentFloor(noteText); noteText = ""; showSaveDialog = false }) { Text("Save") } },
            dismissButton = { TextButton(onClick = { noteText = ""; showSaveDialog = false }) { Text("Cancel") } })
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatScreen(viewModel: ChatViewModel = viewModel()) {
    val statusText by viewModel.statusText
    val isConnected by viewModel.isConnected
    val transcript by viewModel.transcript

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        TopAppBar(title = { Text("Chat") })
        Spacer(modifier = Modifier.height(16.dp))

        Text("Mode", style = MaterialTheme.typography.titleMedium)
        SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
            SegmentedButton(selected = viewModel.selectedMode.value == "interpreter", onClick = { viewModel.selectedMode.value = "interpreter" }, shape = SegmentedButtonDefaults.itemShape(0, 2)) { Text("Interpreter") }
            SegmentedButton(selected = viewModel.selectedMode.value == "chat", onClick = { viewModel.selectedMode.value = "chat" }, shape = SegmentedButtonDefaults.itemShape(1, 2)) { Text("Chat") }
        }

        Spacer(modifier = Modifier.height(16.dp))
        Text(statusText, style = MaterialTheme.typography.bodyLarge)

        if (transcript.isNotEmpty()) {
            Spacer(modifier = Modifier.height(8.dp))
            Card(modifier = Modifier.fillMaxWidth()) { Text(transcript, modifier = Modifier.padding(12.dp)) }
        }

        Spacer(modifier = Modifier.weight(1f))
        Button(onClick = { if (isConnected) viewModel.stopChat() else viewModel.startChat("placeholder-api-key") }, modifier = Modifier.fillMaxWidth(), enabled = true) {
            Text(if (isConnected) "Stop" else "Start Voice Chat")
        }
    }
}
