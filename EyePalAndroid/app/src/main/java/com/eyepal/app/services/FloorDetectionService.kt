package com.eyepal.app.services

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlin.math.abs

class FloorDetectionService(context: Context) : SensorEventListener {
    private val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val barometer = sensorManager.getDefaultSensor(Sensor.TYPE_PRESSURE)
    private val accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)

    private val _currentFloor = MutableStateFlow(0)
    val currentFloor: StateFlow<Int> = _currentFloor

    private val _statusText = MutableStateFlow("Detecting floor level...")
    val statusText: StateFlow<String> = _statusText

    private var baselinePressure = 1013.25f
    private var isCalibrated = false
    private var calibrationCount = 0
    private val calibrationReadings = mutableListOf<Float>()

    private val floorThreshold = 0.36f
    private val hPaPerFloor = 0.12f

    fun start() {
        barometer?.let { sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL) }
        accelerometer?.let { sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL) }
        _statusText.value = "Calibrating... Stand still."
    }

    fun stop() {
        sensorManager.unregisterListener(this)
    }

    fun calibrate() {
        calibrationReadings.clear()
        calibrationCount = 0
        isCalibrated = false
        _statusText.value = "Calibrating... Hold still."
    }

    override fun onSensorChanged(event: SensorEvent?) {
        event ?: return
        when (event.sensor.type) {
            Sensor.TYPE_PRESSURE -> handlePressure(event.values[0])
            Sensor.TYPE_ACCELEROMETER -> handleAcceleration(event.values)
        }
    }

    private fun handlePressure(pressure: Float) {
        if (!isCalibrated) {
            calibrationReadings.add(pressure)
            calibrationCount++
            if (calibrationCount >= 20) {
                baselinePressure = calibrationReadings.average().toFloat()
                isCalibrated = true
                _statusText.value = "Calibrated. Move between floors to detect."
            }
            return
        }

        val delta = baselinePressure - pressure
        val floor = (delta / hPaPerFloor).toInt()
        if (floor != _currentFloor.value) {
            _currentFloor.value = floor
            _statusText.value = if (floor == 0) "Current floor: Ground" else "Floor: $floor"
        }
    }

    private fun handleAcceleration(values: FloatArray) {
        val magnitude = abs(values[0]) + abs(values[1]) + abs(values[2])
        if (magnitude > 30) {
            _statusText.value = "Moving... detecting floor."
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
}
