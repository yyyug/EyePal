package com.eyepal.app.ui

import androidx.annotation.StringRes
import android.Manifest
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.Alignment
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.lifecycle.viewmodel.compose.viewModel
import com.eyepal.app.R
import com.eyepal.app.data.SettingsRepository
import com.eyepal.app.models.AppFeature
import com.eyepal.app.ui.screens.*
import com.eyepal.app.viewmodels.GoogleGlassViewModel
import com.eyepal.app.services.GoogleGlassState
import com.eyepal.app.services.AccessibilityAnnouncer
import com.google.accompanist.permissions.ExperimentalPermissionsApi
import com.google.accompanist.permissions.isGranted
import com.google.accompanist.permissions.rememberPermissionState
import com.google.accompanist.permissions.shouldShowRationale
import kotlinx.coroutines.delay
import kotlinx.serialization.Serializable

sealed class Screen(val route: String, @StringRes val labelRes: Int, val icon: ImageVector) {
    data object QuickRecognition : Screen("quick", R.string.tab_quick, Icons.Default.CameraAlt)
    data object DetailsRecognition : Screen("details", R.string.tab_details, Icons.Default.AutoAwesome)
    data object ReadText : Screen("readtext", R.string.tab_read_text, Icons.Default.TextFields)
    data object Faces : Screen("faces", R.string.tab_faces, Icons.Default.Person)
    data object FloorDetection : Screen("floor", R.string.tab_floor, Icons.Default.Architecture)
    data object Chat : Screen("chat", R.string.tab_chat, Icons.Default.Mic)
    data object LyricPrompter : Screen("lyrics", R.string.tab_lyrics, Icons.Default.MusicNote)
    data object More : Screen("more", R.string.tab_more, Icons.Default.MoreHoriz)
    data object Settings : Screen("settings", R.string.tab_settings, Icons.Default.Settings)
    data object FeatureOrder : Screen("featureorder", R.string.tab_feature_order, Icons.Default.Reorder)
    data object GoogleGlass : Screen("googleglass", R.string.tab_google_glass, Icons.Default.Visibility)
    data object SavedFaces : Screen("savedfaces", R.string.tab_saved_faces, Icons.Default.People)
    data object DetailsSettings : Screen("details_settings", R.string.tab_settings, Icons.Default.Settings)
    data object QuickSettings : Screen("quick_settings", R.string.tab_settings, Icons.Default.Settings)
    data object TextSettings : Screen("text_settings", R.string.tab_settings, Icons.Default.Settings)
    data object FacesSettings : Screen("faces_settings", R.string.tab_settings, Icons.Default.Settings)
    data object LyricsSettings : Screen("lyrics_settings", R.string.tab_settings, Icons.Default.Settings)
}

val defaultBottomTabs = listOf(
    Screen.FloorDetection,
    Screen.Chat,
    Screen.Faces,
    Screen.QuickRecognition,
)

private val featureNameToScreen = mapOf(
    "FLOOR_DETECTION" to Screen.FloorDetection,
    "CHAT" to Screen.Chat,
    "FACES" to Screen.Faces,
    "QUICK_RECOGNITION" to Screen.QuickRecognition,
    "DETAILS_RECOGNITION" to Screen.DetailsRecognition,
    "READ_TEXT" to Screen.ReadText,
    "LYRIC_PROMPTER" to Screen.LyricPrompter,
)

@OptIn(ExperimentalMaterial3Api::class, ExperimentalPermissionsApi::class)
@Composable
fun EyePalApp() {
    val cameraPermission = rememberPermissionState(Manifest.permission.CAMERA)
    val audioPermission = rememberPermissionState(Manifest.permission.RECORD_AUDIO)

    LaunchedEffect(Unit) {
        if (!cameraPermission.status.isGranted) cameraPermission.launchPermissionRequest()
    }
    LaunchedEffect(cameraPermission.status.isGranted) {
        if (cameraPermission.status.isGranted && !audioPermission.status.isGranted) {
            audioPermission.launchPermissionRequest()
        }
    }

    if (!cameraPermission.status.isGranted) {
        Column(modifier = Modifier.fillMaxSize().padding(32.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
            Text("EyePal needs camera access to function", style = MaterialTheme.typography.headlineSmall, textAlign = TextAlign.Center)
            Spacer(modifier = Modifier.height(16.dp))
            if (cameraPermission.status.shouldShowRationale) {
                Text("Camera access is required for all visual assistance features.", style = MaterialTheme.typography.bodyMedium, textAlign = TextAlign.Center)
            }
            Spacer(modifier = Modifier.height(24.dp))
            Button(onClick = { cameraPermission.launchPermissionRequest() }) { Text("Grant Camera Permission") }
        }
        return
    }

    val navController = rememberNavController()
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = navBackStackEntry?.destination?.route
    val context = LocalContext.current
    val activity = context as? android.app.Activity
    val glassViewModel: GoogleGlassViewModel = viewModel()

    val settings = remember { SettingsRepository(context) }
    val savedFeatureOrder by settings.featureOrder.collectAsState(initial = null)

    val orderedFeatureNames = savedFeatureOrder ?: AppFeature.defaultOrder.map { it.name }
    val orderedScreens = orderedFeatureNames.mapNotNull { featureNameToScreen[it] }
    val bottomTabs = if (orderedScreens.size >= 4) orderedScreens.take(4) else defaultBottomTabs
    val moreFeatures = if (orderedScreens.size >= 4)
        orderedFeatureNames.drop(4).mapNotNull { name -> AppFeature.entries.find { it.name == name } }
    else emptyList()

    // Auto-connect to audio glasses on startup
    LaunchedEffect(Unit) {
        delay(1000) // Wait for system initialization
        activity?.let { glassViewModel.autoConnect(it) }
    }

    Scaffold(
        bottomBar = {
            if (currentRoute in bottomTabs.map { it.route } || currentRoute == Screen.More.route) {
                NavigationBar {
                    bottomTabs.forEach { screen ->
                        val label = stringResource(screen.labelRes)
                        NavigationBarItem(
                            icon = { Icon(screen.icon, contentDescription = label) },
                            label = { Text(label) },
                            selected = currentRoute == screen.route,
                            onClick = {
                                navController.navigate(screen.route) {
                                    popUpTo(navController.graph.findStartDestination().id) { saveState = true }
                                    launchSingleTop = true
                                    restoreState = true
                                }
                            }
                        )
                    }
                    val moreLabel = stringResource(R.string.tab_more)
                    NavigationBarItem(
                        icon = { Icon(Icons.Default.MoreHoriz, contentDescription = moreLabel) },
                        label = { Text(moreLabel) },
                        selected = currentRoute == Screen.More.route,
                        onClick = {
                            navController.navigate(Screen.More.route) {
                                popUpTo(navController.graph.findStartDestination().id) { saveState = true }
                                launchSingleTop = true
                                restoreState = true
                            }
                        }
                    )
                }
            }
        }
    ) { padding ->
        NavHost(
            navController = navController,
            startDestination = (bottomTabs.firstOrNull()?.route ?: Screen.FloorDetection.route),
            modifier = Modifier.padding(padding)
        ) {
            composable(Screen.QuickRecognition.route) { QuickRecognitionScreen() }
            composable(Screen.DetailsRecognition.route) { DetailsRecognitionScreen() }
            composable(Screen.ReadText.route) { ReadTextScreen() }
            composable(Screen.Faces.route) { backStackEntry ->
                val facesViewModel: com.eyepal.app.viewmodels.FacesViewModel = viewModel(backStackEntry)
                FacesScreen(viewModel = facesViewModel)
            }
            composable(Screen.FloorDetection.route) { FloorDetectionScreen() }
            composable(Screen.Chat.route) { ChatScreen() }
            composable(Screen.LyricPrompter.route) { LyricPrompterScreen() }
            composable(Screen.More.route) {
                MoreScreen(
                    moreFeatures = moreFeatures,
                    onNavigateToFeature = { feature -> navController.navigate(featureNameToScreen[feature.name]!!.route) },
                    onNavigateToSettings = { navController.navigate(Screen.Settings.route) },
                    onNavigateToFeatureOrder = { navController.navigate(Screen.FeatureOrder.route) },
                    onNavigateToGoogleGlass = { navController.navigate(Screen.GoogleGlass.route) }
                )
            }
            composable(Screen.Settings.route) {
                SettingsScreen(
                    onNavigateToFeatureOrder = { navController.navigate(Screen.FeatureOrder.route) },
                    onNavigateToGoogleGlass = { navController.navigate(Screen.GoogleGlass.route) },
                    onNavigateToDetailsSettings = { navController.navigate(Screen.DetailsSettings.route) },
                    onNavigateToQuickSettings = { navController.navigate(Screen.QuickSettings.route) },
                    onNavigateToTextSettings = { navController.navigate(Screen.TextSettings.route) },
                    onNavigateToFacesSettings = { navController.navigate(Screen.FacesSettings.route) },
                    onNavigateToLyricsSettings = { navController.navigate(Screen.LyricsSettings.route) },
                    onBack = { navController.popBackStack() }
                )
            }
            composable(Screen.FeatureOrder.route) {
                FeatureOrderScreen(onBack = { navController.popBackStack() })
            }
            composable(Screen.GoogleGlass.route) {
                GoogleGlassScreen(onBack = { navController.popBackStack() })
            }
            composable(Screen.SavedFaces.route) { SavedFacesScreen(onBack = { navController.popBackStack() }) }
            composable(Screen.DetailsSettings.route) { DetailsRecognitionSettingsScreen(onBack = { navController.popBackStack() }) }
            composable(Screen.QuickSettings.route) { QuickRecognitionSettingsScreen(onBack = { navController.popBackStack() }) }
            composable(Screen.TextSettings.route) { TextRecognitionSettingsScreen(onBack = { navController.popBackStack() }) }
            composable(Screen.FacesSettings.route) { FacesSettingsScreen(onBack = { navController.popBackStack() }, onNavigateToSavedFaces = { navController.navigate(Screen.SavedFaces.route) }) }
            composable(Screen.LyricsSettings.route) { LyricPrompterSettingsScreen(onBack = { navController.popBackStack() }) }
        }
    }
}
