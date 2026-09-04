package com.eyepal.app.ui.screens

import android.content.Context
import android.view.ViewGroup
import androidx.camera.view.PreviewView
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.viewmodel.compose.viewModel
import com.eyepal.app.R
import com.eyepal.app.viewmodels.ReadTextViewModel
import com.eyepal.app.viewmodels.FacesViewModel
import com.eyepal.app.viewmodels.FloorDetectionViewModel
import com.eyepal.app.viewmodels.ChatViewModel
import com.eyepal.app.services.OAuthService
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReadTextScreen(viewModel: ReadTextViewModel = viewModel()) {
    val statusText by viewModel.statusText
    val recognizedText by viewModel.recognizedText
    val detectedLanguage by viewModel.detectedLanguage
    val isDocumentMode by viewModel.isDocumentMode
    val showCaptureDialog by viewModel.showCaptureDialog
    val capturedTextForDisplay by viewModel.capturedTextForDisplay
    val isProcessing by viewModel.isProcessing
    val errorMessage by viewModel.errorMessage

    DisposableEffect(Unit) { onDispose { viewModel.stopCamera() } }
    LaunchedEffect(Unit) { viewModel.startCamera() }

    Column(modifier = Modifier.fillMaxSize()) {
        AndroidView(factory = { ctx -> PreviewView(ctx).apply { layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT); scaleType = PreviewView.ScaleType.FILL_CENTER; implementationMode = PreviewView.ImplementationMode.COMPATIBLE } },
            modifier = Modifier.fillMaxWidth().weight(1f), update = { preview -> viewModel.startCamera(preview) })

        Card(modifier = Modifier.fillMaxWidth().padding(16.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.9f))) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text(statusText, style = MaterialTheme.typography.bodyLarge)

                if (errorMessage != null) {
                    Spacer(modifier = Modifier.height(8.dp))
                    Card(
                        modifier = Modifier.fillMaxWidth(),
                        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer)
                    ) {
                        Text(
                            errorMessage ?: "",
                            modifier = Modifier.padding(12.dp),
                            color = MaterialTheme.colorScheme.onErrorContainer,
                            style = MaterialTheme.typography.bodySmall
                        )
                    }
                }

                // Detected language display
                if (detectedLanguage.isNotEmpty()) {
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        stringResource(R.string.label_detected_language, detectedLanguage),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.primary
                    )
                }

                // Document mode toggle
                Row(
                    modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(stringResource(R.string.document_detection), style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
                    Switch(
                        checked = isDocumentMode,
                        onCheckedChange = { viewModel.isDocumentMode.value = it }
                    )
                }

                if (recognizedText.isNotEmpty()) {
                    Spacer(modifier = Modifier.height(8.dp))
                    Card(modifier = Modifier.fillMaxWidth()) { Text(recognizedText, modifier = Modifier.padding(12.dp)) }
                }

                Spacer(modifier = Modifier.height(12.dp))
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = { viewModel.captureAndRecognize() }, modifier = Modifier.weight(1f), enabled = !isProcessing) { Text(stringResource(R.string.btn_take_photo)) }
                }
            }
        }
    }

    // Captured text result (full-screen, matching iOS sheet)
    if (showCaptureDialog) {
        Dialog(
            onDismissRequest = { viewModel.showCaptureDialog.value = false },
            properties = DialogProperties(usePlatformDefaultWidth = false)
        ) {
            Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            stringResource(R.string.label_captured_text),
                            style = MaterialTheme.typography.titleLarge,
                            modifier = Modifier.weight(1f)
                        )
                        TextButton(onClick = { viewModel.showCaptureDialog.value = false }) {
                            Text(stringResource(R.string.btn_done))
                        }
                    }
                    HorizontalDivider()
                    Spacer(modifier = Modifier.height(16.dp))
                    Text(
                        capturedTextForDisplay,
                        modifier = Modifier.fillMaxWidth(),
                        style = MaterialTheme.typography.titleMedium
                    )
                    Spacer(modifier = Modifier.height(16.dp))
                    if (detectedLanguage.isNotEmpty()) {
                        Text(
                            stringResource(R.string.label_detected_language, detectedLanguage),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.secondary
                        )
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FacesScreen(viewModel: FacesViewModel = viewModel()) {
    val statusText by viewModel.statusText
    val recognizedName by viewModel.recognizedName
    val pendingSaveName by viewModel.pendingSaveName
    val pendingSampleCount by viewModel.pendingSampleCount
    val sampleTarget = viewModel.sampleTarget
    var nameInput by remember { mutableStateOf("") }
    val focusManager = LocalFocusManager.current

    DisposableEffect(Unit) { onDispose { viewModel.stopCamera() } }

    LaunchedEffect(Unit) { viewModel.startCamera() }

    Column(modifier = Modifier.fillMaxSize()) {
        AndroidView(factory = { ctx -> PreviewView(ctx).apply { layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT); scaleType = PreviewView.ScaleType.FILL_CENTER; implementationMode = PreviewView.ImplementationMode.COMPATIBLE } },
            modifier = Modifier.fillMaxWidth().weight(1f), update = { preview -> viewModel.startCamera(preview) })

        Card(modifier = Modifier.fillMaxWidth().padding(16.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.9f))) {
            Column(modifier = Modifier.padding(16.dp)) {
                if (pendingSampleCount > 0 && pendingSaveName == null) {
                    LinearProgressIndicator(
                        progress = { pendingSampleCount.toFloat() / sampleTarget },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(stringResource(R.string.label_capturing_samples, pendingSampleCount, sampleTarget), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.outline)
                    Spacer(modifier = Modifier.height(8.dp))
                }
                Text(statusText, style = MaterialTheme.typography.bodyLarge)
                recognizedName?.let { name ->
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(name, style = MaterialTheme.typography.headlineLarge, color = MaterialTheme.colorScheme.primary)
                }
            }
        }
        Spacer(modifier = Modifier.height(16.dp))
    }

    if (pendingSaveName != null) {
        val onSave = { if (nameInput.isNotBlank()) { viewModel.saveFace(nameInput); nameInput = ""; focusManager.clearFocus() } }
        AlertDialog(onDismissRequest = { viewModel.dismissSave() }, title = { Text(stringResource(R.string.faces_add_person)) },
            text = { OutlinedTextField(value = nameInput, onValueChange = { nameInput = it }, modifier = Modifier.fillMaxWidth(), placeholder = { Text(stringResource(R.string.faces_person_name)) }, singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { onSave() })) },
            confirmButton = { TextButton(onClick = { onSave() }, enabled = nameInput.isNotBlank()) { Text(stringResource(R.string.btn_save)) } },
            dismissButton = { TextButton(onClick = { nameInput = ""; viewModel.dismissSave() }) { Text(stringResource(R.string.btn_not_now)) } })
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
    var showAddDialog by remember { mutableStateOf(false) }
    var showRenameDialog by remember { mutableStateOf(false) }
    var showEditDialog by remember { mutableStateOf(false) }
    var editingRecordId by remember { mutableStateOf("") }
    var renameText by remember { mutableStateOf("") }
    var editName by remember { mutableStateOf("") }
    var editAltitude by remember { mutableStateOf("") }
    var editFloor by remember { mutableStateOf("") }
    var addName by remember { mutableStateOf("") }
    var addAltitude by remember { mutableStateOf("") }
    var addFloor by remember { mutableStateOf("") }

    DisposableEffect(Unit) { onDispose { viewModel.stop() } }

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        TopAppBar(
            title = { Text(stringResource(R.string.feature_floor_detection)) },
            actions = {
                IconButton(onClick = {
                    addName = ""
                    addAltitude = viewModel.getCurrentAltitude().toInt().toString()
                    addFloor = currentFloor.toString()
                    showAddDialog = true
                }) {
                    Icon(Icons.Default.Add, stringResource(R.string.btn_add))
                }
            }
        )
        Spacer(modifier = Modifier.height(16.dp))

        Text(stringResource(R.string.floor_level), style = MaterialTheme.typography.headlineLarge)
        Text("$currentFloor", style = MaterialTheme.typography.displayLarge, color = MaterialTheme.colorScheme.primary)
        Spacer(modifier = Modifier.height(8.dp))
        Text(statusText, style = MaterialTheme.typography.bodyLarge)
        Spacer(modifier = Modifier.height(16.dp))

        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = { viewModel.calibrate() }, modifier = Modifier.weight(1f)) { Text(stringResource(R.string.btn_calibrate)) }
            Button(onClick = { viewModel.start() }, modifier = Modifier.weight(1f), colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.secondary)) { Text(stringResource(R.string.btn_start)) }
            Button(onClick = { showSaveDialog = true }, modifier = Modifier.weight(1f)) { Text(stringResource(R.string.btn_save)) }
        }

        if (records.isNotEmpty()) {
            Spacer(modifier = Modifier.height(16.dp))
            Text(stringResource(R.string.floor_saved_records), style = MaterialTheme.typography.titleMedium)
            LazyColumn(modifier = Modifier.weight(1f)) {
                items(records) { record ->
                    ListItem(
                        headlineContent = {
                            Text(if (record.name.isNotEmpty()) record.name else stringResource(R.string.floor_label, "${record.floor}"))
                        },
                        supportingContent = {
                            val floorLabel = stringResource(R.string.floor_label, "${record.floor}")
                            Text(buildString {
                                append(floorLabel)
                                if (record.altitude != 0.0) append(" • ${String.format(Locale.US, "%.1f", record.altitude)}m")
                                if (record.note.isNotEmpty()) append(" • ${record.note}")
                                if (record.name.isEmpty()) append(" • ${java.text.SimpleDateFormat("MMM dd, HH:mm", Locale.US).format(java.util.Date(record.timestamp))}")
                            })
                        },
                        trailingContent = {
                            Row {
                                IconButton(onClick = {
                                    editingRecordId = record.id
                                    renameText = record.name
                                    showRenameDialog = true
                                }) {
                                    Icon(Icons.Default.Edit, stringResource(R.string.btn_edit))
                                }
                                IconButton(onClick = { viewModel.deleteRecord(record.id) }) {
                                    Icon(Icons.Default.Delete, stringResource(R.string.btn_delete), tint = MaterialTheme.colorScheme.error)
                                }
                            }
                        },
                        modifier = Modifier.clickable {
                            editingRecordId = record.id
                            editName = record.name
                            editAltitude = record.altitude.toInt().toString()
                            editFloor = record.floor.toString()
                            showEditDialog = true
                        }
                    )
                    HorizontalDivider()
                }
            }
        } else {
            Spacer(modifier = Modifier.weight(1f))
            Text(stringResource(R.string.status_no_saved_records), color = MaterialTheme.colorScheme.outline)
        }
    }

    // Save current floor dialog
    if (showSaveDialog) {
        AlertDialog(onDismissRequest = { showSaveDialog = false }, title = { Text(stringResource(R.string.floor_save_record)) },
            text = { OutlinedTextField(value = noteText, onValueChange = { noteText = it }, modifier = Modifier.fillMaxWidth(), placeholder = { Text(stringResource(R.string.floor_note_optional)) }) },
            confirmButton = { TextButton(onClick = { viewModel.saveCurrentFloor(noteText); noteText = ""; showSaveDialog = false }) { Text(stringResource(R.string.btn_save)) } },
            dismissButton = { TextButton(onClick = { noteText = ""; showSaveDialog = false }) { Text(stringResource(R.string.btn_cancel)) } })
    }

    // Add new record dialog
    if (showAddDialog) {
        AlertDialog(
            onDismissRequest = { showAddDialog = false },
            title = { Text(stringResource(R.string.floor_add_record)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = addName,
                        onValueChange = { addName = it },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text(stringResource(R.string.floor_record_name)) },
                        singleLine = true
                    )
                    OutlinedTextField(
                        value = addAltitude,
                        onValueChange = { addAltitude = it },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text(stringResource(R.string.floor_altitude)) },
                        singleLine = true
                    )
                    OutlinedTextField(
                        value = addFloor,
                        onValueChange = { addFloor = it },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text(stringResource(R.string.floor_number)) },
                        singleLine = true
                    )
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        val altitude = addAltitude.toDoubleOrNull() ?: 0.0
                        val floor = addFloor.toIntOrNull() ?: 0
                        viewModel.addRecord(addName, altitude, floor)
                        showAddDialog = false
                    },
                    enabled = addName.isNotBlank()
                ) { Text(stringResource(R.string.btn_save)) }
            },
            dismissButton = { TextButton(onClick = { showAddDialog = false }) { Text(stringResource(R.string.btn_cancel)) } }
        )
    }

    // Rename dialog
    if (showRenameDialog) {
        AlertDialog(
            onDismissRequest = { showRenameDialog = false },
            title = { Text(stringResource(R.string.floor_rename_record)) },
            text = {
                OutlinedTextField(
                    value = renameText,
                    onValueChange = { renameText = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(stringResource(R.string.floor_record_name)) },
                    singleLine = true
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        viewModel.renameRecord(editingRecordId, renameText)
                        showRenameDialog = false
                    },
                    enabled = renameText.isNotBlank()
                ) { Text(stringResource(R.string.btn_save)) }
            },
            dismissButton = { TextButton(onClick = { showRenameDialog = false }) { Text(stringResource(R.string.btn_cancel)) } }
        )
    }

    // Edit record dialog
    if (showEditDialog) {
        AlertDialog(
            onDismissRequest = { showEditDialog = false },
            title = { Text(stringResource(R.string.floor_edit_record)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = editName,
                        onValueChange = { editName = it },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text(stringResource(R.string.floor_record_name)) },
                        singleLine = true
                    )
                    OutlinedTextField(
                        value = editAltitude,
                        onValueChange = { editAltitude = it },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text(stringResource(R.string.floor_altitude)) },
                        singleLine = true
                    )
                    OutlinedTextField(
                        value = editFloor,
                        onValueChange = { editFloor = it },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text(stringResource(R.string.floor_number)) },
                        singleLine = true
                    )
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        val altitude = editAltitude.toDoubleOrNull() ?: 0.0
                        val floor = editFloor.toIntOrNull() ?: 0
                        viewModel.updateRecord(editingRecordId, editName, altitude, floor)
                        showEditDialog = false
                    },
                    enabled = editName.isNotBlank()
                ) { Text(stringResource(R.string.btn_save)) }
            },
            dismissButton = { TextButton(onClick = { showEditDialog = false }) { Text(stringResource(R.string.btn_cancel)) } }
        )
    }
}

private val languageOptions = listOf(
    "af" to "Afrikaans", "ar" to "Arabic", "az" to "Azerbaijani", "be" to "Belarusian",
    "bg" to "Bulgarian", "bs" to "Bosnian", "ca" to "Catalan", "cs" to "Czech",
    "cy" to "Welsh", "da" to "Danish", "de" to "German", "el" to "Greek",
    "en" to "English", "es" to "Spanish", "et" to "Estonian", "fa" to "Persian",
    "fi" to "Finnish", "fr" to "French", "gl" to "Galician", "he" to "Hebrew",
    "hi" to "Hindi", "hr" to "Croatian", "hu" to "Hungarian", "hy" to "Armenian",
    "id" to "Indonesian", "is" to "Icelandic", "it" to "Italian", "ja" to "Japanese",
    "kk" to "Kazakh", "kn" to "Kannada", "ko" to "Korean", "lt" to "Lithuanian",
    "lv" to "Latvian", "mi" to "Maori", "mk" to "Macedonian", "mr" to "Marathi",
    "ms" to "Malay", "ne" to "Nepali", "nl" to "Dutch", "no" to "Norwegian",
    "pl" to "Polish", "pt" to "Portuguese", "ro" to "Romanian", "ru" to "Russian",
    "sk" to "Slovak", "sl" to "Slovenian", "sr" to "Serbian", "sv" to "Swedish",
    "sw" to "Swahili", "ta" to "Tamil", "th" to "Thai", "tl" to "Filipino",
    "tr" to "Turkish", "uk" to "Ukrainian", "ur" to "Urdu", "vi" to "Vietnamese",
    "zh" to "Chinese"
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatScreen(viewModel: ChatViewModel = viewModel()) {
    val statusText by viewModel.statusText
    val isConnected by viewModel.isConnected
    val isConnecting by viewModel.isConnecting
    val transcript by viewModel.transcript
    val errorMessage by viewModel.errorMessage
    val mode by viewModel.selectedMode
    val langA by viewModel.languageA
    val langB by viewModel.languageB
    var expandedLangA by remember { mutableStateOf(false) }
    var expandedLangB by remember { mutableStateOf(false) }
    val context = LocalContext.current

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        TopAppBar(title = { Text(stringResource(R.string.tab_chat)) })
        Spacer(modifier = Modifier.height(12.dp))

        // Mode toggle
        Text(stringResource(R.string.chat_mode), style = MaterialTheme.typography.titleMedium)
        SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
            SegmentedButton(
                selected = mode == "chat",
                onClick = { viewModel.selectedMode.value = "chat" },
                shape = SegmentedButtonDefaults.itemShape(0, 2)
            ) { Text(stringResource(R.string.tab_chat)) }
            SegmentedButton(
                selected = mode == "interpreter",
                onClick = { viewModel.selectedMode.value = "interpreter" },
                shape = SegmentedButtonDefaults.itemShape(1, 2)
            ) { Text(stringResource(R.string.btn_interpreter)) }
        }

        // Language pickers (interpreter mode only)
        if (mode == "interpreter") {
            Spacer(modifier = Modifier.height(12.dp))
            Text(stringResource(R.string.chat_language_a), style = MaterialTheme.typography.titleSmall)
            Box {
                OutlinedButton(
                    onClick = { expandedLangA = true },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(languageOptions.firstOrNull { it.first == langA }?.second ?: langA)
                }
                DropdownMenu(expanded = expandedLangA, onDismissRequest = { expandedLangA = false }) {
                    languageOptions.forEach { (code, name) ->
                        DropdownMenuItem(
                            text = { Text(name) },
                            onClick = { viewModel.languageA.value = code; viewModel.persistLanguages(); expandedLangA = false }
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(8.dp))
            Text(stringResource(R.string.chat_language_b), style = MaterialTheme.typography.titleSmall)
            Box {
                OutlinedButton(
                    onClick = { expandedLangB = true },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(languageOptions.firstOrNull { it.first == langB }?.second ?: langB)
                }
                DropdownMenu(expanded = expandedLangB, onDismissRequest = { expandedLangB = false }) {
                    languageOptions.forEach { (code, name) ->
                        DropdownMenuItem(
                            text = { Text(name) },
                            onClick = { viewModel.languageB.value = code; viewModel.persistLanguages(); expandedLangB = false }
                        )
                    }
                }
            }

            if (langA == langB) {
                Spacer(modifier = Modifier.height(8.dp))
                Text(stringResource(R.string.label_choose_two_languages), color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium)
            }
        }

        Spacer(modifier = Modifier.height(12.dp))

        // Status
        Text(statusText, style = MaterialTheme.typography.bodyLarge)

        // Error
        if (errorMessage != null) {
            Spacer(modifier = Modifier.height(8.dp))
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer)
            ) {
                Text(
                    errorMessage ?: "",
                    modifier = Modifier.padding(12.dp),
                    color = MaterialTheme.colorScheme.onErrorContainer
                )
            }
        }

        // Transcript
        if (transcript.isNotEmpty()) {
            Spacer(modifier = Modifier.height(8.dp))
            Card(modifier = Modifier.fillMaxWidth()) {
                Text(transcript, modifier = Modifier.padding(12.dp))
            }
        }

        Spacer(modifier = Modifier.weight(1f))

        // Start / Stop
        Button(
            onClick = {
                if (isConnected || isConnecting) {
                    viewModel.stop()
                } else {
                    if (!OAuthService.isSignedIn(context)) {
                        viewModel.errorMessage.value = "Sign in with ChatGPT from Details Recognition first."
                    } else {
                        viewModel.start()
                    }
                }
            },
            modifier = Modifier.fillMaxWidth(),
            enabled = !isConnecting && !(mode == "interpreter" && langA == langB),
            colors = if (isConnected) ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error)
            else ButtonDefaults.buttonColors()
        ) {
            Text(
                when {
                    isConnecting -> stringResource(R.string.chat_connecting)
                    isConnected -> stringResource(R.string.btn_stop)
                    else -> stringResource(R.string.btn_start_voice_chat)
                }
            )
        }
    }
}
