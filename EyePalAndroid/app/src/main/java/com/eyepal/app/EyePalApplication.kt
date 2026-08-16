package com.eyepal.app

import android.app.Application
import com.eyepal.app.di.AppContainer

class EyePalApplication : Application() {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
    }
}
