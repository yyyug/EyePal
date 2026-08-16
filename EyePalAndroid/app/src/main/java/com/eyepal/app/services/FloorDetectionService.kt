package com.eyepal.app.services

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import com.eyepal.app.R
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlin.math.abs

class FloorDetectionService(context: Context) : SensorEventListener {
    private val appContext = context.applicationContext
    private val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val barometer = sensorManager.getDefaultSensor(Sensor.TYPE_PRESSURE)
    private val accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)

    private val _currentFloor = MutableStateFlow(0)
    val currentFloor: StateFlow<Int> = _currentFloor

    private val _statusText = MutableStateFlow(appContext.getString(R.string.floor_status_detecting))
    val statusText: StateFlow<String> = _statusText
    private val _currentPressure = MutableStateFlow(1013.25f)
    val currentPressure: StateFlow<Float> = _currentPressure
    private val _baselinePressure = MutableStateFlow(1013.25f)
    val baselinePressureFlow: StateFlow<Float> = _baselinePressure

    private var baselinePressure = 1013.25f
    private var isCalibrated = false
    private var calibrationCount = 0
    private val calibrationReadings = mutableListOf<Float>()

    private val floorThreshold = 0.36f
    private val hPaPerFloor = 0.12f

    fun start() {
        barometer?.let { sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL) }
        accelerometer?.let { sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL) }
        _statusText.value = appContext.getString(R.string.floor_status_calibrating_stand)
    }

    fun stop() {
        sensorManager.unregisterListener(this)
    }

    fun calibrate() {
        synchronized(calibrationReadings) {
            calibrationReadings.clear()
            calibrationCount = 0
            isCalibrated = false
        }
        _statusText.value = appContext.getString(R.string.floor_status_calibrating_hold)
    }

    override fun onSensorChanged(event: SensorEvent?) {
        event ?: return
        when (event.sensor.type) {
            Sensor.TYPE_PRESSURE -> handlePressure(event.values[0])
            Sensor.TYPE_ACCELEROMETER -> handleAcceleration(event.values)
        }
    }

    private fun handlePressure(pressure: Float) {
        _currentPressure.value = pressure
        if (!isCalibrated) {
            synchronized(calibrationReadings) {
                calibrationReadings.add(pressure)
                calibrationCount++
                if (calibrationCount >= 20) {
                    baselinePressure = calibrationReadings.average().toFloat()
                    _baselinePressure.value = baselinePressure
                    isCalibrated = true
                }
            }
            if (isCalibrated) {
                _statusText.value = appContext.getString(R.string.floor_status_calibrated)
            }
            return
        }

        val delta = baselinePressure - pressure
        val floor = (delta / hPaPerFloor).toInt()
        if (floor != _currentFloor.value) {
            _currentFloor.value = floor
            _statusText.value = if (floor == 0) appContext.getString(R.string.floor_status_ground) else appContext.getString(R.string.floor_status_floor, floor)
        }
    }

    private fun handleAcceleration(values: FloatArray) {
        val magnitude = abs(values[0]) + abs(values[1]) + abs(values[2])
        if (magnitude > 30) {
            _statusText.value = appContext.getString(R.string.floor_status_moving)
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
}
