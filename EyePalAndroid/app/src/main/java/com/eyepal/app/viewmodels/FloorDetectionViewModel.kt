package com.eyepal.app.viewmodels

import android.app.Application
import androidx.compose.runtime.mutableStateOf
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.eyepal.app.EyePalApplication
import com.eyepal.app.R
import com.eyepal.app.models.Floor
import com.eyepal.app.models.FloorPlace
import com.eyepal.app.services.FloorRecordStorage
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import kotlin.math.pow
import kotlin.math.roundToInt

class FloorDetectionViewModel(application: Application) : AndroidViewModel(application) {
    private fun str(resId: Int): String = getApplication<Application>().getString(resId)
    private fun str(resId: Int, vararg args: Any?): String =
        getApplication<Application>().getString(resId, *args)

    val places = mutableStateOf<List<FloorPlace>>(emptyList())

    /** Null until the barometer has produced a real sample. */
    val currentPressureKPa = mutableStateOf<Double?>(null)

    private val container = (application as EyePalApplication).container
    private val floorService = container.floorDetectionService
    private val announcer = container.announcer

    init {
        places.value = FloorRecordStorage.loadPlaces(application)
        viewModelScope.launch {
            floorService.currentPressure.collectLatest {
                currentPressureKPa.value = it?.toDouble()
            }
        }
    }

    fun start() = floorService.start()

    fun stop() = floorService.stop()

    // MARK: - Places

    fun addPlace(name: String, startFloorLabel: String, pressureKPa: Double?): String? {
        val trimmedName = name.trim()
        val trimmedFloor = startFloorLabel.trim()
        if (trimmedName.isEmpty() || trimmedFloor.isEmpty() || pressureKPa == null) return null
        if (!pressureKPa.isFinite()) return null
        val place = FloorPlace(
            name = trimmedName,
            startFloorLabel = trimmedFloor,
            baselinePressureKPa = pressureKPa
        )
        places.value = places.value + place
        persist()
        return place.id
    }

    fun renamePlace(placeId: String, name: String) {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return
        updatePlace(placeId) { it.copy(name = trimmed) }
    }

    /** Corrects the reference floor's label. The pressure stays as recorded. */
    fun updateStartFloorLabel(placeId: String, label: String) {
        val trimmed = label.trim()
        if (trimmed.isEmpty()) return
        updatePlace(placeId) { it.copy(startFloorLabel = trimmed) }
    }

    fun deletePlace(placeId: String) {
        places.value = places.value.filterNot { it.id == placeId }
        persist()
    }

    /**
     * Re-captures the reference. Deliberately never automatic: a building with
     * low ceilings or a mezzanine would re-anchor from the wrong floor and every
     * stored height would go with it.
     */
    fun recalibrateBaseline(placeId: String, pressureKPa: Double) {
        if (!pressureKPa.isFinite()) return
        updatePlace(placeId) { it.copy(baselinePressureKPa = pressureKPa) }
        announcer.announce(str(R.string.floor_status_recalibrated), minimumInterval = 0)
    }

    /** Sets an existing recorded floor as the new reference (start) floor.
     * The chosen floor's pressure becomes the baseline, and its label becomes
     * the start floor label. All stored heights are recomputed from this new
     * reference.
     */
    fun setStartFloor(placeId: String, floorId: String) {
        val floorLabel = places.value.first { it.id == placeId }
            ?.floors?.firstOrNull { it.id == floorId }?.label
        updatePlace(placeId) { place ->
            val floor = place.floors.firstOrNull { it.id == floorId } ?: return@updatePlace place
            place.copy(
                baselinePressureKPa = floor.pressureKPa,
                startFloorLabel = floor.label
            )
        }
        announcer.announce(str(R.string.floor_status_start_floor_set, floorLabel ?: floorId), minimumInterval = 0)
    }

    // MARK: - Floors

    fun addFloor(placeId: String, label: String, pressureKPa: Double?) {
        val trimmed = label.trim()
        if (trimmed.isEmpty() || pressureKPa == null || !pressureKPa.isFinite()) return
        updatePlace(placeId) { it.copy(floors = it.floors + Floor(label = trimmed, pressureKPa = pressureKPa)) }
        announcer.announce(str(R.string.status_record_saved, trimmed), minimumInterval = 0)
    }

    /**
     * Renames a floor and optionally moves it to a corrected height. Height is
     * converted back into a pressure against the place's baseline so every
     * height stays derived from one reference.
     */
    fun updateFloor(placeId: String, floorId: String, label: String, heightMeters: Double?) {
        val trimmed = label.trim()
        if (trimmed.isEmpty()) return
        updatePlace(placeId) { place ->
            val floors = place.floors.map { floor ->
                if (floor.id != floorId) return@map floor
                val pressure = heightMeters
                    ?.let { pressureKPaForHeight(it, place.baselinePressureKPa) }
                    ?: floor.pressureKPa
                floor.copy(label = trimmed, pressureKPa = pressure)
            }
            place.copy(floors = floors)
        }
        announcer.announce(str(R.string.status_record_updated), minimumInterval = 0)
    }

    fun deleteFloor(placeId: String, floorId: String) {
        updatePlace(placeId) { place ->
            place.copy(floors = place.floors.filterNot { it.id == floorId })
        }
    }

    fun announceArrival(place: FloorPlace, floor: Floor) {
        val name = "${place.name} ${floor.label}"
        announcer.announce(str(R.string.floor_arrived, name), minimumInterval = 0)
    }

    fun announce(text: String) {
        announcer.announce(text, minimumInterval = 0)
    }

    // MARK: - Derived values

    /** Height above a reference pressure, in metres, via the standard barometric formula. */
    fun heightAboveBaseline(pressureKPa: Double, baselineKPa: Double): Double? {
        if (pressureKPa <= 0 || baselineKPa <= 0) return null
        if (!pressureKPa.isFinite() || !baselineKPa.isFinite()) return null
        return 44330.0 * (1.0 - (pressureKPa / baselineKPa).pow(1.0 / 5.255))
    }

    fun heightOf(floor: Floor, place: FloorPlace): Double? =
        heightAboveBaseline(floor.pressureKPa, place.baselinePressureKPa)

    fun drift(pressureKPa: Double, place: FloorPlace): Double? =
        heightAboveBaseline(pressureKPa, place.baselinePressureKPa)

    fun suggestedFloorLabel(pressureKPa: Double, place: FloorPlace): String? {
        val start = place.startFloorNumber ?: return null
        val height = heightAboveBaseline(pressureKPa, place.baselinePressureKPa) ?: return null
        return (start + (height / STOREY_HEIGHT_METERS).roundToInt()).toString()
    }

    /** Inverse of the barometric formula, used when the user corrects a height. */
    fun pressureKPaForHeight(heightMeters: Double, baselineKPa: Double): Double? {
        if (baselineKPa <= 0 || !baselineKPa.isFinite() || !heightMeters.isFinite()) return null
        if (heightMeters >= 44330.0) return null
        val pressure = baselineKPa * (1.0 - heightMeters / 44330.0).pow(5.255)
        return if (pressure.isFinite() && pressure > 0) pressure else null
    }

    fun hasArrived(place: FloorPlace, floor: Floor, pressureKPa: Double): Boolean {
        val target = heightOf(floor, place) ?: return false
        val current = heightAboveBaseline(pressureKPa, place.baselinePressureKPa) ?: return false
        return kotlin.math.abs(current - target) <= ARRIVAL_LEAD_METERS
    }

    private fun updatePlace(placeId: String, transform: (FloorPlace) -> FloorPlace) {
        places.value = places.value.map { if (it.id == placeId) transform(it) else it }
        persist()
    }

    private fun persist() {
        FloorRecordStorage.savePlaces(getApplication(), places.value)
    }

    override fun onCleared() {
        super.onCleared()
        floorService.stop()
    }

    companion object {
        /** Fixed storey height used only to suggest a floor number. */
        const val STOREY_HEIGHT_METERS = 3.0

        /** How close to the target counts as arrived, so the cue comes early. */
        const val ARRIVAL_LEAD_METERS = 0.2

        /** Drift worth mentioning at all. */
        const val DRIFT_NOTICE_METERS = 0.3
    }
}
