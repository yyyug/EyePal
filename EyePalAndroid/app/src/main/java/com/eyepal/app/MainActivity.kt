package com.eyepal.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.eyepal.app.ui.EyePalApp
import com.eyepal.app.ui.theme.EyePalTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            EyePalTheme {
                EyePalApp()
            }
        }
    }

    override fun onDestroy() {
        if (!isChangingConfigurations) {
            (application as EyePalApplication).container.announcer.shutdown()
        }
        super.onDestroy()
    }
}
