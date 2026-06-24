package com.eyepal.app

import android.app.Application
import com.eyepal.app.data.SettingsRepository

class EyePalApplication : Application() {
    val settingsRepository by lazy { SettingsRepository(this) }
}
