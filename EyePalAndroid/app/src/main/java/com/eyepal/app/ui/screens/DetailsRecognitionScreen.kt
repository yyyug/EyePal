package com.eyepal.app.ui.screens

import android.view.ViewGroup
import androidx.camera.view.PreviewView
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.viewmodel.compose.viewModel
import com.eyepal.app.viewmodels.DetailsRecognitionViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DetailsRecognitionScreen(viewModel: DetailsRecognitionViewModel = viewModel()) {
    val statusText by viewModel.statusText
    val descriptionText by viewModel.descriptionText
    val followUpQuestion by viewModel.followUpQuestion
    val isProcessing by viewModel.isProcessing
    val isSignedIn by viewModel.isSignedIn

    DisposableEffect(Unit) { onDispose { viewModel.stopCamera() } }

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
            update = { preview -> viewModel.startCamera(preview) }
        )

        Card(
            modifier = Modifier.fillMaxWidth().padding(16.dp),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.9f))
        ) {
            Column(modifier = Modifier.padding(16.dp)) {
                if (!isSignedIn) {
                    Text("Sign in with ChatGPT to use scene description.")
                    Spacer(modifier = Modifier.height(8.dp))
                    Button(onClick = { viewModel.signIn() }) { Text("Sign In with ChatGPT") }
                } else {
                    Text(statusText, style = MaterialTheme.typography.bodyLarge)

                    if (descriptionText.isNotEmpty()) {
                        Spacer(modifier = Modifier.height(8.dp))
                        Card(modifier = Modifier.fillMaxWidth()) {
                            Text(descriptionText, modifier = Modifier.padding(12.dp))
                        }
                        Spacer(modifier = Modifier.height(8.dp))
                        Row(modifier = Modifier.fillMaxWidth()) {
                            OutlinedTextField(
                                value = followUpQuestion,
                                onValueChange = { viewModel.followUpQuestion.value = it },
                                modifier = Modifier.weight(1f),
                                placeholder = { Text("Ask follow-up") },
                                singleLine = true
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            Button(
                                onClick = { viewModel.submitFollowUp() },
                                enabled = !isProcessing && followUpQuestion.isNotBlank()
                            ) { Text("Send") }
                        }
                    }

                    Spacer(modifier = Modifier.height(12.dp))
                    Button(
                        onClick = { viewModel.capturePhoto() },
                        modifier = Modifier.fillMaxWidth(),
                        enabled = !isProcessing
                    ) { Text(if (isProcessing) "Working..." else "Take Photo") }
                }
            }
        }
    }
}
