package com.eyepal.app.ui.screens

import android.Manifest
import android.view.ViewGroup
import androidx.camera.view.PreviewView
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.viewmodel.compose.viewModel
import com.eyepal.app.R
import com.eyepal.app.services.DiscoveredGlass
import com.eyepal.app.services.GlassConnectionState
import com.eyepal.app.viewmodels.GoogleGlassViewModel
import com.google.accompanist.permissions.ExperimentalPermissionsApi
import com.google.accompanist.permissions.isGranted
import com.google.accompanist.permissions.rememberPermissionState

@OptIn(ExperimentalMaterial3Api::class, ExperimentalPermissionsApi::class)
@Composable
fun GoogleGlassScreen(onBack: () -> Unit, viewModel: GoogleGlassViewModel = viewModel()) {
    val isConnected by viewModel.isConnected
    val statusText by viewModel.statusText
    val useGlassCamera by viewModel.useGlassCamera
    val isXRMode by viewModel.isXRMode
    val bluetoothNeedsEnable by viewModel.bluetoothNeedsEnable
    val bluetoothPairingNeeded by viewModel.bluetoothPairingNeeded
    val bluetoothPermissionDenied by viewModel.bluetoothPermissionDenied
    val connectionState by viewModel.connectionState
    val discoveredDevices by viewModel.discoveredDevices
    val pairingDevice by viewModel.pairingDevice
    val connectedDeviceName by viewModel.connectedDeviceName
    val statusDetail by viewModel.statusDetail
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current

    val btPermission = rememberPermissionState(Manifest.permission.BLUETOOTH_CONNECT)
    LaunchedEffect(Unit) {
        if (!btPermission.status.isGranted) btPermission.launchPermissionRequest()
    }

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        TopAppBar(title = { Text(stringResource(R.string.tab_google_glass)) }, navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.btn_back)) } })

        Card(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text(stringResource(R.string.glass_audio_glasses), style = MaterialTheme.typography.titleMedium)
                Spacer(modifier = Modifier.height(8.dp))
                Text(statusText, color = if (isConnected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline)
                connectedDeviceName?.let { name ->
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(name, style = MaterialTheme.typography.bodyMedium)
                }
                if (isConnected) {
                    Spacer(modifier = Modifier.height(8.dp))
                    AssistChip(
                        onClick = {},
                        label = { Text(if (isXRMode) stringResource(R.string.glass_connected_xr) else stringResource(R.string.glass_connected_bt)) },
                        leadingIcon = { Text(if (isXRMode) "XR" else "BT", style = MaterialTheme.typography.labelSmall) }
                    )
                }
                Spacer(modifier = Modifier.height(12.dp))
                when {
                    isConnected -> Button(onClick = { viewModel.disconnect() }, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.glass_disconnect)) }
                    bluetoothPermissionDenied -> {
                        Button(onClick = { btPermission.launchPermissionRequest() }, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.glass_request_permission)) }
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(stringResource(R.string.glass_permission_needed), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.outline)
                    }
                    bluetoothNeedsEnable -> {
                        Button(onClick = {
                            val activity = context as? android.app.Activity
                            if (activity != null) viewModel.requestBluetoothEnable(activity)
                        }, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.glass_enable_bluetooth)) }
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(stringResource(R.string.glass_bluetooth_required), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.outline)
                    }
                    connectionState == GlassConnectionState.SCANNING -> {
                        Button(onClick = { viewModel.stopScan() }, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.glass_stop_scan)) }
                        Spacer(modifier = Modifier.height(8.dp))
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(stringResource(R.string.glass_scanning), style = MaterialTheme.typography.bodySmall)
                        }
                    }
                    connectionState == GlassConnectionState.PAIRING || connectionState == GlassConnectionState.CONNECTING -> {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(stringResource(R.string.glass_connecting), style = MaterialTheme.typography.bodySmall)
                        }
                    }
                    else -> {
                        Button(onClick = { viewModel.scan() }, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.glass_scan)) }
                        Spacer(modifier = Modifier.height(4.dp))
                        TextButton(onClick = {
                            val activity = context as? android.app.Activity
                            if (activity != null) viewModel.openBluetoothSettings(activity)
                        }, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.glass_open_bt_settings)) }
                        if (bluetoothPairingNeeded) {
                            Spacer(modifier = Modifier.height(4.dp))
                            Text(stringResource(R.string.glass_pairing_instructions), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.outline)
                        }
                    }
                }
            }
        }

        if (!isConnected && (discoveredDevices.isNotEmpty() || connectionState == GlassConnectionState.SCANNING || (statusDetail != null && connectionState == GlassConnectionState.DISCONNECTED))) {
            Spacer(modifier = Modifier.height(16.dp))
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(8.dp)) {
                    if (discoveredDevices.isEmpty() && statusDetail != null) {
                        statusDetail?.let { detail ->
                            Text(detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.outline, modifier = Modifier.padding(8.dp))
                        }
                    }
                    discoveredDevices.forEach { glass ->
                        GlassDeviceRow(
                            glass = glass,
                            isPairing = pairingDevice == glass.address,
                            onPair = { viewModel.pairWith(glass.device) }
                        )
                        HorizontalDivider()
                    }
                }
            }
        }

        if (isConnected) {
            Spacer(modifier = Modifier.height(16.dp))
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text(stringResource(R.string.glass_camera), style = MaterialTheme.typography.titleMedium)
                    Spacer(modifier = Modifier.height(8.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(stringResource(R.string.glass_use_camera))
                        Spacer(modifier = Modifier.weight(1f))
                        Switch(checked = useGlassCamera, onCheckedChange = {
                            viewModel.toggleGlassCamera(lifecycleOwner, PreviewView(context).apply {
                                layoutParams = ViewGroup.LayoutParams(1, 1)
                            })
                        })
                    }
                    if (isXRMode) {
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(stringResource(R.string.glass_xr_desc), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
                    }
                    if (useGlassCamera) {
                        Spacer(modifier = Modifier.height(8.dp))
                        AndroidView(
                            factory = { ctx ->
                                PreviewView(ctx).apply {
                                    layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                                    scaleType = PreviewView.ScaleType.FILL_CENTER
                                    implementationMode = PreviewView.ImplementationMode.COMPATIBLE
                                }
                            },
                            modifier = Modifier.fillMaxWidth().height(200.dp),
                            update = { preview -> viewModel.toggleGlassCamera(lifecycleOwner, preview) }
                        )
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(16.dp))
        Card(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text(stringResource(R.string.glass_how_it_works), style = MaterialTheme.typography.titleMedium)
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    if (isXRMode) stringResource(R.string.glass_xr_desc)
                    else stringResource(R.string.glass_bluetooth_desc),
                    style = MaterialTheme.typography.bodyMedium
                )
            }
        }
    }
}

@Composable
private fun GlassDeviceRow(
    glass: DiscoveredGlass,
    isPairing: Boolean,
    onPair: () -> Unit
) {
    Row(modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(modifier = Modifier.weight(1f)) {
            Text(glass.name, style = MaterialTheme.typography.bodyLarge)
            Text(
                if (glass.isPaired) stringResource(R.string.glass_paired) else glass.address,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.outline
            )
        }
        if (isPairing) {
            CircularProgressIndicator(modifier = Modifier.size(24.dp), strokeWidth = 2.dp)
        } else {
            Button(onClick = onPair) { Text(stringResource(R.string.glass_pair)) }
        }
    }
}
