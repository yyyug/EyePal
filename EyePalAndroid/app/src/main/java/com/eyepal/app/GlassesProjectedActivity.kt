package com.eyepal.app

import android.os.Bundle
import androidx.activity.ComponentActivity

/**
 * GlassesProjectedActivity handles the XR projected lifecycle for audio glasses.
 *
 * For audio glasses (no display), this activity stays alive to maintain the
 * projected activity lifecycle. The system uses this lifecycle to route
 * audio and camera through the projected context.
 *
 * Do NOT call finish() — the activity must remain alive while the glasses
 * are connected so the system can manage the projected device lifecycle.
 */
class GlassesProjectedActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Audio glasses have no display — do not setContent.
        // The activity stays alive to maintain the projected lifecycle.
    }

    override fun onResume() {
        super.onResume()
        // The projected device (glasses) is active while this activity resumes.
        // System will route audio/camera through the projected context.
    }

    override fun onPause() {
        super.onPause()
        // Glasses may be disconnecting or going to background.
    }

    override fun onDestroy() {
        super.onDestroy()
        // Projected context is destroyed when the device disconnects.
        // The system handles cleanup automatically.
    }
}
