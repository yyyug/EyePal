package com.eyepal.app.models

import androidx.compose.runtime.Stable
import kotlinx.serialization.Serializable
import java.util.UUID

/**
 * A building the user visits, plus the reference its floors are measured from.
 *
 * The reference is a floor the user recognises ("1") rather than an abstract
 * calibration: asking which floor you are standing on is a question anyone can
 * answer.
 */
@Stable
@Serializable
data class FloorPlace(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val startFloorLabel: String,
    val baselinePressureKPa: Double,
    val floors: List<Floor> = emptyList()
) {
    val startFloorNumber: Int?
        get() = startFloorLabel.trim().toIntOrNull()
}

/**
 * One floor inside a place.
 *
 * Only the pressure is stored. The height is always recomputed from the place's
 * baseline, so recalibrating the baseline corrects every floor's displayed height
 * at once instead of leaving heights captured under a stale reference.
 */
@Stable
@Serializable
data class Floor(
    val id: String = UUID.randomUUID().toString(),
    val label: String,
    val pressureKPa: Double
)
