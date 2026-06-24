package com.eyepal.app.ui.screens

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.content.Context
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.eyepal.app.data.SettingsRepository
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GoogleGlassScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val settings = remember { SettingsRepository(context) }
    val isConnected by settings.googleGlassConnected.collectAsState(initial = false)
    val deviceName by settings.googleGlassDeviceName.collectAsState(initial = "")
    var showPairDialog by remember { mutableStateOf(false) }
    var pairedDevices by remember { mutableStateOf<List<BluetoothDevice>>(emptyList()) }

    val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) {
        pairedDevices = getPairedBluetoothDevices(context)
    }

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        TopAppBar(
            title = { Text("Google Glass") },
            navigationIcon = {
                IconButton(onClick = onBack) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                }
            }
        )

        Spacer(modifier = Modifier.height(16.dp))

        Card(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text("Audio Glasses", style = MaterialTheme.typography.titleMedium)
                Spacer(modifier = Modifier.height(8.dp))

                if (isConnected) {
                    Text("Connected: $deviceName", color = MaterialTheme.colorScheme.primary)
                    Spacer(modifier = Modifier.height(8.dp))
                    Button(onClick = {
                        scope.launch {
                            settings.setGoogleGlassConnected(false)
                            settings.setGoogleGlassDeviceName("")
                        }
                    }) {
                        Text("Disconnect")
                    }
                } else {
                    Text("No glasses connected.", color = MaterialTheme.colorScheme.outline)
                    Spacer(modifier = Modifier.height(8.dp))
                    Button(onClick = { showPairDialog = true }) {
                        Text("Pair New Device")
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        Card(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text("How it works", style = MaterialTheme.typography.titleMedium)
                Spacer(modifier = Modifier.height(8.dp))
                Text("EyePal sends audio descriptions to your audio glasses via Bluetooth.", style = MaterialTheme.typography.bodyMedium)
                Spacer(modifier = Modifier.height(4.dp))
                Text("Supported devices: Google Audio Glasses, Ray-Ban Meta, and other Bluetooth audio glasses.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.outline)
            }
        }
    }

    if (showPairDialog) {
        AlertDialog(
            onDismissRequest = { showPairDialog = false },
            title = { Text("Select Glasses") },
            text = {
                if (pairedDevices.isEmpty()) {
                    Text("No paired Bluetooth audio devices found. Pair your glasses in Android Bluetooth settings first.")
                } else {
                    LazyColumn {
                        items(pairedDevices) { device ->
                            ListItem(
                                headlineContent = { Text(device.name ?: "Unknown Device") },
                                supportingContent = { Text(device.address ?: "") },
                                modifier = Modifier.clickable {
                                    scope.launch {
                                        settings.setGoogleGlassDeviceName(device.name ?: "Unknown")
                                        settings.setGoogleGlassConnected(true)
                                    }
                                    showPairDialog = false
                                }
                            )
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { showPairDialog = false }) { Text("Cancel") }
            }
        )
    }
}

private fun getPairedBluetoothDevices(context: Context): List<BluetoothDevice> {
    val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager ?: return emptyList()
    val adapter = bluetoothManager.adapter ?: return emptyList()
    return try {
        adapter.bondedDevices?.toList() ?: emptyList()
    } catch (e: SecurityException) {
        emptyList()
    }
}
