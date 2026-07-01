package com.eyepal.app

import android.os.Bundle
import androidx.activity.ComponentActivity

/**
 * GlassesProjectedActivity handles the XR projected lifecycle for audio glasses.
 * Audio glasses have NO display, so this activity does not render any UI.
 * Its sole purpose is to participate in the XR projected activity lifecycle
 * so the system can route audio and camera through the projected context.
 */
class GlassesProjectedActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Audio glasses have no display — nothing to render here.
        // The activity exists only so the XR projected lifecycle is managed
        // and the system can provide projected audio/camera to the main app.
        finish()
    }
}
