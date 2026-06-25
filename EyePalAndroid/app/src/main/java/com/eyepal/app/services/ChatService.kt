package com.eyepal.app.services

import android.content.Context
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.InputStream
import java.util.concurrent.TimeUnit

class ChatService(private val context: Context) {
    private val _statusText = MutableStateFlow("Ready to start voice chat.")
    val statusText: StateFlow<String> = _statusText

    private val _isConnected = MutableStateFlow(false)
    val isConnected: StateFlow<Boolean> = _isConnected

    private val _transcript = MutableStateFlow("")
    val transcript: StateFlow<String> = _transcript

    private var audioTrack: AudioTrack? = null
    private var recordingJob: Job? = null
    private val client = OkHttpClient.Builder()
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .build()

    fun startVoiceChat(apiKey: String, mode: String, langA: String, langB: String) {
        _isConnected.value = true
        _statusText.value = "Connecting to voice service..."
        _transcript.value = ""

        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val sampleRate = 24000
        val bufferSize = AudioRecord.getMinBufferSize(
            sampleRate,
            android.media.AudioFormat.CHANNEL_IN_MONO,
            android.media.AudioFormat.ENCODING_PCM_16BIT
        )

        recordingJob = CoroutineScope(Dispatchers.IO).launch {
            try {
                val recorder = AudioRecord(
                    MediaRecorder.AudioSource.MIC,
                    sampleRate,
                    android.media.AudioFormat.CHANNEL_IN_MONO,
                    android.media.AudioFormat.ENCODING_PCM_16BIT,
                    bufferSize
                )

                audioTrack = AudioTrack.Builder()
                    .setAudioAttributes(
                        android.media.AudioAttributes.Builder()
                            .setUsage(android.media.AudioAttributes.USAGE_MEDIA)
                            .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SPEECH)
                            .build()
                    )
                    .setAudioFormat(
                        android.media.AudioFormat.Builder()
                            .setSampleRate(sampleRate)
                            .setChannelMask(android.media.AudioFormat.CHANNEL_OUT_MONO)
                            .setEncoding(android.media.AudioFormat.ENCODING_PCM_16BIT)
                            .build()
                    )
                    .setBufferSizeInBytes(bufferSize)
                    .build()

                recorder.startRecording()
                audioTrack?.play()
                _statusText.value = "Listening... Speak now."

                val buffer = ShortArray(bufferSize / 2)
                while (isActive && _isConnected.value) {
                    val read = recorder.read(buffer, 0, buffer.size)
                    if (read > 0) {
                        val audioData = buffer.copyOf(read)
                        processAudioChunk(audioData, sampleRate, apiKey, mode, langA, langB)
                    }
                }

                recorder.stop()
                recorder.release()
                audioTrack?.stop()
                audioTrack?.release()
            } catch (e: Exception) {
                _statusText.value = "Error: ${e.message}"
                _isConnected.value = false
            }
        }
    }

    private fun processAudioChunk(audioData: ShortArray, sampleRate: Int, apiKey: String, mode: String, langA: String, langB: String) {
        val pcmData = ShortToByteArray(audioData)
        val base64Audio = android.util.Base64.encodeToString(pcmData, android.util.Base64.NO_WRAP)

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val instruction = if (mode == "interpreter") {
                    "Translate speech from $langA to $langB and vice versa. Be concise."
                } else {
                    "You are a helpful voice assistant. Be concise."
                }

                val payload = JSONObject().apply {
                    put("model", "gpt-4o-audio-preview")
                    put("messages", org.json.JSONArray().apply {
                        put(JSONObject().apply {
                            put("role", "system")
                            put("content", instruction)
                        })
                        put(JSONObject().apply {
                            put("role", "user")
                            put("content", org.json.JSONArray().apply {
                                put(JSONObject().apply {
                                    put("type", "input_audio")
                                    put("input_audio", JSONObject().apply {
                                        put("data", base64Audio)
                                        put("format", "pcm16")
                                    })
                                })
                            })
                        })
                    })
                    put("max_tokens", 300)
                }

                val request = Request.Builder()
                    .url("https://api.openai.com/v1/chat/completions")
                    .post(payload.toString().toRequestBody("application/json".toMediaType()))
                    .header("Authorization", "Bearer $apiKey")
                    .build()

                val response = client.newCall(request).execute()
                val body = response.body?.string() ?: return@launch
                val json = JSONObject(body)
                val content = json.getJSONArray("choices").getJSONObject(0)
                    .getJSONObject("message").getString("content")

                _transcript.value = content
                _statusText.value = "Response received."
            } catch (_: Exception) {}
        }
    }

    private fun ShortToByteArray(shorts: ShortArray): ByteArray {
        val bytes = ByteArray(shorts.size * 2)
        for (i in shorts.indices) {
            bytes[i * 2] = (shorts[i].toInt() and 0xFF).toByte()
            bytes[i * 2 + 1] = (shorts[i].toInt() shr 8 and 0xFF).toByte()
        }
        return bytes
    }

    fun stop() {
        recordingJob?.cancel()
        recordingJob = null
        _isConnected.value = false
        _statusText.value = "Voice chat stopped."
        audioTrack?.stop()
        audioTrack?.release()
        audioTrack = null
    }
}
