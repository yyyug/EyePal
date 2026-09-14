package com.eyepal.app.services

import android.content.Context
import android.media.MediaPlayer
import android.media.AudioAttributes
import java.io.File

class FaceAudioPlayer(private val context: Context) {
    var onFinish: (() -> Unit)? = null

    val isPlaying: Boolean get() = player?.isPlaying == true

    private var player: MediaPlayer? = null

    fun play(file: File) {
        stop()
        if (!file.exists() || file.length() == 0L) return
        val callback = onFinish
        try {
            val newPlayer = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ASSISTANCE_ACCESSIBILITY)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
                setDataSource(file.absolutePath)
                setOnCompletionListener {
                    callback?.invoke()
                }
                prepare()
                start()
            }
            player = newPlayer
        } catch (e: Exception) {
            player = null
        }
    }

    fun stop() {
        try {
            player?.let {
                if (it.isPlaying) it.stop()
                it.release()
            }
        } catch (_: Exception) {}
        player = null
    }

    fun release() {
        stop()
        onFinish = null
    }
}