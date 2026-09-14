package com.eyepal.app.services

import android.media.MediaRecorder
import android.os.Build
import android.util.Log
import java.io.File
import java.io.IOException

class FaceAudioRecorder(private val audioDir: File) {
    @Volatile
    var isRecording: Boolean = false
        private set

    private var recorder: MediaRecorder? = null
    private var outputFile: File? = null

    @Volatile
    var lastError: String? = null
        private set

    fun start(): Boolean {
        if (isRecording) return false
        lastError = null
        try {
            audioDir.mkdirs()
            val file = File.createTempFile("face_audio_", ".m4a", audioDir)
            val r = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder()
            } else {
                @Suppress("DEPRECATION")
                MediaRecorder()
            }
            @Suppress("DEPRECATION")
            r.setAudioSource(MediaRecorder.AudioSource.MIC)
            r.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            r.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            r.setAudioSamplingRate(44100)
            r.setAudioEncodingBitRate(64000)
            r.setAudioChannels(1)
            r.setOutputFile(file.absolutePath)
            r.prepare()
            r.start()
            recorder = r
            outputFile = file
            isRecording = true
            return true
        } catch (e: IOException) {
            lastError = "Failed to start recording: ${e.message}"
            Log.e("FaceAudioRec", lastError, e)
            releaseRecorder()
            return false
        } catch (e: Exception) {
            lastError = "Recording error: ${e.message}"
            Log.e("FaceAudioRec", lastError, e)
            releaseRecorder()
            return false
        }
    }

    fun stop(): File? {
        if (!isRecording) return null
        isRecording = false
        try {
            recorder?.stop()
        } catch (e: RuntimeException) {
            Log.e("FaceAudioRec", "stop() failed: ${e.message}", e)
            releaseRecorder()
            outputFile?.delete()
            outputFile = null
            lastError = "Recording failed: ${e.message}"
            return null
        } finally {
            releaseRecorder()
        }
        val file = outputFile?.takeIf { it.exists() && it.length() > 0 }
        outputFile = null
        return file
    }

    fun cancel() {
        if (!isRecording) {
            releaseRecorder()
            return
        }
        isRecording = false
        try { recorder?.stop() } catch (_: Exception) {}
        releaseRecorder()
        runCatching { outputFile?.delete() }
        outputFile = null
    }

    private fun releaseRecorder() {
        try {
            recorder?.release()
        } catch (_: Exception) {}
        recorder = null
    }
}