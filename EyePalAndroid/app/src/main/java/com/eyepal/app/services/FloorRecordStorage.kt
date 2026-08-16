package com.eyepal.app.services

import android.content.Context
import com.eyepal.app.models.FloorRecord
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File

object FloorRecordStorage {
    private val json = Json { ignoreUnknownKeys = true; prettyPrint = true }

    fun loadRecords(context: Context): List<FloorRecord> {
        val file = File(context.filesDir, "floor_records.json")
        if (!file.exists()) return emptyList()
        return try { json.decodeFromString<List<FloorRecord>>(file.readText()) } catch (_: Exception) { emptyList() }
    }

    fun saveRecords(context: Context, records: List<FloorRecord>) {
        try { File(context.filesDir, "floor_records.json").writeText(json.encodeToString(records)) } catch (_: Exception) {}
    }

    fun addRecord(context: Context, record: FloorRecord) {
        val records = loadRecords(context).toMutableList()
        records.add(0, record)
        saveRecords(context, records)
    }

    fun deleteRecord(context: Context, id: String) {
        val records = loadRecords(context).toMutableList()
        records.removeAll { it.id == id }
        saveRecords(context, records)
    }

    fun renameRecord(context: Context, id: String, newName: String) {
        val records = loadRecords(context).toMutableList()
        val index = records.indexOfFirst { it.id == id }
        if (index >= 0) {
            records[index] = records[index].copy(name = newName)
            saveRecords(context, records)
        }
    }

    fun updateRecord(context: Context, id: String, name: String, altitude: Double, floor: Int) {
        val records = loadRecords(context).toMutableList()
        val index = records.indexOfFirst { it.id == id }
        if (index >= 0) {
            records[index] = records[index].copy(name = name, altitude = altitude, floor = floor)
            saveRecords(context, records)
        }
    }
}
