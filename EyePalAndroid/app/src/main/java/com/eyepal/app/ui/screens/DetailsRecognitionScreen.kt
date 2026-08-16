package com.eyepal.app.ui.screens

import android.view.ViewGroup
import androidx.camera.view.PreviewView
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.compose.ui.graphics.asImageBitmap
import com.eyepal.app.R
import com.eyepal.app.EyePalApplication
import com.eyepal.app.viewmodels.DetailsRecognitionViewModel
import com.eyepal.app.viewmodels.RecognitionActionControlStyle

private fun defaultPresets() = listOf(
    Triple("Custom", "For a blind user, first read visible text exactly. Then describe people, objects, layout, and orientation cues. Be concise and specific. Do not use markdown or double asterisks.", "Custom"),
    Triple("Product", "Describe the main product in this image with 1 or 2 sentences, including its brand, name, packaging details, and primary function.", "Product"),
    Triple("Dish", "Describe the dish layout in detail for a blind user, including portions, relative positions, and likely ingredients.", "Dish"),
    Triple("Short Text", "Read the visible short text and numbers exactly, and mention where they appear in the scene.", "Short Text")
)

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun DetailsRecognitionScreen(viewModel: DetailsRecognitionViewModel = viewModel()) {
    val context = LocalContext.current
    val settings = remember { (context.applicationContext as EyePalApplication).container.settingsRepository }
    val savedButtonsJson by settings.detailButtons.collectAsState(initial = "")
    val presets = remember(savedButtonsJson) {
        if (savedButtonsJson.isNotEmpty()) {
            try {
                val arr = org.json.JSONArray(savedButtonsJson)
                (0 until arr.length()).map { i ->
                    val obj = arr.getJSONObject(i)
                    Triple(
                        obj.optString("name", context.getString(R.string.label_button, i + 1)),
                        obj.optString("prompt", context.getString(R.string.describe_scene)),
                        obj.optString("type", "Custom")
                    )
                }.take(4)
            } catch (e: Exception) { defaultPresets() }
        } else defaultPresets()
    }

    val statusText by viewModel.statusText
    val descriptionText by viewModel.descriptionText
    val followUpQuestion by viewModel.followUpQuestion
    val isProcessing by viewModel.isProcessing
    val isSignedIn by viewModel.isSignedIn
    val showOAuthLogin by viewModel.showOAuthLogin
    var showPromptDialog by remember { mutableStateOf(false) }
    var promptText by remember { mutableStateOf("") }
    val announcer = remember { (context.applicationContext as EyePalApplication).container.announcer }
    val controlStyle by settings.detailsActionControlStyle.collectAsState(initial = com.eyepal.app.config.Defaults.DETAILS_ACTION_CONTROL_STYLE)
    val actions = remember(presets) { listOf(context.getString(R.string.btn_take_photo)) + presets.map { it.first } }
    var selectedActionIndex by remember { mutableIntStateOf(0) }

    DisposableEffect(Unit) { onDispose { viewModel.stopCamera() } }

    LaunchedEffect(Unit) { viewModel.startCamera() }

    if (showOAuthLogin) {
        OAuthLoginScreen(
            onSuccess = { viewModel.onOAuthSuccess() },
            onDismiss = { viewModel.onOAuthDismiss() }
        )
        return
    }

    Column(modifier = Modifier.fillMaxSize()) {
        AndroidView(factory = { ctx -> PreviewView(ctx).apply { layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT); scaleType = PreviewView.ScaleType.FILL_CENTER; implementationMode = PreviewView.ImplementationMode.COMPATIBLE } },
            modifier = Modifier.fillMaxWidth().weight(1f), update = { preview -> viewModel.startCamera(preview) })

        Card(modifier = Modifier.fillMaxWidth().padding(16.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.9f))) {
                Column(modifier = Modifier.padding(16.dp)) {
                if (!isSignedIn) {
                    Text(stringResource(R.string.settings_scene_desc_hint))
                    Spacer(modifier = Modifier.height(8.dp))
                    val errorMsg by viewModel.errorMessage
                    if (errorMsg != null) {
                        Text(errorMsg!!, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                        Spacer(modifier = Modifier.height(8.dp))
                    }
                    Button(onClick = { viewModel.signIn() }) { Text(stringResource(R.string.btn_sign_in_chatgpt)) }
                } else {
                    Text(statusText, style = MaterialTheme.typography.bodyLarge)

                    viewModel.capturedImage.value?.let { bitmap ->
                        Spacer(modifier = Modifier.height(8.dp))
                        Image(bitmap = bitmap.asImageBitmap(), contentDescription = stringResource(R.string.captured_image),
                            modifier = Modifier.fillMaxWidth().height(150.dp).clip(RoundedCornerShape(8.dp)), contentScale = ContentScale.Crop)
                        Spacer(modifier = Modifier.height(4.dp))
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            OutlinedButton(onClick = { viewModel.retakePhoto() }, modifier = Modifier.weight(1f), enabled = !isProcessing) { Text(stringResource(R.string.retake)) }
                            OutlinedButton(onClick = { viewModel.resendFullRes() }, modifier = Modifier.weight(1f), enabled = !isProcessing) { Text(stringResource(R.string.full_res)) }
                        }
                    }

                    if (descriptionText.isNotEmpty()) {
                        Spacer(modifier = Modifier.height(8.dp))
                        Card(modifier = Modifier.fillMaxWidth()) { Text(descriptionText, modifier = Modifier.padding(12.dp)) }
                        Spacer(modifier = Modifier.height(8.dp))
                        Row(modifier = Modifier.fillMaxWidth()) {
                            OutlinedTextField(value = followUpQuestion, onValueChange = { viewModel.followUpQuestion.value = it }, modifier = Modifier.weight(1f), placeholder = { Text(stringResource(R.string.label_ask_follow_up)) }, singleLine = true)
                            Spacer(modifier = Modifier.width(8.dp))
                            Button(onClick = { viewModel.submitFollowUp() }, enabled = !isProcessing && followUpQuestion.isNotBlank()) { Text(stringResource(R.string.btn_send)) }
                        }
                    }

                    Spacer(modifier = Modifier.height(12.dp))

                    if (RecognitionActionControlStyle.fromValue(controlStyle) == RecognitionActionControlStyle.SINGLE_ADJUSTABLE_CONTROL) {
                        val clampedIndex = selectedActionIndex.coerceIn(0, (actions.size - 1).coerceAtLeast(0))
                        val selectedLabel = if (actions.isEmpty()) stringResource(R.string.btn_take_photo) else actions[clampedIndex]
                        var dragAccumulator by remember { mutableFloatStateOf(0f) }
                        val dragThreshold = 90f
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(MaterialTheme.shapes.medium)
                                .background(MaterialTheme.colorScheme.primary)
                                .combinedClickable(
                                    onClick = {
                                        when (clampedIndex) {
                                            0 -> viewModel.capturePhoto()
                                            else -> viewModel.capturePresetPhoto(presets[clampedIndex - 1].second)
                                        }
                                    },
                                    onLongClick = {
                                        if (clampedIndex == 0) showPromptDialog = true
                                    }
                                )
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
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                text = if (isProcessing) stringResource(R.string.label_working) else selectedLabel,
                                modifier = Modifier.padding(16.dp),
                                color = MaterialTheme.colorScheme.onPrimary,
                                style = MaterialTheme.typography.labelLarge
                            )
                        }
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(stringResource(R.string.details_swipe_hint), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.outline)
                    } else {
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Button(onClick = { viewModel.capturePhoto() }, modifier = Modifier.weight(1f), enabled = !isProcessing) { Text(if (isProcessing) stringResource(R.string.label_working) else stringResource(R.string.btn_take_photo)) }
                            OutlinedButton(onClick = { showPromptDialog = true }, modifier = Modifier.weight(1f), enabled = !isProcessing) { Text(stringResource(R.string.btn_custom_prompt)) }
                        }

                        Spacer(modifier = Modifier.height(8.dp))
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            presets.forEach { (name, prompt, _) ->
                                OutlinedButton(onClick = { viewModel.capturePresetPhoto(prompt) }, modifier = Modifier.weight(1f), enabled = !isProcessing) { Text(name) }
                            }
                        }
                    }
                }
            }
        }
    }

    if (showPromptDialog) {
        AlertDialog(onDismissRequest = { showPromptDialog = false }, title = { Text(stringResource(R.string.label_custom_prompt_title)) },
            text = { OutlinedTextField(value = promptText, onValueChange = { promptText = it }, modifier = Modifier.fillMaxWidth(), placeholder = { Text(stringResource(R.string.label_custom_prompt_hint)) }) },
            confirmButton = { TextButton(onClick = { viewModel.capturePresetPhoto(promptText); promptText = ""; showPromptDialog = false }) { Text(stringResource(R.string.btn_send)) } },
            dismissButton = { TextButton(onClick = { promptText = ""; showPromptDialog = false }) { Text(stringResource(R.string.btn_cancel)) } })
    }
}
