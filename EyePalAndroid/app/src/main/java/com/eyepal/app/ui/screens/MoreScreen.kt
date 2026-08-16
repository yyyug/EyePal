package com.eyepal.app.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.eyepal.app.R
import com.eyepal.app.models.AppFeature

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MoreScreen(
    moreFeatures: List<AppFeature>,
    onNavigateToFeature: (AppFeature) -> Unit,
    onNavigateToSettings: () -> Unit,
    onNavigateToFeatureOrder: () -> Unit,
    onNavigateToGoogleGlass: () -> Unit
) {
    val context = LocalContext.current
    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        TopAppBar(title = { Text(stringResource(R.string.tab_more)) })
        Spacer(modifier = Modifier.height(8.dp))

        LazyColumn {
            items(moreFeatures.size) { index ->
                val feature = moreFeatures[index]
                ListItem(
                    headlineContent = { Text(feature.getDisplayName(context)) },
                    supportingContent = { Text(feature.getDescription(context), style = MaterialTheme.typography.bodySmall) },
                    modifier = Modifier.clickable { onNavigateToFeature(feature) }
                )
                HorizontalDivider()
            }
            item {
                ListItem(headlineContent = { Text(stringResource(R.string.tab_settings)) }, supportingContent = { Text(stringResource(R.string.more_app_config)) },
                    modifier = Modifier.clickable { onNavigateToSettings() })
                HorizontalDivider()
            }
            item {
                ListItem(headlineContent = { Text(stringResource(R.string.tab_feature_order)) }, supportingContent = { Text(stringResource(R.string.more_custom_tabs)) },
                    modifier = Modifier.clickable { onNavigateToFeatureOrder() })
                HorizontalDivider()
            }
            item {
                ListItem(headlineContent = { Text(stringResource(R.string.tab_google_glass)) }, supportingContent = { Text(stringResource(R.string.more_audio_glasses)) },
                    modifier = Modifier.clickable { onNavigateToGoogleGlass() })
            }
        }
    }
}
