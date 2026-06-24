package com.eyepal.app.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
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

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        TopAppBar(title = { Text("Details Recognition") })

        Spacer(modifier = Modifier.height(16.dp))

        if (!isSignedIn) {
            Text("Sign in with ChatGPT to use scene description.", style = MaterialTheme.typography.bodyMedium)
            Spacer(modifier = Modifier.height(8.dp))
            Button(onClick = { viewModel.signIn() }) {
                Text("Sign In with ChatGPT")
            }
        } else {
            Text(statusText, style = MaterialTheme.typography.bodyLarge)

            if (descriptionText.isNotEmpty()) {
                Spacer(modifier = Modifier.height(8.dp))
                Card(modifier = Modifier.fillMaxWidth()) {
                    Text(descriptionText, modifier = Modifier.padding(16.dp))
                }

                Spacer(modifier = Modifier.height(8.dp))
                Row(modifier = Modifier.fillMaxWidth()) {
                    OutlinedTextField(
                        value = followUpQuestion,
                        onValueChange = { viewModel.followUpQuestion.value = it },
                        modifier = Modifier.weight(1f),
                        placeholder = { Text("Ask a follow-up") }
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Button(
                        onClick = { viewModel.submitFollowUp() },
                        enabled = !isProcessing && followUpQuestion.isNotBlank()
                    ) {
                        Text("Send")
                    }
                }
            }

            Spacer(modifier = Modifier.weight(1f))

            Button(
                onClick = { viewModel.capturePhoto() },
                modifier = Modifier.fillMaxWidth(),
                enabled = !isProcessing
            ) {
                Text(if (isProcessing) "Working..." else "Take Photo")
            }
        }
    }
}
