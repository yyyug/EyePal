package com.eyepal.app.services

import android.content.Context
import com.eyepal.app.R
import com.eyepal.app.models.Floor
import com.eyepal.app.models.FloorPlace
import com.eyepal.app.models.FloorRecord
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File
import kotlin.math.pow

/**
 * Persists places and their floors as one JSON document.
 *
 * Only pressures are stored; heights are derived. Reading the old flat record
 * file is a one-off migration, kept so existing installs do not lose history.
 */
object FloorRecordStorage {
    private const val PLACES_FILE = "floor_places.json"
    private const val LEGACY_FILE = "floor_records.json"
    private const val ASSUMED_BASELINE_KPA = 1013.25

    private val json = Json { ignoreUnknownKeys = true; prettyPrint = true }

    fun loadPlaces(context: Context): List<FloorPlace> {
        val file = File(context.filesDir, PLACES_FILE)
        if (file.exists()) {
            return try {
                json.decodeFromString<List<FloorPlace>>(file.readText())
            } catch (_: Exception) {
                emptyList()
            }
        }
        val migrated = migrateLegacyRecords(context)
        if (migrated.isNotEmpty()) savePlaces(context, migrated)
        return migrated
    }

    fun savePlaces(context: Context, places: List<FloorPlace>) {
        try {
            File(context.filesDir, PLACES_FILE).writeText(json.encodeToString(places))
            File(context.filesDir, LEGACY_FILE).delete()
        } catch (_: Exception) {
        }
    }

    /**
     * The old model kept one row per saved floor with an absolute altitude and
     * no pressure. Group those rows by name, treat the lowest one as the
     * reference and rebuild pressures relative to it.
     */
    private fun migrateLegacyRecords(context: Context): List<FloorPlace> {
        val file = File(context.filesDir, LEGACY_FILE)
        if (!file.exists()) return emptyList()
        val legacy = try {
            json.decodeFromString<List<FloorRecord>>(file.readText())
        } catch (_: Exception) {
            return emptyList()
        }

        val order = mutableListOf<String>()
        val grouped = mutableMapOf<String, MutableList<FloorRecord>>()
        for (record in legacy) {
            val key = record.name.ifBlank {
                context.getString(R.string.floor_label, record.floor.toString())
            }
            if (grouped[key] == null) {
                grouped[key] = mutableListOf()
                order.add(key)
            }
            grouped[key]?.add(record)
        }

        return order.mapNotNull { name ->
            val records = grouped[name] ?: return@mapNotNull null
            val start = records.minByOrNull { it.altitude } ?: return@mapNotNull null
            val floors = records
                .filter { it.id != start.id }
                .map { record ->
                    Floor(
                        label = record.floor.toString(),
                        pressureKPa = pressureForHeight(
                            record.altitude - start.altitude,
                            ASSUMED_BASELINE_KPA
                        ) ?: ASSUMED_BASELINE_KPA
                    )
                }
            FloorPlace(
                name = name,
                startFloorLabel = start.floor.toString(),
                baselinePressureKPa = ASSUMED_BASELINE_KPA,
                floors = floors
            )
        }
    }

    private fun pressureForHeight(heightMeters: Double, baselineKPa: Double): Double? {
        if (baselineKPa <= 0 || heightMeters >= 44330.0) return null
        val pressure = baselineKPa * (1.0 - heightMeters / 44330.0).pow(5.255)
        return if (pressure.isFinite() && pressure > 0) pressure else null
    }
}
