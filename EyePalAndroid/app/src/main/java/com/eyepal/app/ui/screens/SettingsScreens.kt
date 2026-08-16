package com.eyepal.app.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import androidx.navigation.NavController
import com.eyepal.app.R
import com.eyepal.app.data.SettingsRepository
import com.eyepal.app.models.AppFeature

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    onNavigateToFeatureOrder: () -> Unit,
    onNavigateToGoogleGlass: () -> Unit,
    onNavigateToDetailsSettings: () -> Unit = {},
    onNavigateToQuickSettings: () -> Unit = {},
    onNavigateToTextSettings: () -> Unit = {},
    onNavigateToFacesSettings: () -> Unit = {},
    onNavigateToLyricsSettings: () -> Unit = {},
    onBack: () -> Unit
) {
    LazyColumn(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        item {
            TopAppBar(title = { Text(stringResource(R.string.tab_settings)) })
        }
        item {
            Text(stringResource(R.string.tab_feature_order), modifier = Modifier.clickable { onNavigateToFeatureOrder() }.padding(vertical = 12.dp))
        }
        item { HorizontalDivider() }
        item {
            Text(stringResource(R.string.settings_features), style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(vertical = 8.dp))
            Text(stringResource(R.string.settings_details_recognition), modifier = Modifier.clickable { onNavigateToDetailsSettings() }.padding(vertical = 8.dp))
            Text(stringResource(R.string.settings_quick_recognition), modifier = Modifier.clickable { onNavigateToQuickSettings() }.padding(vertical = 8.dp))
            Text(stringResource(R.string.settings_text_recognition), modifier = Modifier.clickable { onNavigateToTextSettings() }.padding(vertical = 8.dp))
            Text(stringResource(R.string.tab_faces), modifier = Modifier.clickable { onNavigateToFacesSettings() }.padding(vertical = 8.dp))
            Text(stringResource(R.string.settings_lyric_prompter), modifier = Modifier.clickable { onNavigateToLyricsSettings() }.padding(vertical = 8.dp))
        }
        item { HorizontalDivider() }
        item {
            Text(stringResource(R.string.tab_google_glass), style = MaterialTheme.typography.titleMedium, modifier = Modifier.clickable { onNavigateToGoogleGlass() }.padding(vertical = 12.dp))
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FeatureOrderScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val settings = remember { SettingsRepository(context) }
    val featureOrder by settings.featureOrder.collectAsState(initial = AppFeature.defaultOrder.map { it.name })
    var currentOrder by remember(featureOrder) { mutableStateOf(featureOrder.toMutableList()) }
    val scope = rememberCoroutineScope()

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        TopAppBar(title = { Text(stringResource(R.string.tab_feature_order)) }, navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.btn_back)) } })
        Spacer(modifier = Modifier.height(8.dp))
        LazyColumn {
            items(currentOrder.size) { index ->
                val name = currentOrder[index]
                val feature = AppFeature.entries.find { it.name == name }
                if (feature != null) {
                    ListItem(
                        headlineContent = { Text(feature.getDisplayName(context)) },
                        supportingContent = { Text(feature.getDescription(context), style = MaterialTheme.typography.bodySmall) },
                        trailingContent = {
                            Row {
                                IconButton(
                                    onClick = {
                                        if (index > 0) {
                                            val swapped = currentOrder.toMutableList()
                                            val temp = swapped[index]
                                            swapped[index] = swapped[index - 1]
                                            swapped[index - 1] = temp
                                            currentOrder = swapped
                                            scope.launch { settings.setFeatureOrder(swapped) }
                                        }
                                    },
                                    enabled = index > 0
                                ) {
                                    Icon(Icons.Filled.KeyboardArrowUp, contentDescription = stringResource(R.string.move_up))
                                }
                                IconButton(
                                    onClick = {
                                        if (index < currentOrder.size - 1) {
                                            val swapped = currentOrder.toMutableList()
                                            val temp = swapped[index]
                                            swapped[index] = swapped[index + 1]
                                            swapped[index + 1] = temp
                                            currentOrder = swapped
                                            scope.launch { settings.setFeatureOrder(swapped) }
                                        }
                                    },
                                    enabled = index < currentOrder.size - 1
                                ) {
                                    Icon(Icons.Filled.KeyboardArrowDown, contentDescription = stringResource(R.string.move_down))
                                }
                            }
                        }
                    )
                    HorizontalDivider()
                }
            }
        }
    }
}
