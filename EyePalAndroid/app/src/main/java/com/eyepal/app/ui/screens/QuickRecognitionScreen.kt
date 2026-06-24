package com.eyepal.app.ui.screens

import android.view.ViewGroup
import androidx.camera.view.PreviewView
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.viewmodel.compose.viewModel
import com.eyepal.app.viewmodels.QuickRecognitionViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun QuickRecognitionScreen(viewModel: QuickRecognitionViewModel = viewModel()) {
    val statusText by viewModel.statusText
    val responseText by viewModel.responseText
    val isProcessing by viewModel.isProcessing
    val errorMessage by viewModel.errorMessage
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current

    DisposableEffect(Unit) {
        onDispose { viewModel.stopCamera() }
    }

    Column(modifier = Modifier.fillMaxSize()) {
        AndroidView(
            factory = { ctx ->
                PreviewView(ctx).apply {
                    layoutParams = ViewGroup.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT
                    )
                    scaleType = PreviewView.ScaleType.FILL_CENTER
                    implementationMode = PreviewView.ImplementationMode.COMPATIBLE
                }
            },
            modifier = Modifier.fillMaxWidth().weight(1f),
            update = { preview ->
                viewModel.startCamera(preview)
            }
        )

        Card(
            modifier = Modifier.fillMaxWidth().padding(16.dp),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.9f))
        ) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text(statusText, style = MaterialTheme.typography.bodyLarge)

                if (responseText.isNotEmpty()) {
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(responseText, style = MaterialTheme.typography.bodyMedium)
                }

                Spacer(modifier = Modifier.height(12.dp))

                Button(
                    onClick = { viewModel.takePhoto() },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !isProcessing
                ) {
                    Text(if (isProcessing) "Working..." else "Take Photo")
                }
            }
        }
    }

    errorMessage?.let {
        LaunchedEffect(it) { viewModel.clearError() }
    }
}
