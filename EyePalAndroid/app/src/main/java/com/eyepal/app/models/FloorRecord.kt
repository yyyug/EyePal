package com.eyepal.app.models

import kotlinx.serialization.Serializable

@Serializable
data class FloorRecord(
    val id: String,
    val floor: Int,
    val timestamp: Long = System.currentTimeMillis(),
    val note: String = ""
)
