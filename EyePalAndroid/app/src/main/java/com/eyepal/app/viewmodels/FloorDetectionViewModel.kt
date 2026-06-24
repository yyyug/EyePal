package com.eyepal.app.viewmodels

import android.app.Application
import androidx.compose.runtime.mutableStateOf
import androidx.lifecycle.AndroidViewModel
import com.eyepal.app.services.FloorDetectionService
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

class FloorDetectionViewModel(application: Application) : AndroidViewModel(application) {
    val currentFloor = mutableStateOf(0)
    val statusText = mutableStateOf("Tap Calibrate to start.")
    val isCalibrated = mutableStateOf(false)

    private val floorService = FloorDetectionService(application)

    init {
        viewModelScope.launch {
            floorService.currentFloor.collectLatest { currentFloor.value = it }
        }
        viewModelScope.launch {
            floorService.statusText.collectLatest { statusText.value = it }
        }
    }

    fun start() { floorService.start() }
    fun stop() { floorService.stop() }
    fun calibrate() {
        floorService.calibrate()
        isCalibrated.value = true
    }

    override fun onCleared() {
        super.onCleared()
        floorService.stop()
    }
}
