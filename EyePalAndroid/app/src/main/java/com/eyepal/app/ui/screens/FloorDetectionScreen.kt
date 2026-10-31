package com.eyepal.app.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.eyepal.app.R
import com.eyepal.app.models.Floor
import com.eyepal.app.models.FloorPlace
import com.eyepal.app.viewmodels.FloorDetectionViewModel
import java.util.Locale
import kotlin.math.abs

/**
 * Floor detection: places, their reference floor, and the floors recorded inside
 * them. Mirrors the iOS flow so the two apps behave the same.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FloorDetectionScreen(viewModel: FloorDetectionViewModel = viewModel()) {
    val places = viewModel.places.value
    val pressure = viewModel.currentPressureKPa.value
    var selectedPlaceId by rememberSaveable { mutableStateOf<String?>(null) }
    var monitoredFloorId by rememberSaveable { mutableStateOf<String?>(null) }
    var autoAddFloor by rememberSaveable { mutableStateOf(false) }

    DisposableEffect(Unit) {
        viewModel.start()
        onDispose { viewModel.stop() }
    }

    val selectedPlace = places.firstOrNull { it.id == selectedPlaceId }
    val monitoredFloor = selectedPlace?.floors?.firstOrNull { it.id == monitoredFloorId }

    BackHandler(enabled = monitoredFloorId != null) {
        monitoredFloorId = null
    }
    BackHandler(enabled = monitoredFloorId == null && selectedPlaceId != null) {
        selectedPlaceId = null
    }

    when {
        selectedPlace != null && monitoredFloor != null -> FloorMonitorContent(
            place = selectedPlace,
            floor = monitoredFloor,
            pressure = pressure,
            viewModel = viewModel,
            onBack = { monitoredFloorId = null }
        )

        selectedPlace != null -> FloorPlaceDetailContent(
            place = selectedPlace,
            pressure = pressure,
            viewModel = viewModel,
            autoAddFloor = autoAddFloor,
            onAutoAddConsumed = { autoAddFloor = false },
            onMonitor = { monitoredFloorId = it },
            onBack = { selectedPlaceId = null }
        )

        else -> FloorPlaceListContent(
            places = places,
            pressure = pressure,
            onOpen = { selectedPlaceId = it },
            onAdd = { name, start ->
                viewModel.addPlace(name, start, pressure)?.let { id ->
                    selectedPlaceId = id
                    autoAddFloor = true
                }
            },
            onRename = viewModel::renamePlace,
            onDelete = viewModel::deletePlace
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FloorPlaceListContent(
    places: List<FloorPlace>,
    pressure: Double?,
    onOpen: (String) -> Unit,
    onAdd: (String, String) -> Unit,
    onRename: (String, String) -> Unit,
    onDelete: (String) -> Unit
) {
    var showAdd by remember { mutableStateOf(false) }
    var renamingPlace by remember { mutableStateOf<FloorPlace?>(null) }

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        TopAppBar(
            title = { Text(stringResource(R.string.feature_floor_detection)) },
            actions = {
                IconButton(onClick = { showAdd = true }) {
                    Icon(Icons.Default.Add, stringResource(R.string.btn_add))
                }
            }
        )

        if (places.isEmpty()) {
            Spacer(modifier = Modifier.weight(1f))
            Text(
                stringResource(R.string.floor_empty),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.outline
            )
            Spacer(modifier = Modifier.weight(1f))
        } else {
            LazyColumn(modifier = Modifier.weight(1f)) {
                items(places, key = { it.id }) { place ->
                    ListItem(
                        headlineContent = { Text(place.name) },
                        supportingContent = {
                            Text(
                                stringResource(
                                    R.string.floor_place_subtitle,
                                    place.startFloorLabel,
                                    place.floors.size
                                )
                            )
                        },
                        trailingContent = {
                            Row {
                                IconButton(onClick = { renamingPlace = place }) {
                                    Icon(
                                        Icons.Default.Edit,
                                        stringResource(R.string.floor_rename_place)
                                    )
                                }
                                IconButton(onClick = { onDelete(place.id) }) {
                                    Icon(
                                        Icons.Default.Delete,
                                        stringResource(R.string.btn_delete),
                                        tint = MaterialTheme.colorScheme.error
                                    )
                                }
                            }
                        },
                        modifier = Modifier
                            .clickable { onOpen(place.id) }
                    )
                    HorizontalDivider()
                }
            }
        }
    }

    if (showAdd) {
        AddPlaceDialog(
            pressure = pressure,
            onDismiss = { showAdd = false },
            onSave = { name, start ->
                onAdd(name, start)
                showAdd = false
            }
        )
    }

    renamingPlace?.let { place ->
        RenameDialog(
            title = stringResource(R.string.floor_rename_place),
            initial = place.name,
            label = stringResource(R.string.floor_place_name),
            onDismiss = { renamingPlace = null },
            onSave = { name ->
                onRename(place.id, name)
                renamingPlace = null
            }
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FloorPlaceDetailContent(
    place: FloorPlace,
    pressure: Double?,
    viewModel: FloorDetectionViewModel,
    autoAddFloor: Boolean,
    onAutoAddConsumed: () -> Unit,
    onMonitor: (String) -> Unit,
    onBack: () -> Unit
) {
    var showAddFloor by remember { mutableStateOf(false) }
    var editingFloor by remember { mutableStateOf<Floor?>(null) }
    var renamingStartFloor by remember { mutableStateOf(false) }
    var pendingRecalibrationDrift by remember { mutableStateOf<Double?>(null) }

    LaunchedEffect(autoAddFloor) {
        if (autoAddFloor) {
            showAddFloor = true
            onAutoAddConsumed()
        }
    }

    val drift = pressure?.let { viewModel.drift(it, place) }

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        TopAppBar(
            title = { Text(place.name) },
            navigationIcon = {
                IconButton(onClick = onBack) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.btn_back))
                }
            },
            actions = {
                IconButton(onClick = { showAddFloor = true }) {
                    Icon(Icons.Default.Add, stringResource(R.string.floor_add_floor_action))
                }
            }
        )

        LazyColumn(modifier = Modifier.weight(1f)) {
            item {
                Text(
                    stringResource(R.string.floor_reference),
                    style = MaterialTheme.typography.titleMedium
                )
                Spacer(modifier = Modifier.height(8.dp))
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        ReferenceRow(
                            label = stringResource(R.string.floor_start_floor),
                            value = place.startFloorLabel
                        )
                        ReferenceRow(
                            label = stringResource(R.string.floor_pressure),
                            value = String.format(
                                Locale.US,
                                "%.2f kPa",
                                place.baselinePressureKPa
                            )
                        )
                        if (drift != null && abs(drift) > FloorDetectionViewModel.DRIFT_NOTICE_METERS) {
                            Spacer(modifier = Modifier.height(8.dp))
                            Text(
                                stringResource(R.string.floor_drift, drift),
                                style = MaterialTheme.typography.bodySmall
                            )
                        }
                        Spacer(modifier = Modifier.height(8.dp))
                        TextButton(onClick = { renamingStartFloor = true }) {
                            Text(stringResource(R.string.floor_rename_start_floor))
                        }
                        Button(
                            onClick = {
                                val current = pressure ?: return@Button
                                pendingRecalibrationDrift = viewModel.drift(current, place)
                            },
                            enabled = pressure != null,
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(stringResource(R.string.floor_recalibrate))
                        }
                    }
                }
                Spacer(modifier = Modifier.height(16.dp))
                Text(
                    stringResource(R.string.floor_floors),
                    style = MaterialTheme.typography.titleMedium
                )
            }

            if (place.floors.isEmpty()) {
                item {
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        stringResource(R.string.floor_no_floors),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.outline
                    )
                }
            } else {
                'val startFloorIsListed = place.floors.any { it.label == place.startFloorLabel }
val displayFloors = place.floors + (if (startFloorIsListed) emptyList() else listOf(
    Floor(id = place.id.toString(), label = place.startFloorLabel, pressureKPa = place.baselinePressureKPa)
))
items(displayFloors, key = { it.id }) { floor ->'
                    val isStartFloor = floor.label == place.startFloorLabel
                    ListItem(
                        headlineContent = {
                            Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                                Text(floor.label)
                                if (isStartFloor) {
                                    Icon(
                                        imageVector = Icons.Default.Home,
                                        contentDescription = stringResource(R.string.floor_set_as_start),
                                        modifier = androidx.compose.ui.Modifier
                                            .size(16.dp)
                                            .padding(start = 4.dp),
                                        tint = MaterialTheme.colorScheme.primary
                                    )
                                }
                            }
                        },
                        supportingContent = {
                            viewModel.heightOf(floor, place)?.let { height ->
                                Text(String.format(Locale.US, "%+.2f m", height))
                            }
                        },
                        trailingContent = {
                            Row {
                                IconButton(onClick = { viewModel.setStartFloor(place.id, floor.label, floor.pressureKPa) }) {
                                    Icon(
                                        Icons.Default.Home,
                                        stringResource(R.string.floor_set_as_start),
                                        tint = MaterialTheme.colorScheme.primary
                                    )
                                }
                                IconButton(onClick = { editingFloor = floor }) {
                                    Icon(
                                        Icons.Default.Edit,
                                        stringResource(R.string.floor_rename_floor)
                                    )
                                }
                                IconButton(
                                    onClick = { viewModel.deleteFloor(place.id, floor.id) }
                                ) {
                                    Icon(
                                        Icons.Default.Delete,
                                        stringResource(R.string.btn_delete),
                                        tint = MaterialTheme.colorScheme.error
                                    )
                                }
                            }
                        },
                        modifier = Modifier.clickable { onMonitor(floor.id) }
                    )
                    HorizontalDivider()
                }
            }
        }
    }

    if (showAddFloor) {
        AddFloorDialog(
            place = place,
            pressure = pressure,
            viewModel = viewModel,
            onDismiss = { showAddFloor = false },
            onSave = { label ->
                viewModel.addFloor(place.id, label, pressure)
                showAddFloor = false
            }
        )
    }

    if (renamingStartFloor) {
        RenameDialog(
            title = stringResource(R.string.floor_rename_start_floor),
            initial = place.startFloorLabel,
            label = stringResource(R.string.floor_number),
            onDismiss = { renamingStartFloor = false },
            onSave = { label ->
                viewModel.updateStartFloorLabel(place.id, label)
                renamingStartFloor = false
            }
        )
    }

    editingFloor?.let { floor ->
        EditFloorDialog(
            place = place,
            floor = floor,
            viewModel = viewModel,
            onDismiss = { editingFloor = null },
            onSave = { label, height ->
                viewModel.updateFloor(place.id, floor.id, label, height)
                editingFloor = null
            }
        )
    }

    pendingRecalibrationDrift?.let { driftMeters ->
        AlertDialog(
            onDismissRequest = { pendingRecalibrationDrift = null },
            title = { Text(stringResource(R.string.floor_recalibrate_confirm_title)) },
            text = {
                Text(
                    stringResource(
                        R.string.floor_recalibrate_confirm_message,
                        driftMeters,
                        place.startFloorLabel
                    )
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    pressure?.let { viewModel.recalibrateBaseline(place.id, it) }
                    pendingRecalibrationDrift = null
                }) {
                    Text(stringResource(R.string.floor_recalibrate_confirm_action))
                }
            },
            dismissButton = {
                TextButton(onClick = { pendingRecalibrationDrift = null }) {
                    Text(stringResource(R.string.btn_cancel))
                }
            }
        )
    }
}

@Composable
private fun ReferenceRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(label)
        Text(value, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FloorMonitorContent(
    place: FloorPlace,
    floor: Floor,
    pressure: Double?,
    viewModel: FloorDetectionViewModel,
    onBack: () -> Unit
) {
    var announced by remember(floor.id) { mutableStateOf(false) }

    LaunchedEffect(pressure, floor.id) {
        val current = pressure
        if (current == null) {
            announced = false
            return@LaunchedEffect
        }
        val arrived = viewModel.hasArrived(place, floor, current)
        if (arrived && !announced) {
            announced = true
            viewModel.announceArrival(place, floor)
        } else if (!arrived) {
            announced = false
        }
    }

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        TopAppBar(
            title = { Text(floor.label) },
            navigationIcon = {
                IconButton(onClick = onBack) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.btn_back))
                }
            }
        )

        Spacer(modifier = Modifier.height(16.dp))
        Text(
            stringResource(R.string.floor_pressure),
            style = MaterialTheme.typography.titleSmall
        )
        Text(
            pressure?.let { String.format(Locale.US, "%.2f kPa", it) }
                ?: stringResource(R.string.floor_unavailable),
            style = MaterialTheme.typography.headlineMedium
        )

        Spacer(modifier = Modifier.height(16.dp))
        Text(
            stringResource(R.string.floor_watching, "${place.name} ${floor.label}"),
            style = MaterialTheme.typography.headlineSmall
        )

        viewModel.heightOf(floor, place)?.let { height ->
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                String.format(Locale.US, "%+.2f m", height),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun AddPlaceDialog(
    pressure: Double?,
    onDismiss: () -> Unit,
    onSave: (String, String) -> Unit
) {
    var name by remember { mutableStateOf("") }
    var startFloor by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.floor_new_place)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    stringResource(R.string.floor_starting_header),
                    style = MaterialTheme.typography.titleSmall
                )
                Text(
                    stringResource(R.string.floor_pressure) + ": " +
                        (pressure?.let { String.format(Locale.US, "%.2f kPa", it) }
                            ?: stringResource(R.string.floor_unavailable))
                )
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(stringResource(R.string.floor_place_name)) },
                    singleLine = true
                )
                OutlinedTextField(
                    value = startFloor,
                    onValueChange = { startFloor = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(stringResource(R.string.floor_start_floor)) },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)
                )
                Text(
                    stringResource(R.string.floor_starting_footer),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.outline
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = { onSave(name, startFloor) },
                enabled = name.isNotBlank() && startFloor.isNotBlank() && pressure != null
            ) {
                Text(stringResource(R.string.floor_set_as_start))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.btn_cancel)) }
        }
    )
}

@Composable
private fun AddFloorDialog(
    place: FloorPlace,
    pressure: Double?,
    viewModel: FloorDetectionViewModel,
    onDismiss: () -> Unit,
    onSave: (String) -> Unit
) {
    var label by remember { mutableStateOf("") }
    var didPrefill by remember { mutableStateOf(false) }

    val height = pressure?.let { viewModel.drift(it, place) }
    val suggestion = pressure?.let { viewModel.suggestedFloorLabel(it, place) }

    LaunchedEffect(pressure, place.id) {
        if (!didPrefill && label.isBlank() && pressure != null) {
            suggestion?.let {
                label = it
                didPrefill = true
            }
        }
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.floor_new_floor)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    stringResource(R.string.floor_destination_header),
                    style = MaterialTheme.typography.titleSmall
                )
                Text(
                    stringResource(R.string.floor_pressure) + ": " +
                        (pressure?.let { String.format(Locale.US, "%.2f kPa", it) }
                            ?: stringResource(R.string.floor_unavailable))
                )
                Text(
                    stringResource(R.string.floor_above_start) + ": " +
                        (height?.let { String.format(Locale.US, "%+.2f m", it) }
                            ?: stringResource(R.string.floor_unavailable))
                )
                Text(
                    stringResource(R.string.floor_suggested) + ": " +
                        (suggestion ?: stringResource(R.string.floor_unavailable))
                )
                OutlinedTextField(
                    value = label,
                    onValueChange = {
                        label = it
                        didPrefill = true
                    },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(stringResource(R.string.floor_number)) },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)
                )
                Text(
                    stringResource(R.string.floor_destination_footer),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.outline
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = { onSave(label) },
                enabled = label.isNotBlank() && pressure != null
            ) {
                Text(stringResource(R.string.floor_add_floor))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.btn_cancel)) }
        }
    )
}

@Composable
private fun EditFloorDialog(
    place: FloorPlace,
    floor: Floor,
    viewModel: FloorDetectionViewModel,
    onDismiss: () -> Unit,
    onSave: (String, Double?) -> Unit
) {
    var label by remember { mutableStateOf(floor.label) }
    var height by remember {
        mutableStateOf(
            viewModel.heightOf(floor, place)?.let { String.format(Locale.US, "%.2f", it) } ?: ""
        )
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.floor_rename_floor)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = label,
                    onValueChange = { label = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(stringResource(R.string.floor_number)) },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)
                )
                OutlinedTextField(
                    value = height,
                    onValueChange = { height = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(stringResource(R.string.floor_height)) },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)
                )
                Text(
                    stringResource(R.string.floor_height_footer),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.outline
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    val meters = height
                        .replace(',', '.')
                        .trim()
                        .toDoubleOrNull()
                    onSave(label, meters)
                },
                enabled = label.isNotBlank()
            ) {
                Text(stringResource(R.string.btn_save))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.btn_cancel)) }
        }
    )
}

@Composable
private fun RenameDialog(
    title: String,
    initial: String,
    label: String,
    onDismiss: () -> Unit,
    onSave: (String) -> Unit
) {
    var value by remember { mutableStateOf(initial) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            OutlinedTextField(
                value = value,
                onValueChange = { value = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text(label) },
                singleLine = true
            )
        },
        confirmButton = {
            TextButton(
                onClick = { onSave(value) },
                enabled = value.isNotBlank()
            ) {
                Text(stringResource(R.string.btn_save))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.btn_cancel)) }
        }
    )
}




