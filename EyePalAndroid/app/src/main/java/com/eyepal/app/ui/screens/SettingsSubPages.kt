package com.eyepal.app.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.eyepal.app.services.OAuthService

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DetailsRecognitionSettingsScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val isSignedIn = remember { mutableStateOf(OAuthService.isSignedIn(context)) }
    var showSignOutDialog by remember { mutableStateOf(false) }

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        TopAppBar(title = { Text("Details Recognition") }, navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") } })
        Spacer(modifier = Modifier.height(16.dp))

        Text("ChatGPT Account", style = MaterialTheme.typography.titleMedium)
        Spacer(modifier = Modifier.height(8.dp))
        if (isSignedIn.value) {
            Text("Signed in", color = MaterialTheme.colorScheme.primary)
            Spacer(modifier = Modifier.height(8.dp))
            Button(onClick = { showSignOutDialog = true }) { Text("Sign Out") }
        } else {
            Text("Not signed in", color = MaterialTheme.colorScheme.outline)
            Spacer(modifier = Modifier.height(8.dp))
            Button(onClick = {
                val intent = OAuthService.getAuthIntent(context)
                context.startActivity(intent)
            }) { Text("Sign In with ChatGPT") }
        }

        Spacer(modifier = Modifier.height(24.dp))
        Text("Scene Description", style = MaterialTheme.typography.titleMedium)
        Spacer(modifier = Modifier.height(8.dp))
        Text("Uses OpenAI API for detailed scene descriptions. Sign in with ChatGPT to enable.", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.outline)
    }

    if (showSignOutDialog) {
        AlertDialog(onDismissRequest = { showSignOutDialog = false }, title = { Text("Sign Out") },
            text = { Text("Are you sure you want to sign out of ChatGPT?") },
            confirmButton = { TextButton(onClick = { OAuthService.signOut(context); isSignedIn.value = false; showSignOutDialog = false }) { Text("Sign Out", color = MaterialTheme.colorScheme.error) } },
            dismissButton = { TextButton(onClick = { showSignOutDialog = false }) { Text("Cancel") } })
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun QuickRecognitionSettingsScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val prefs = remember { context.getSharedPreferences("settings", 0) }
    var apiKey by remember { mutableStateOf(prefs.getString("moondream_api_key", "") ?: "") }

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        TopAppBar(title = { Text("Quick Recognition") }, navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") } })
        Spacer(modifier = Modifier.height(16.dp))

        Text("Moondream API", style = MaterialTheme.typography.titleMedium)
        Spacer(modifier = Modifier.height(8.dp))
        OutlinedTextField(value = apiKey, onValueChange = { apiKey = it; prefs.edit().putString("moondream_api_key", it).apply() }, modifier = Modifier.fillMaxWidth(), label = { Text("API Key") }, singleLine = true)
        Spacer(modifier = Modifier.height(8.dp))
        Text("Get your API key from moondream.ai", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.outline)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TextRecognitionSettingsScreen(onBack: () -> Unit) {
    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        TopAppBar(title = { Text("Text Recognition") }, navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") } })
        Spacer(modifier = Modifier.height(16.dp))
        Text("OCR Engine", style = MaterialTheme.typography.titleMedium)
        Spacer(modifier = Modifier.height(8.dp))
        Text("Powered by Google MLKit. Supports Latin, Chinese, Japanese, and Korean scripts.", style = MaterialTheme.typography.bodyMedium)
        Spacer(modifier = Modifier.height(16.dp))
        Text("Features", style = MaterialTheme.typography.titleMedium)
        Spacer(modifier = Modifier.height(8.dp))
        Text("• Real-time text recognition from camera\n• Multi-language support\n• Continuous recognition mode", style = MaterialTheme.typography.bodyMedium)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FacesSettingsScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val prefs = remember { context.getSharedPreferences("settings", 0) }
    var threshold by remember { mutableFloatStateOf(prefs.getFloat("face_match_threshold", 0.82f)) }
    var suggestUnknown by remember { mutableStateOf(prefs.getBoolean("suggest_unknown_faces", true)) }

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        TopAppBar(title = { Text("Faces") }, navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") } })
        Spacer(modifier = Modifier.height(16.dp))

        Text("Match Sensitivity", style = MaterialTheme.typography.titleMedium)
        Text("${String.format("%.0f", threshold * 100)}%", style = MaterialTheme.typography.bodyLarge)
        Slider(value = threshold, onValueChange = { threshold = it; prefs.edit().putFloat("face_match_threshold", it).apply() }, valueRange = 0.78f..0.98f, steps = 19)
        Spacer(modifier = Modifier.height(16.dp))

        Text("Suggest Unknown Faces", style = MaterialTheme.typography.titleMedium)
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
            Text("Show prompt when unknown face detected", modifier = Modifier.weight(1f))
            Switch(checked = suggestUnknown, onCheckedChange = { suggestUnknown = it; prefs.edit().putBoolean("suggest_unknown_faces", it).apply() })
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LyricPrompterSettingsScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val prefs = remember { context.getSharedPreferences("settings", 0) }
    var provider by remember { mutableStateOf(prefs.getString("lyric_llm_provider", "CODEX") ?: "CODEX") }
    var modelID by remember { mutableStateOf(prefs.getString("lyric_model_id", "gpt-5.4-mini") ?: "gpt-5.4-mini") }
    var apiKey by remember { mutableStateOf(prefs.getString("lyric_api_key", "") ?: "") }
    var advanceOffset by remember { mutableFloatStateOf(prefs.getFloat("lyric_advance_offset", 0f)) }

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        TopAppBar(title = { Text("Lyric Prompter") }, navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") } })
        Spacer(modifier = Modifier.height(16.dp))

        Text("Playback", style = MaterialTheme.typography.titleMedium)
        Text("Advance offset: ${String.format("%.1f", advanceOffset)}s")
        Slider(value = advanceOffset, onValueChange = { advanceOffset = it; prefs.edit().putFloat("lyric_advance_offset", it).apply() }, valueRange = 0f..5f, steps = 9)
        Spacer(modifier = Modifier.height(16.dp))

        Text("AI Provider", style = MaterialTheme.typography.titleMedium)
        SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
            listOf("CODEX", "GEMINI", "OPENAI").forEachIndexed { index, name ->
                SegmentedButton(selected = provider == name, onClick = { provider = name; prefs.edit().putString("lyric_llm_provider", name).apply() }, shape = SegmentedButtonDefaults.itemShape(index, 3)) { Text(name) }
            }
        }
        Spacer(modifier = Modifier.height(8.dp))
        OutlinedTextField(value = modelID, onValueChange = { modelID = it; prefs.edit().putString("lyric_model_id", it).apply() }, modifier = Modifier.fillMaxWidth(), label = { Text("Model ID") }, singleLine = true)
        if (provider != "CODEX") {
            Spacer(modifier = Modifier.height(8.dp))
            OutlinedTextField(value = apiKey, onValueChange = { apiKey = it; prefs.edit().putString("lyric_api_key", it).apply() }, modifier = Modifier.fillMaxWidth(), label = { Text("API Key") }, singleLine = true)
        }
    }
}
