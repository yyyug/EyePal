package com.eyepal.app.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.eyepal.app.data.SettingsRepository
import com.eyepal.app.models.AppFeature
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    onNavigateToFeatureOrder: () -> Unit,
    onNavigateToGoogleGlass: () -> Unit,
    onBack: () -> Unit
) {
    val context = LocalContext.current
    val settings = remember { SettingsRepository(context) }
    val threshold by settings.faceMatchThreshold.collectAsState(initial = 0.82f)
    val margin by settings.faceMatchMargin.collectAsState(initial = 0.015f)
    val lyricProvider by settings.lyricLLMProvider.collectAsState(initial = "CODEX")
    val lyricAdvance by settings.lyricAdvanceOffset.collectAsState(initial = 0.0)

    val scope = rememberCoroutineScope()
    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        TopAppBar(title = { Text("Settings") })

        Text("Feature Order", modifier = Modifier.clickable { onNavigateToFeatureOrder() }.padding(vertical = 12.dp))

        HorizontalDivider()

        Text("Face Recognition", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(vertical = 8.dp))
        Text("Match sensitivity: ${String.format("%.0f", threshold * 100)}%")
        Slider(value = threshold, onValueChange = { scope.launch { settings.setFaceMatchThreshold(it) } }, valueRange = 0.78f..0.98f, steps = 19)

        Text("Top match margin: ${String.format("%.3f", margin)}")
        Slider(value = margin.toFloat(), onValueChange = { scope.launch { settings.setFaceMatchMargin(it.toDouble()) } }, valueRange = 0.005f..0.05f, steps = 8)

        HorizontalDivider()

        Text("Lyric Prompter", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(vertical = 8.dp))
        Text("LLM Provider: $lyricProvider")
        Text("Advance offset: ${String.format("%.1f", lyricAdvance)}s")

        HorizontalDivider()

        Text("Google Glass", style = MaterialTheme.typography.titleMedium, modifier = Modifier.clickable { onNavigateToGoogleGlass() }.padding(vertical = 12.dp))
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FeatureOrderScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val settings = remember { SettingsRepository(context) }
    val featureOrder by settings.featureOrder.collectAsState(initial = AppFeature.defaultOrder.map { it.name })

    val features = remember(featureOrder) {
        featureOrder.mapNotNull { name -> AppFeature.entries.find { it.name == name } }
    }

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        TopAppBar(title = { Text("Feature Order") })
        Spacer(modifier = Modifier.height(8.dp))

        features.forEach { feature ->
            ListItem(
                headlineContent = { Text(feature.displayName) },
                supportingContent = {
                    Column {
                        Text(feature.description, style = MaterialTheme.typography.bodySmall)
                        Text("Tab", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.outline)
                    }
                }
            )
            HorizontalDivider()
        }
    }
}
