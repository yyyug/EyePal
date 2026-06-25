package com.eyepal.app.ui.screens

import android.view.ViewGroup
import androidx.camera.view.PreviewView
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.viewmodel.compose.viewModel
import com.eyepal.app.viewmodels.QuickRecognitionViewModel

data class QuickPreset(val title: String, val icon: String, val prompt: String)

val quickPresets = listOf(
    QuickPreset("Product", "📦", "Describe the main product with brand, name and function"),
    QuickPreset("Dish", "🍽", "Describe the food layout on the plate using clock positions"),
    QuickPreset("Short Text", "🔍", "Read the visible text in the image"),
    QuickPreset("Custom", "⚙", "")
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun QuickRecognitionScreen(viewModel: QuickRecognitionViewModel = viewModel()) {
    val statusText by viewModel.statusText
    val responseText by viewModel.responseText
    val isProcessing by viewModel.isProcessing
    val isContinuous by viewModel.isContinuousCapture
    val errorMessage by viewModel.errorMessage
    val capturedImage by viewModel.capturedImage
    val lifecycleOwner = LocalLifecycleOwner.current

    DisposableEffect(Unit) { onDispose { viewModel.stopContinuous(); viewModel.stopCamera() } }

    Column(modifier = Modifier.fillMaxSize()) {
        AndroidView(
            factory = { ctx -> PreviewView(ctx).apply { layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT); scaleType = PreviewView.ScaleType.FILL_CENTER; implementationMode = PreviewView.ImplementationMode.COMPATIBLE } },
            modifier = Modifier.fillMaxWidth().weight(1f),
            update = { preview -> viewModel.startCamera(preview) }
        )

        Card(modifier = Modifier.fillMaxWidth().padding(16.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.9f))) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text(statusText, style = MaterialTheme.typography.bodyLarge)

                if (responseText.isNotEmpty()) {
                    Spacer(modifier = Modifier.height(8.dp))
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Text(responseText, modifier = Modifier.padding(12.dp), style = MaterialTheme.typography.bodyMedium)
                    }
                }

                Spacer(modifier = Modifier.height(12.dp))

                Button(onClick = { viewModel.takePhoto() }, modifier = Modifier.fillMaxWidth(), enabled = !isProcessing && !isContinuous) {
                    Text(if (isProcessing) "Working..." else "Take Photo")
                }

                Spacer(modifier = Modifier.height(8.dp))

                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    quickPresets.forEach { preset ->
                        OutlinedButton(onClick = { viewModel.takePresetPhoto(preset.prompt) }, modifier = Modifier.weight(1f), enabled = !isProcessing && !isContinuous) {
                            Text(preset.title, textAlign = TextAlign.Center, style = MaterialTheme.typography.labelSmall)
                        }
                    }
                }

                Spacer(modifier = Modifier.height(8.dp))

                Button(onClick = { if (isContinuous) viewModel.stopContinuous() else viewModel.startContinuousMode() }, modifier = Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(containerColor = if (isContinuous) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.secondary)) {
                    Text(if (isContinuous) "Stop" else "Continuous")
                }
            }
        }
    }

    errorMessage?.let { LaunchedEffect(it) { viewModel.clearError() } }
}
