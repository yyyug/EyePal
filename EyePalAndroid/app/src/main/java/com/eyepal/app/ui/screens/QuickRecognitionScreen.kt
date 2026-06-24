package com.eyepal.app.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.eyepal.app.viewmodels.QuickRecognitionViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun QuickRecognitionScreen(viewModel: QuickRecognitionViewModel = viewModel()) {
    val statusText by viewModel.statusText
    val responseText by viewModel.responseText
    val isProcessing by viewModel.isProcessing
    val capturedImage by viewModel.capturedImage
    val errorMessage by viewModel.errorMessage

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        TopAppBar(title = { Text("Quick Recognition") })

        Spacer(modifier = Modifier.height(16.dp))

        Text(statusText, style = MaterialTheme.typography.bodyLarge)

        Spacer(modifier = Modifier.height(8.dp))

        if (capturedImage != null) {
            capturedImage?.let {
                Image(bitmap = it, contentDescription = "Captured", modifier = Modifier.fillMaxWidth().height(200.dp))
            }
        }

        if (responseText.isNotEmpty()) {
            Spacer(modifier = Modifier.height(8.dp))
            Card(modifier = Modifier.fillMaxWidth()) {
                Text(responseText, modifier = Modifier.padding(16.dp))
            }
        }

        Spacer(modifier = Modifier.weight(1f))

        Button(
            onClick = { viewModel.takePhoto() },
            modifier = Modifier.fillMaxWidth(),
            enabled = !isProcessing
        ) {
            Text(if (isProcessing) "Working..." else "Take Photo")
        }
    }

    errorMessage?.let {
        LaunchedEffect(it) {
            viewModel.clearError()
        }
    }
}
