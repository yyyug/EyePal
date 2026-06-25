package com.eyepal.app.ui

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.eyepal.app.ui.screens.*
import kotlinx.serialization.Serializable

sealed class Screen(val route: String, val label: String, val icon: ImageVector) {
    data object QuickRecognition : Screen("quick", "Quick", Icons.Default.CameraAlt)
    data object DetailsRecognition : Screen("details", "Details", Icons.Default.AutoAwesome)
    data object ReadText : Screen("readtext", "Read Text", Icons.Default.TextFields)
    data object Faces : Screen("faces", "Faces", Icons.Default.Person)
    data object FloorDetection : Screen("floor", "Floor", Icons.Default.Architecture)
    data object Chat : Screen("chat", "Chat", Icons.Default.Mic)
    data object LyricPrompter : Screen("lyrics", "Lyrics", Icons.Default.MusicNote)
    data object More : Screen("more", "More", Icons.Default.MoreHoriz)
    data object Settings : Screen("settings", "Settings", Icons.Default.Settings)
    data object FeatureOrder : Screen("featureorder", "Feature Order", Icons.Default.Reorder)
    data object GoogleGlass : Screen("googleglass", "Google Glass", Icons.Default.Visibility)
    data object SavedFaces : Screen("savedfaces", "Saved Faces", Icons.Default.People)
    data object DetailsSettings : Screen("details_settings", "Details Settings", Icons.Default.Settings)
    data object QuickSettings : Screen("quick_settings", "Quick Settings", Icons.Default.Settings)
    data object TextSettings : Screen("text_settings", "Text Settings", Icons.Default.Settings)
    data object FacesSettings : Screen("faces_settings", "Faces Settings", Icons.Default.Settings)
    data object LyricsSettings : Screen("lyrics_settings", "Lyrics Settings", Icons.Default.Settings)
}

val bottomTabs = listOf(
    Screen.QuickRecognition,
    Screen.DetailsRecognition,
    Screen.ReadText,
    Screen.Faces,
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EyePalApp() {
    val navController = rememberNavController()
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = navBackStackEntry?.destination?.route

    Scaffold(
        bottomBar = {
            if (currentRoute in bottomTabs.map { it.route } || currentRoute == Screen.More.route) {
                NavigationBar {
                    bottomTabs.forEach { screen ->
                        NavigationBarItem(
                            icon = { Icon(screen.icon, contentDescription = screen.label) },
                            label = { Text(screen.label) },
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
                    NavigationBarItem(
                        icon = { Icon(Icons.Default.MoreHoriz, contentDescription = "More") },
                        label = { Text("More") },
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
            startDestination = Screen.QuickRecognition.route,
            modifier = Modifier.padding(padding)
        ) {
            composable(Screen.QuickRecognition.route) { QuickRecognitionScreen() }
            composable(Screen.DetailsRecognition.route) { DetailsRecognitionScreen() }
            composable(Screen.ReadText.route) { ReadTextScreen() }
            composable(Screen.Faces.route) {
                val facesViewModel: com.eyepal.app.viewmodels.FacesViewModel = viewModel()
                FacesScreen(viewModel = facesViewModel, onNavigateToSavedFaces = { navController.navigate(Screen.SavedFaces.route) }, savedFacesViewModel = facesViewModel)
            }
            composable(Screen.FloorDetection.route) { FloorDetectionScreen() }
            composable(Screen.Chat.route) { ChatScreen() }
            composable(Screen.LyricPrompter.route) { LyricPrompterScreen() }
            composable(Screen.More.route) {
                MoreScreen(
                    onNavigateToSettings = { navController.navigate(Screen.Settings.route) },
                    onNavigateToFeatureOrder = { navController.navigate(Screen.FeatureOrder.route) },
                    onNavigateToFloorDetection = { navController.navigate(Screen.FloorDetection.route) },
                    onNavigateToChat = { navController.navigate(Screen.Chat.route) },
                    onNavigateToLyricPrompter = { navController.navigate(Screen.LyricPrompter.route) },
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
            composable(Screen.SavedFaces.route) {
                val facesViewModel: com.eyepal.app.viewmodels.FacesViewModel = viewModel()
                SavedFacesScreen(viewModel = facesViewModel, onBack = { navController.popBackStack() })
            }
            composable(Screen.DetailsSettings.route) { DetailsRecognitionSettingsScreen(onBack = { navController.popBackStack() }) }
            composable(Screen.QuickSettings.route) { QuickRecognitionSettingsScreen(onBack = { navController.popBackStack() }) }
            composable(Screen.TextSettings.route) { TextRecognitionSettingsScreen(onBack = { navController.popBackStack() }) }
            composable(Screen.FacesSettings.route) { FacesSettingsScreen(onBack = { navController.popBackStack() }) }
            composable(Screen.LyricsSettings.route) { LyricPrompterSettingsScreen(onBack = { navController.popBackStack() }) }
        }
    }
}
