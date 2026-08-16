package com.eyepal.app.viewmodels

import android.app.Application
import androidx.compose.runtime.mutableStateOf
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.eyepal.app.EyePalApplication
import com.eyepal.app.R
import com.eyepal.app.models.FloorRecord
import com.eyepal.app.services.FloorRecordStorage
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

class FloorDetectionViewModel(application: Application) : AndroidViewModel(application) {
    private fun str(resId: Int): String = getApplication<Application>().getString(resId)
    private fun str(resId: Int, vararg args: Any?): String = getApplication<Application>().getString(resId, *args)

    val currentFloor = mutableStateOf(0)
    val statusText = mutableStateOf(str(R.string.status_tap_calibrate))
    val isCalibrated = mutableStateOf(false)
    val records = mutableStateOf<List<FloorRecord>>(emptyList())

    private val container = (application as EyePalApplication).container
    private val floorService = container.floorDetectionService
    private val announcer = container.announcer

    init {
        records.value = FloorRecordStorage.loadRecords(application)
        viewModelScope.launch { floorService.currentFloor.collectLatest { currentFloor.value = it } }
        viewModelScope.launch { floorService.statusText.collectLatest { statusText.value = it } }
        viewModelScope.launch { floorService.currentPressure.collectLatest { currentPressure = it } }
        viewModelScope.launch { floorService.baselinePressureFlow.collectLatest { baselinePressure = it } }
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
        announcer.announce(str(R.string.status_floor_saved, floor))
    }

    fun deleteRecord(id: String) {
        records.value = records.value.filter { it.id != id }
        FloorRecordStorage.deleteRecord(getApplication(), id)
    }

    fun renameRecord(id: String, newName: String) {
        records.value = records.value.map { if (it.id == id) it.copy(name = newName) else it }
        FloorRecordStorage.renameRecord(getApplication(), id, newName)
        announcer.announce(str(R.string.status_record_renamed, newName))
    }

    fun addRecord(name: String, altitude: Double, floor: Int) {
        val record = FloorRecord(
            id = System.currentTimeMillis().toString(),
            floor = floor,
            name = name,
            altitude = altitude
        )
        records.value = listOf(record) + records.value
        FloorRecordStorage.addRecord(getApplication(), record)
        announcer.announce(str(R.string.status_record_saved, name))
    }

    fun updateRecord(id: String, name: String, altitude: Double, floor: Int) {
        records.value = records.value.map { if (it.id == id) it.copy(name = name, altitude = altitude, floor = floor) else it }
        FloorRecordStorage.updateRecord(getApplication(), id, name, altitude, floor)
        announcer.announce(str(R.string.status_record_updated))
    }

    private var currentPressure = 1013.25f
    private var baselinePressure = 1013.25f

    fun getCurrentAltitude(): Double {
        if (currentPressure <= 0) return 0.0
        return 44330.0 * (1.0 - java.lang.Math.pow((currentPressure / baselinePressure).toDouble(), 1.0 / 5.255))
    }

    override fun onCleared() { super.onCleared(); floorService.stop() }
}