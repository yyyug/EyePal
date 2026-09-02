package com.eyepal.app.ui.screens

import android.view.ViewGroup
import android.content.Intent
import android.net.Uri
import androidx.camera.view.PreviewView
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.viewmodel.compose.viewModel
import com.eyepal.app.R
import com.eyepal.app.EyePalApplication
import com.eyepal.app.services.GemmaModelKind
import com.eyepal.app.viewmodels.QuickRecognitionViewModel
import com.eyepal.app.viewmodels.RecognitionActionControlStyle

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun QuickRecognitionScreen(viewModel: QuickRecognitionViewModel = viewModel()) {
    val statusText by viewModel.statusText
    val responseText by viewModel.responseText
    val isProcessing by viewModel.isProcessing
    val isContinuous by viewModel.isContinuousCapture
    val errorMessage by viewModel.errorMessage
    val capturedImage by viewModel.capturedImage
    val context = LocalContext.current
    val currentPresets by viewModel.presets
    val settings = remember { (context.applicationContext as EyePalApplication).container.settingsRepository }
    val controlStyle by settings.quickActionControlStyle.collectAsState(initial = com.eyepal.app.config.Defaults.QUICK_ACTION_CONTROL_STYLE)
    val announcer = remember { (context.applicationContext as EyePalApplication).container.announcer }

    val actions = remember(currentPresets) { listOf(context.getString(R.string.btn_take_photo)) + currentPresets.map { it.name } }
    var selectedActionIndex by remember { mutableIntStateOf(0) }

    DisposableEffect(Unit) { onDispose { viewModel.stopContinuous(); viewModel.stopCamera() } }

    LaunchedEffect(Unit) { viewModel.startCamera() }

    Column(modifier = Modifier.fillMaxSize()) {
        AndroidView(
            factory = { ctx -> PreviewView(ctx).apply { layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT); scaleType = PreviewView.ScaleType.FILL_CENTER; implementationMode = PreviewView.ImplementationMode.COMPATIBLE } },
            modifier = Modifier.fillMaxWidth().weight(1f),
            update = { preview -> viewModel.startCamera(preview) }
        )

        Card(modifier = Modifier.fillMaxWidth().padding(16.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.9f))) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text(statusText, style = MaterialTheme.typography.bodyLarge)

                if (viewModel.quickModelProvider.value == "gemma" && !viewModel.gemmaCanRunOffline()) {
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(stringResource(R.string.quick_gemma_not_downloaded), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.outline)
                    TextButton(onClick = {
                        viewModel.downloadModel(viewModel.selectedGemmaKind() ?: GemmaModelKind.E2B)
                    }) {
                        Text(stringResource(R.string.gemma_action_download))
                    }
                } else if (viewModel.quickModelProvider.value == "moondream" && viewModel.apiKey.value.isBlank()) {
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(stringResource(R.string.quick_no_api_key), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.outline)
                    TextButton(onClick = {
                        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://moondream.ai/")))
                    }) {
                        Text(stringResource(R.string.quick_signup_api_key))
                    }
                }

                if (responseText.isNotEmpty()) {
                    Spacer(modifier = Modifier.height(8.dp))
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Text(responseText, modifier = Modifier.padding(12.dp), style = MaterialTheme.typography.bodyMedium)
                    }
                }

                Spacer(modifier = Modifier.height(12.dp))

                if (RecognitionActionControlStyle.fromValue(controlStyle) == RecognitionActionControlStyle.SINGLE_ADJUSTABLE_CONTROL) {
                    val clampedIndex = selectedActionIndex.coerceIn(0, (actions.size - 1).coerceAtLeast(0))
                    val selectedLabel = if (actions.isEmpty()) context.getString(R.string.btn_take_photo) else actions[clampedIndex]
                    var dragAccumulator by remember { mutableFloatStateOf(0f) }
                    val dragThreshold = 90f
                    Button(
                        onClick = {
                            when (clampedIndex) {
                                0 -> viewModel.takePhoto()
                                else -> viewModel.takePresetPhoto(currentPresets[clampedIndex - 1].prompt)
                            }
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .pointerInput(actions.size) {
                                detectVerticalDragGestures(
                                    onDragEnd = { dragAccumulator = 0f },
                                    onVerticalDrag = { change, dragAmount ->
                                        change.consume()
                                        dragAccumulator += dragAmount
                                        val maxIndex = (actions.size - 1).coerceAtLeast(0)
                                        while (dragAccumulator > dragThreshold && selectedActionIndex < maxIndex) {
                                            dragAccumulator -= dragThreshold
                                            selectedActionIndex++
                                            announcer.announce(actions[selectedActionIndex])
                                        }
                                        while (dragAccumulator < -dragThreshold && selectedActionIndex > 0) {
                                            dragAccumulator += dragThreshold
                                            selectedActionIndex--
                                            announcer.announce(actions[selectedActionIndex])
                                        }
                                    }
                                )
                            },
                        enabled = !isProcessing && !isContinuous
                    ) {
                        Text(if (isProcessing) stringResource(R.string.status_processing) else selectedLabel, modifier = Modifier.padding(vertical = 4.dp))
                    }
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(stringResource(R.string.quick_swipe_hint), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.outline)
                } else {
                    Button(onClick = { viewModel.takePhoto() }, modifier = Modifier.fillMaxWidth(), enabled = !isProcessing && !isContinuous) {
                        Text(if (isProcessing) stringResource(R.string.status_processing) else stringResource(R.string.btn_take_photo))
                    }

                    Spacer(modifier = Modifier.height(8.dp))

                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        currentPresets.forEach { preset ->
                            OutlinedButton(onClick = { viewModel.takePresetPhoto(preset.prompt) }, modifier = Modifier.weight(1f), enabled = !isProcessing && !isContinuous) {
                                Text(preset.name, textAlign = TextAlign.Center, style = MaterialTheme.typography.labelSmall)
                            }
                        }
                    }
                }

                Spacer(modifier = Modifier.height(8.dp))

                Button(onClick = { if (isContinuous) viewModel.stopContinuous() else viewModel.startContinuousMode() }, modifier = Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(containerColor = if (isContinuous) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.secondary)) {
                    Text(if (isContinuous) stringResource(R.string.btn_stop) else stringResource(R.string.btn_continuous))
                }
            }
        }
    }

    errorMessage?.let { LaunchedEffect(it) { viewModel.clearError() } }
}