package com.eyepal.app.models

import androidx.compose.runtime.Stable
import kotlinx.serialization.Serializable

@Stable
@Serializable
data class FloorRecord(
    @Stable val id: String,
    @Stable val floor: Int,
    @Stable val timestamp: Long = System.currentTimeMillis(),
    @Stable val note: String = "",
    @Stable val name: String = "",
    @Stable val altitude: Double = 0.0
)