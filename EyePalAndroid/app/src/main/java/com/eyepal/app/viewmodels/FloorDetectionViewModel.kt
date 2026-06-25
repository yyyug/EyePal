package com.eyepal.app.viewmodels

import android.app.Application
import androidx.compose.runtime.mutableStateOf
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.eyepal.app.models.FloorRecord
import com.eyepal.app.services.AccessibilityAnnouncer
import com.eyepal.app.services.FloorDetectionService
import com.eyepal.app.services.FloorRecordStorage
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

class FloorDetectionViewModel(application: Application) : AndroidViewModel(application) {
    val currentFloor = mutableStateOf(0)
    val statusText = mutableStateOf("Tap Calibrate to start.")
    val isCalibrated = mutableStateOf(false)
    val records = mutableStateOf<List<FloorRecord>>(emptyList())

    private val floorService = FloorDetectionService(application)
    private val announcer = AccessibilityAnnouncer(application)

    init {
        records.value = FloorRecordStorage.loadRecords(application)
        viewModelScope.launch { floorService.currentFloor.collectLatest { currentFloor.value = it } }
        viewModelScope.launch { floorService.statusText.collectLatest { statusText.value = it } }
    }

    fun start() { floorService.start() }
    fun stop() { floorService.stop() }

    fun calibrate() {
        floorService.calibrate()
        isCalibrated.value = true
    }

    fun saveCurrentFloor(note: String = "") {
        val floor = currentFloor.value
        val record = FloorRecord(id = System.currentTimeMillis().toString(), floor = floor, note = note)
        records.value = listOf(record) + records.value
        FloorRecordStorage.addRecord(getApplication(), record)
        announcer.announce("Floor $floor saved.")
    }

    fun deleteRecord(id: String) {
        records.value = records.value.filter { it.id != id }
        FloorRecordStorage.deleteRecord(getApplication(), id)
    }

    override fun onCleared() { super.onCleared(); floorService.stop() }
}
