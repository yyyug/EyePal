package com.eyepal.app.services

import android.content.Context
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import org.webrtc.*
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.nio.ByteBuffer

class RealtimeWebRTCService(private val context: Context) {

    companion object {
        private const val TAG = "RealtimeWebRTC"
        private const val CHAT_URL = "https://api.openai.com/v1/realtime/calls?model=gpt-realtime-2"
        private const val TRANSLATE_URL = "https://api.openai.com/v1/realtime/translations/calls?model=gpt-realtime-translate"
    }

    private val ioScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var factory: PeerConnectionFactory? = null

    private var chatPc: PeerConnection? = null
    private var chatDc: DataChannel? = null
    private var chatAudioSource: AudioSource? = null
    private var chatLocalAudioTrack: AudioTrack? = null
    private var chatRemoteAudioTrack: AudioTrack? = null

    private var fwdPc: PeerConnection? = null
    private var fwdDc: DataChannel? = null
    private var fwdAudioSource: AudioSource? = null
    private var fwdLocalAudioTrack: AudioTrack? = null
    private var fwdRemoteAudioTrack: AudioTrack? = null

    private var revPc: PeerConnection? = null
    private var revDc: DataChannel? = null
    private var revAudioSource: AudioSource? = null
    private var revLocalAudioTrack: AudioTrack? = null
    private var revRemoteAudioTrack: AudioTrack? = null

    var onTranscript: ((String) -> Unit)? = null
    var onInputTranscript: ((String) -> Unit)? = null
    var onError: ((String) -> Unit)? = null
    var onStatusChange: ((String) -> Unit)? = null

    @Volatile
    private var connectedCount = 0

    fun initialize() {
        val initOptions = PeerConnectionFactory.InitializationOptions.builder(context)
            .setEnableInternalTracer(false)
            .createInitializationOptions()
        PeerConnectionFactory.initialize(initOptions)
        factory = PeerConnectionFactory.builder()
            .setOptions(PeerConnectionFactory.Options())
            .createPeerConnectionFactory()
    }

    // ── Chat Mode ───────────────────────────────────────────────

    fun connectChat(accessToken: String, instructions: String) {
        val iceServers = listOf(
            PeerConnection.IceServer.builder("stun:stun.l.google.com:19302").createIceServer(),
            PeerConnection.IceServer.builder("stun:stun1.l.google.com:19302").createIceServer()
        )
        val config = PeerConnection.RTCConfiguration(iceServers)

        val observer = createChatObserver()
        chatPc = factory?.createPeerConnection(config, observer)
            ?: run { onError?.invoke("Failed to create PeerConnection"); return }

        // Audio
        val audioConstraints = MediaConstraints().apply {
            mandatory.add(MediaConstraints.KeyValuePair("googEchoCancellation", "true"))
            mandatory.add(MediaConstraints.KeyValuePair("googAutoGainControl", "true"))
            mandatory.add(MediaConstraints.KeyValuePair("googNoiseSuppression", "true"))
        }
        chatAudioSource = factory?.createAudioSource(audioConstraints)
        chatLocalAudioTrack = factory?.createAudioTrack("voice-assistant-mic", chatAudioSource)
        chatPc?.addTrack(chatLocalAudioTrack, listOf("local"))

        // Data channel
        val dcInit = DataChannel.Init().apply { ordered = true }
        chatDc = chatPc?.createDataChannel("oai-events", dcInit)
        chatDc?.registerObserver(object : DataChannel.Observer {
            override fun onBufferedAmountChange(amount: Long) {}
            override fun onStateChange() {
                val state = chatDc?.state()
                Log.d(TAG, "Chat DC state: $state")
                if (state == DataChannel.State.OPEN) {
                    sendChatSessionUpdate(instructions)
                }
            }
            override fun onMessage(message: DataChannel.Buffer?) {
                message?.let { handleChatMessage(it) }
            }
        })

        // SDP offer
        val sdpConstraints = MediaConstraints().apply {
            mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveAudio", "true"))
        }
        chatPc?.createOffer(object : SdpObserver {
            override fun onCreateSuccess(sdp: SessionDescription) {
                chatPc?.setLocalDescription(object : SdpObserver {
                    override fun onSetSuccess() {
                        postSdpOffer(accessToken, CHAT_URL, sdp.description, chatPc)
                    }
                    override fun onSetFailure(error: String) { onError?.invoke("Local desc failed: $error") }
                    override fun onCreateSuccess(p0: SessionDescription?) {}
                    override fun onCreateFailure(p0: String?) {}
                }, sdp)
            }
            override fun onCreateFailure(error: String) { onError?.invoke("Offer failed: $error") }
            override fun onSetSuccess() {}
            override fun onSetFailure(error: String) {}
        }, sdpConstraints)
    }

    private fun createChatObserver() = object : PeerConnection.Observer {
        override fun onSignalingChange(state: PeerConnection.SignalingState) {}
        override fun onIceConnectionChange(state: PeerConnection.IceConnectionState) {
            when (state) {
                PeerConnection.IceConnectionState.FAILED,
                PeerConnection.IceConnectionState.DISCONNECTED,
                PeerConnection.IceConnectionState.CLOSED -> onStatusChange?.invoke("Disconnected")
                PeerConnection.IceConnectionState.CONNECTED -> onStatusChange?.invoke("Connected")
                else -> {}
            }
        }
        override fun onIceConnectionReceivingChange(receiving: Boolean) {}
        override fun onIceGatheringChange(state: PeerConnection.IceGatheringState) {}
        override fun onIceCandidate(candidate: IceCandidate) {}
        override fun onIceCandidatesRemoved(candidates: Array<IceCandidate>) {}
        override fun onAddStream(stream: MediaStream) {
            stream.audioTracks.firstOrNull()?.let { chatRemoteAudioTrack = it }
        }
        override fun onRemoveStream(stream: MediaStream) {}
        override fun onDataChannel(channel: DataChannel) {}
        override fun onRenegotiationNeeded() {}
        override fun onAddTrack(receiver: RtpReceiver, streams: Array<MediaStream>) {
            receiver.track()?.let { if (it is AudioTrack) chatRemoteAudioTrack = it }
        }
    }

    private fun sendChatSessionUpdate(instructions: String) {
        val sessionUpdate = JSONObject().apply {
            put("type", "session.update")
            put("session", JSONObject().apply {
                put("type", "realtime")
                put("instructions", instructions)
                put("input_audio_transcription", JSONObject().apply { put("model", "whisper-1") })
                put("turn_detection", JSONObject().apply {
                    put("type", "server_vad")
                    put("threshold", 0.5)
                    put("prefix_padding_ms", 300)
                    put("silence_duration_ms", 500)
                })
            })
        }
        sendDataChannelMessage(chatDc, sessionUpdate)
    }

    private fun handleChatMessage(buffer: DataChannel.Buffer) {
        val data = ByteArray(buffer.data.remaining())
        buffer.data.get(data)
        val text = String(data)
        try {
            val json = JSONObject(text)
            when (json.optString("type")) {
                "response.output_audio_transcript.done" -> {
                    val transcript = json.optString("transcript", "")
                    if (transcript.isNotEmpty()) onTranscript?.invoke(transcript)
                }
                "conversation.item.input_audio_transcription.completed" -> {
                    val transcript = json.optString("transcript", "")
                    if (transcript.isNotEmpty()) onInputTranscript?.invoke(transcript)
                }
                "error" -> {
                    val errorMsg = json.optJSONObject("error")?.optString("message") ?: "Unknown error"
                    onError?.invoke(errorMsg)
                }
                "session.created", "session.updated" -> Log.d(TAG, "Chat: ${json.optString("type")}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse chat DC message: $text", e)
        }
    }

    // ── Interpreter Mode ────────────────────────────────────────

    fun connectInterpreter(accessToken: String, langA: String, langB: String) {
        connectedCount = 0
        onStatusChange?.invoke("Connecting...")
        connectInterpreterPair(accessToken, langA, langB, isForward = true)
        connectInterpreterPair(accessToken, langB, langA, isForward = false)
    }

    private fun connectInterpreterPair(accessToken: String, sourceLang: String, targetLang: String, isForward: Boolean) {
        val label = if (isForward) "FWD" else "REV"
        val iceServers = listOf(
            PeerConnection.IceServer.builder("stun:stun.l.google.com:19302").createIceServer(),
            PeerConnection.IceServer.builder("stun:stun1.l.google.com:19302").createIceServer()
        )
        val config = PeerConnection.RTCConfiguration(iceServers)
        val observer = createInterpreterObserver(label, isForward)
        val pc = factory?.createPeerConnection(config, observer)
            ?: run { onError?.invoke("Failed to create $label PeerConnection"); return }

        val audioConstraints = MediaConstraints().apply {
            mandatory.add(MediaConstraints.KeyValuePair("googEchoCancellation", "true"))
            mandatory.add(MediaConstraints.KeyValuePair("googAutoGainControl", "true"))
            mandatory.add(MediaConstraints.KeyValuePair("googNoiseSuppression", "true"))
        }
        val audioSource = factory?.createAudioSource(audioConstraints)
        val localTrack = factory?.createAudioTrack("voice-mic-$label", audioSource)
        pc.addTrack(localTrack, listOf("local-$label"))

        val dcInit = DataChannel.Init().apply { ordered = true }
        val dc = pc.createDataChannel("oai-events", dcInit)
        dc.registerObserver(object : DataChannel.Observer {
            override fun onBufferedAmountChange(amount: Long) {}
            override fun onStateChange() {
                val state = dc.state()
                Log.d(TAG, "$label DC state: $state")
                if (state == DataChannel.State.OPEN) sendInterpreterSessionUpdate(dc, sourceLang, targetLang)
            }
            override fun onMessage(message: DataChannel.Buffer?) {
                message?.let { handleInterpreterMessage(it, isForward) }
            }
        })

        if (isForward) { fwdPc = pc; fwdDc = dc; fwdAudioSource = audioSource; fwdLocalAudioTrack = localTrack }
        else { revPc = pc; revDc = dc; revAudioSource = audioSource; revLocalAudioTrack = localTrack }

        val sdpConstraints = MediaConstraints().apply {
            mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveAudio", "true"))
        }
        pc.createOffer(object : SdpObserver {
            override fun onCreateSuccess(sdp: SessionDescription) {
                pc.setLocalDescription(object : SdpObserver {
                    override fun onSetSuccess() { postSdpOffer(accessToken, TRANSLATE_URL, sdp.description, pc) }
                    override fun onSetFailure(error: String) { onError?.invoke("$label local desc: $error") }
                    override fun onCreateSuccess(p0: SessionDescription?) {}
                    override fun onCreateFailure(p0: String?) {}
                }, sdp)
            }
            override fun onCreateFailure(error: String) { onError?.invoke("$label offer: $error") }
            override fun onSetSuccess() {}
            override fun onSetFailure(error: String) {}
        }, sdpConstraints)
    }

    private fun createInterpreterObserver(label: String, isForward: Boolean) = object : PeerConnection.Observer {
        override fun onSignalingChange(state: PeerConnection.SignalingState) {}
        override fun onIceConnectionChange(state: PeerConnection.IceConnectionState) {
            when (state) {
                PeerConnection.IceConnectionState.FAILED,
                PeerConnection.IceConnectionState.DISCONNECTED,
                PeerConnection.IceConnectionState.CLOSED -> onStatusChange?.invoke("$label Disconnected")
                PeerConnection.IceConnectionState.CONNECTED -> {
                    synchronized(this@RealtimeWebRTCService) {
                        connectedCount++
                        if (connectedCount >= 2) onStatusChange?.invoke("Connected")
                    }
                }
                else -> {}
            }
        }
        override fun onIceConnectionReceivingChange(receiving: Boolean) {}
        override fun onIceGatheringChange(state: PeerConnection.IceGatheringState) {}
        override fun onIceCandidate(candidate: IceCandidate) {}
        override fun onIceCandidatesRemoved(candidates: Array<IceCandidate>) {}
        override fun onAddStream(stream: MediaStream) {
            stream.audioTracks.firstOrNull()?.let {
                if (isForward) fwdRemoteAudioTrack = it else revRemoteAudioTrack = it
            }
        }
        override fun onRemoveStream(stream: MediaStream) {}
        override fun onDataChannel(channel: DataChannel) {}
        override fun onRenegotiationNeeded() {}
        override fun onAddTrack(receiver: RtpReceiver, streams: Array<MediaStream>) {
            receiver.track()?.let {
                if (it is AudioTrack) { if (isForward) fwdRemoteAudioTrack = it else revRemoteAudioTrack = it }
            }
        }
    }

    private fun sendInterpreterSessionUpdate(dc: DataChannel, sourceLang: String, targetLang: String) {
        val sessionUpdate = JSONObject().apply {
            put("type", "session.update")
            put("session", JSONObject().apply {
                put("audio", JSONObject().apply {
                    put("input", JSONObject().apply {
                        put("transcription", JSONObject().apply { put("model", "gpt-realtime-whisper") })
                    })
                    put("output", JSONObject().apply { put("language", targetLang) })
                })
                put("instructions", "You are a real-time interpreter. Translate speech from $sourceLang to $targetLang.")
            })
        }
        sendDataChannelMessage(dc, sessionUpdate)
    }

    private fun handleInterpreterMessage(buffer: DataChannel.Buffer, isForward: Boolean) {
        val data = ByteArray(buffer.data.remaining())
        buffer.data.get(data)
        val text = String(data)
        try {
            val json = JSONObject(text)
            when (json.optString("type")) {
                "conversation.item.input_audio_transcription.completed" -> {
                    val transcript = json.optString("transcript", "")
                    if (transcript.isNotEmpty()) {
                        val prefix = if (isForward) "Speaker A" else "Speaker B"
                        onInputTranscript?.invoke("$prefix: $transcript")
                        autoSwitchDirection(transcript, isForward)
                    }
                }
                "response.output_audio_transcript.done" -> {
                    val transcript = json.optString("transcript", "")
                    if (transcript.isNotEmpty()) {
                        val prefix = if (isForward) "Translated (A→B)" else "Translated (B→A)"
                        onTranscript?.invoke("$prefix: $transcript")
                    }
                }
                "error" -> onError?.invoke(json.optJSONObject("error")?.optString("message") ?: "Unknown error")
                "session.created", "session.updated" -> Log.d(TAG, "Interpreter ${if (isForward) "fwd" else "rev"}: ${json.optString("type")}")
            }
        } catch (e: Exception) { Log.e(TAG, "Parse error: $text", e) }
    }

    var languageA: String = "en"
    var languageB: String = "ja"

    private fun autoSwitchDirection(transcript: String, isForward: Boolean) {
        val detected = LanguageDetector.detectLanguage(transcript)
        if (detected == languageA && isForward) {
            // Speaker is using languageA on the forward session — keep forward output, suppress reverse
            fwdRemoteAudioTrack?.setEnabled(true)
            revRemoteAudioTrack?.setEnabled(false)
        } else if (detected == languageB && !isForward) {
            // Speaker is using languageB on the reverse session — keep reverse output, suppress forward
            fwdRemoteAudioTrack?.setEnabled(false)
            revRemoteAudioTrack?.setEnabled(true)
        } else if (detected == languageA && !isForward) {
            // Speaker switched to languageA on the reverse session — switch output to forward
            fwdRemoteAudioTrack?.setEnabled(true)
            revRemoteAudioTrack?.setEnabled(false)
        } else if (detected == languageB && isForward) {
            // Speaker switched to languageB on the forward session — switch output to reverse
            fwdRemoteAudioTrack?.setEnabled(false)
            revRemoteAudioTrack?.setEnabled(true)
        }
    }

    // ── Shared ──────────────────────────────────────────────────

    private fun postSdpOffer(accessToken: String, url: String, sdpOffer: String, targetPc: PeerConnection?) {
        ioScope.launch {
            var connection: HttpURLConnection? = null
            try {
                withContext(Dispatchers.IO) {
                    connection = URL(url).openConnection() as HttpURLConnection
                    connection!!.requestMethod = "POST"
                    connection!!.setRequestProperty("Content-Type", "application/sdp")
                    connection!!.setRequestProperty("Authorization", "Bearer $accessToken")
                    connection!!.doOutput = true
                    connection!!.connectTimeout = 15000
                    connection!!.readTimeout = 30000

                    connection!!.outputStream.use { it.write(sdpOffer.toByteArray(Charsets.UTF_8)); it.flush() }

                    val responseCode = connection!!.responseCode
                    if (responseCode != 200) {
                        val errorBody = connection!!.errorStream?.bufferedReader()?.readText() ?: "Unknown"
                        throw Exception("SDP exchange failed ($responseCode): $errorBody")
                    }

                    connection!!.inputStream.bufferedReader().use { reader ->
                        val answerSDP = reader.readText()
                        Log.d(TAG, "Got SDP answer (${answerSDP.length} chars)")
                        val answer = SessionDescription(SessionDescription.Type.ANSWER, answerSDP)

                        targetPc?.setRemoteDescription(object : SdpObserver {
                            override fun onSetSuccess() { onStatusChange?.invoke("Session establishing...") }
                            override fun onSetFailure(error: String) { onError?.invoke("Remote desc: $error") }
                            override fun onCreateSuccess(p0: SessionDescription?) {}
                            override fun onCreateFailure(p0: String?) {}
                        }, answer)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "SDP POST error", e)
                onError?.invoke("Network error: ${e.message}")
            } finally {
                connection?.disconnect()
            }
        }
    }

    private fun sendDataChannelMessage(dc: DataChannel?, msg: JSONObject) {
        val buffer = DataChannel.Buffer(ByteBuffer.wrap(msg.toString().toByteArray(Charsets.UTF_8)), false)
        dc?.send(buffer)
    }

    fun setRemoteAudioEnabled(enabled: Boolean) {
        chatRemoteAudioTrack?.setEnabled(enabled)
        fwdRemoteAudioTrack?.setEnabled(enabled)
        revRemoteAudioTrack?.setEnabled(enabled)
    }

    fun disconnect() {
        val closeEvent = JSONObject().put("type", "session.close")
        listOf(chatDc, fwdDc, revDc).forEach { sendDataChannelMessage(it, closeEvent) }

        listOf(chatPc, fwdPc, revPc).forEach { it?.close() }
        listOf(chatDc, fwdDc, revDc).forEach { it?.close() }
        listOf(chatLocalAudioTrack, fwdLocalAudioTrack, revLocalAudioTrack).forEach { it?.dispose() }
        listOf(chatAudioSource, fwdAudioSource, revAudioSource).forEach { it?.dispose() }

        chatPc = null; chatDc = null; chatAudioSource = null; chatLocalAudioTrack = null; chatRemoteAudioTrack = null
        fwdPc = null; fwdDc = null; fwdAudioSource = null; fwdLocalAudioTrack = null; fwdRemoteAudioTrack = null
        revPc = null; revDc = null; revAudioSource = null; revLocalAudioTrack = null; revRemoteAudioTrack = null
        connectedCount = 0
    }
}
