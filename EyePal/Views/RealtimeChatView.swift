import SwiftUI
import AVFoundation
import NaturalLanguage
import WebRTC

struct RealtimeChatView: View {
    enum ChatMode: String, CaseIterable, Identifiable {
        case interpreter = "Interpreter"
        case voiceAssistant = "Chat"

        var id: String { rawValue }
    }

    @EnvironmentObject private var openAIStore: OpenAISubscriptionStore
    @AppStorage("chatInterpreterLanguageA") private var interpreterLanguageA = "en"
    @AppStorage("chatInterpreterLanguageB") private var interpreterLanguageB = "ja"

    @State private var mode: ChatMode = .voiceAssistant
    @StateObject private var controller = RTCRealtimeChatController()

    var body: some View {
        List {
            Section("Chat") {
                Picker("Mode", selection: $mode) {
                    ForEach(ChatMode.allCases) { entry in
                        Text(entry.rawValue).tag(entry)
                    }
                }
                .pickerStyle(.segmented)

                if mode == .interpreter {
                    Picker("Language A", selection: $interpreterLanguageA) {
                        ForEach(RealtimeTranslationLanguage.supported) { language in
                            Text(language.displayName).tag(language.code)
                        }
                    }

                    Picker("Language B", selection: $interpreterLanguageB) {
                        ForEach(RealtimeTranslationLanguage.supported) { language in
                            Text(language.displayName).tag(language.code)
                        }
                    }

                    if interpreterLanguageA == interpreterLanguageB {
                        Text("Choose two different languages for two-way interpretation.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Button(controller.isConnected ? "Stop" : "Start Voice Chat") {
                    if controller.isConnected {
                        controller.stop()
                    } else {
                        beginVoiceChat()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!openAIStore.isSignedIn || controller.isConnecting || !canStartSession)

                if !openAIStore.isSignedIn {
                    Text("Sign in with ChatGPT from Details Description first.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Text(controller.statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if !controller.latestTranscript.isEmpty {
                    Text(controller.latestTranscript)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Chat Error",
            isPresented: Binding(
                get: { controller.errorMessage != nil },
                set: { if !$0 { controller.errorMessage = nil } }
            )
        ) {
            Button("OK") {
                controller.errorMessage = nil
            }
        } message: {
            Text(controller.errorMessage ?? "")
        }
        .onDisappear {
            controller.stop()
        }
    }

    private var canStartSession: Bool {
        if mode == .interpreter {
            return interpreterLanguageA != interpreterLanguageB
        }
        return true
    }

    private func beginVoiceChat() {
        Task {
            do {
                let credentials = try await openAIStore.activeCredentials()
                await controller.start(
                    accessToken: credentials.accessToken,
                    mode: mode,
                    languageA: interpreterLanguageA,
                    languageB: interpreterLanguageB
                )
            } catch {
                await MainActor.run {
                    controller.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct RealtimeTranslationLanguage: Identifiable {
    let code: String
    let displayName: String

    var id: String { code }

    private static let englishLocale = Locale(identifier: "en")

    static let supportedCodes = [
        "af", "ar", "az", "be", "bg", "bs", "ca", "cs", "cy", "da", "de", "el", "en", "es", "et",
        "fa", "fi", "fr", "gl", "he", "hi", "hr", "hu", "hy", "id", "is", "it", "iw", "ja", "kk",
        "kn", "ko", "lt", "lv", "mi", "mk", "mr", "ms", "ne", "nl", "no", "pl", "pt", "ro", "ru",
        "sk", "sl", "sr", "sv", "sw", "ta", "th", "tl", "tr", "uk", "ur", "vi", "zh"
    ]

    static let supported: [RealtimeTranslationLanguage] = {
        supportedCodes.map { code in
            let localeCode = code == "iw" ? "he" : code
            let label = englishLocale.localizedString(forLanguageCode: localeCode)
                ?? Locale.current.localizedString(forLanguageCode: localeCode)
                ?? code.uppercased()
            return RealtimeTranslationLanguage(code: code, displayName: "\(label) (\(code))")
        }
    }()
}

@MainActor
private final class RTCRealtimeChatController: NSObject, ObservableObject {
    @Published var isConnected = false
    @Published var isConnecting = false
    @Published var statusText = "Ready"
    @Published var latestTranscript = ""
    @Published var errorMessage: String?

    private let factory: RTCPeerConnectionFactory
    private var voiceAssistantSession: RealtimeVoiceAssistantSession?
    private var interpreterSessionManager: DualRealtimeTranslationSessionManager?

    override init() {
        RTCInitializeSSL()
        factory = RTCPeerConnectionFactory(
            encoderFactory: RTCDefaultVideoEncoderFactory(),
            decoderFactory: RTCDefaultVideoDecoderFactory()
        )
        super.init()
    }

    func start(
        accessToken: String,
        mode: RealtimeChatView.ChatMode,
        languageA: String,
        languageB: String
    ) async {
        guard !isConnected, !isConnecting else { return }

        isConnecting = true
        statusText = "Connecting..."
        latestTranscript = ""
        errorMessage = nil

        do {
            try configureAudioSession()

            switch mode {
            case .voiceAssistant:
                let session = RealtimeVoiceAssistantSession(factory: factory)
                voiceAssistantSession = session
                interpreterSessionManager = nil
                try await session.connect(accessToken: accessToken)
                session.onStatus = { [weak self] status in
                    Task { @MainActor in
                        self?.statusText = status
                    }
                }
                session.onTranscript = { [weak self] transcript in
                    Task { @MainActor in
                        self?.latestTranscript = transcript
                    }
                }
                session.onError = { [weak self] message in
                    Task { @MainActor in
                        self?.errorMessage = message
                    }
                }
                statusText = "Listening. Speak now."
            case .interpreter:
                let manager = DualRealtimeTranslationSessionManager(
                    factory: factory,
                    languageA: languageA,
                    languageB: languageB
                )
                interpreterSessionManager = manager
                voiceAssistantSession = nil
                manager.onStatus = { [weak self] status in
                    Task { @MainActor in
                        self?.statusText = status
                    }
                }
                manager.onTranscript = { [weak self] transcript in
                    Task { @MainActor in
                        self?.latestTranscript = transcript
                    }
                }
                manager.onError = { [weak self] message in
                    Task { @MainActor in
                        self?.errorMessage = message
                    }
                }
                try await manager.connect(accessToken: accessToken)
            }

            isConnected = true
            isConnecting = false
        } catch {
            stop()
            errorMessage = error.localizedDescription
            statusText = "Connection failed."
        }
    }

    func stop() {
        voiceAssistantSession?.stop()
        voiceAssistantSession = nil
        interpreterSessionManager?.stop()
        interpreterSessionManager = nil

        isConnected = false
        isConnecting = false
        statusText = "Ready"

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func configureAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try audioSession.setActive(true)
    }
}

private final class RealtimeVoiceAssistantSession: NSObject {
    var onStatus: ((String) -> Void)?
    var onTranscript: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private let factory: RTCPeerConnectionFactory
    private var peerConnection: RTCPeerConnection?
    private var dataChannel: RTCDataChannel?

    init(factory: RTCPeerConnectionFactory) {
        self.factory = factory
        super.init()
    }

    func connect(accessToken: String) async throws {
        let config = RTCConfiguration()
        config.iceServers = []
        config.sdpSemantics = .unifiedPlan

        let pcConstraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]
        )
        let pc = factory.peerConnection(with: config, constraints: pcConstraints, delegate: self)
        peerConnection = pc

        let audioSource = factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
        let audioTrack = factory.audioTrack(with: audioSource, trackId: "voice-assistant-mic")
        pc.add(audioTrack, streamIds: ["local"])

        let dcConfig = RTCDataChannelConfiguration()
        dcConfig.isOrdered = true
        let dc = pc.dataChannel(forLabel: "oai-events", configuration: dcConfig)
        dc?.delegate = self
        dataChannel = dc

        let offerConstraints = RTCMediaConstraints(
            mandatoryConstraints: ["OfferToReceiveAudio": "true"],
            optionalConstraints: nil
        )

        let offer = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RTCSessionDescription, Error>) in
            pc.offer(for: offerConstraints) { sdp, error in
                if let sdp {
                    continuation.resume(returning: sdp)
                } else {
                    continuation.resume(throwing: error ?? RTCChatError(message: "Offer generation failed."))
                }
            }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pc.setLocalDescription(offer) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/realtime/calls?model=gpt-realtime-2")!)
        request.httpMethod = "POST"
        request.setValue("application/sdp", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = offer.sdp.data(using: .utf8)

        let (answerData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: answerData, encoding: .utf8) ?? "Unknown"
            throw RTCChatError(message: "SDP exchange failed: \(body)")
        }

        guard let answerSDP = String(data: answerData, encoding: .utf8) else {
            throw RTCChatError(message: "Invalid SDP answer from server.")
        }

        let answer = RTCSessionDescription(type: .answer, sdp: answerSDP)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pc.setRemoteDescription(answer) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func stop() {
        dataChannel?.close()
        peerConnection?.close()
        dataChannel = nil
        peerConnection = nil
    }

    private func sendEvent(_ dict: [String: Any]) {
        guard let dc = dataChannel, dc.readyState == .open,
              let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        dc.sendData(RTCDataBuffer(data: data, isBinary: false))
    }
}

extension RealtimeVoiceAssistantSession: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        if newState == .failed || newState == .disconnected || newState == .closed {
            onStatus?("Disconnected.")
        }
    }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams: [RTCMediaStream]) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove rtpReceiver: RTCRtpReceiver) {}
}

extension RealtimeVoiceAssistantSession: RTCDataChannelDelegate {
    nonisolated func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        if dataChannel.readyState == .open {
            sendEvent([
                "type": "session.update",
                "session": [
                    "type": "realtime",
                    "instructions": "You are a helpful voice assistant for blind users. Respond concisely and clearly in audio.",
                    "input_audio_transcription": ["model": "whisper-1"],
                    "turn_detection": [
                        "type": "server_vad",
                        "threshold": 0.5,
                        "silence_duration_ms": 500,
                    ],
                ],
            ])
            onStatus?("Listening. Speak now.")
        }
    }

    nonisolated func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        guard let object = try? JSONSerialization.jsonObject(with: buffer.data) as? [String: Any] else { return }
        let eventType = object["type"] as? String ?? ""

        switch eventType {
        case "response.output_audio_transcript.done":
            let transcript = (object["transcript"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !transcript.isEmpty {
                onTranscript?(transcript)
                onStatus?("Listening. Speak now.")
            }
        case "conversation.item.input_audio_transcription.completed":
            let transcript = (object["transcript"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !transcript.isEmpty {
                onStatus?("You: \(transcript)")
            }
        case "error":
            let message = ((object["error"] as? [String: Any])?["message"] as? String) ?? "Unknown realtime error"
            onError?(message)
        default:
            break
        }
    }
}

private final class DualRealtimeTranslationSessionManager {
    enum Direction {
        case aToB
        case bToA
    }

    var onStatus: ((String) -> Void)?
    var onTranscript: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private let languageA: String
    private let languageB: String
    private let forwardSession: RealtimeTranslationSession
    private let reverseSession: RealtimeTranslationSession
    private var activeDirection: Direction = .aToB
    private var transcriptBuffer = ""

    init(factory: RTCPeerConnectionFactory, languageA: String, languageB: String) {
        self.languageA = languageA
        self.languageB = languageB
        forwardSession = RealtimeTranslationSession(factory: factory, sourceLabel: "\(languageA)->\(languageB)", targetLanguage: languageB)
        reverseSession = RealtimeTranslationSession(factory: factory, sourceLabel: "\(languageB)->\(languageA)", targetLanguage: languageA)

        forwardSession.onInputTranscriptCompleted = { [weak self] transcript in
            self?.handleInputTranscriptCompleted(transcript)
        }
        reverseSession.onInputTranscriptCompleted = { [weak self] transcript in
            self?.handleInputTranscriptCompleted(transcript)
        }

        forwardSession.onOutputTranscriptDelta = { [weak self] delta in
            self?.handleOutputDelta(delta, direction: .aToB)
        }
        reverseSession.onOutputTranscriptDelta = { [weak self] delta in
            self?.handleOutputDelta(delta, direction: .bToA)
        }

        forwardSession.onOutputTranscriptDone = { [weak self] in
            self?.handleOutputDone(direction: .aToB)
        }
        reverseSession.onOutputTranscriptDone = { [weak self] in
            self?.handleOutputDone(direction: .bToA)
        }

        forwardSession.onError = { [weak self] message in
            self?.onError?(message)
        }
        reverseSession.onError = { [weak self] message in
            self?.onError?(message)
        }
    }

    func connect(accessToken: String) async throws {
        async let forwardConnect: Void = forwardSession.connect(accessToken: accessToken)
        async let reverseConnect: Void = reverseSession.connect(accessToken: accessToken)
        _ = try await (forwardConnect, reverseConnect)

        applyActiveDirection(.aToB)
        onStatus?("Interpreter running. Speak either Language A or B.")
    }

    func stop() {
        forwardSession.stop()
        reverseSession.stop()
        transcriptBuffer = ""
    }

    private func handleInputTranscriptCompleted(_ transcript: String) {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let detectedDirection = detectDirection(from: trimmed), detectedDirection != activeDirection {
            applyActiveDirection(detectedDirection)
        }
    }

    private func handleOutputDelta(_ delta: String, direction: Direction) {
        guard direction == activeDirection else { return }
        guard !delta.isEmpty else { return }

        transcriptBuffer += delta
        onTranscript?(transcriptBuffer)
    }

    private func handleOutputDone(direction: Direction) {
        guard direction == activeDirection else { return }
        onStatus?("Listening. Speak now.")
    }

    private func applyActiveDirection(_ direction: Direction) {
        activeDirection = direction
        transcriptBuffer = ""
        onTranscript?("")

        let forwardEnabled = direction == .aToB
        forwardSession.setOutputAudioEnabled(forwardEnabled)
        reverseSession.setOutputAudioEnabled(!forwardEnabled)

        switch direction {
        case .aToB:
            onStatus?("Interpreting \(languageA) -> \(languageB)")
        case .bToA:
            onStatus?("Interpreting \(languageB) -> \(languageA)")
        }
    }

    private func detectDirection(from transcript: String) -> Direction? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(transcript)
        guard let language = recognizer.dominantLanguage else {
            return nil
        }

        let dominantCode = language.rawValue.lowercased()
        if dominantCode == languageA || dominantCode.hasPrefix("\(languageA)-") {
            return .aToB
        }
        if dominantCode == languageB || dominantCode.hasPrefix("\(languageB)-") {
            return .bToA
        }

        return nil
    }
}

private final class RealtimeTranslationSession: NSObject {
    var onInputTranscriptCompleted: ((String) -> Void)?
    var onOutputTranscriptDelta: ((String) -> Void)?
    var onOutputTranscriptDone: (() -> Void)?
    var onError: ((String) -> Void)?

    private let factory: RTCPeerConnectionFactory
    private let sourceLabel: String
    private let targetLanguage: String

    private var peerConnection: RTCPeerConnection?
    private var dataChannel: RTCDataChannel?
    private var remoteAudioTrack: RTCAudioTrack?

    init(factory: RTCPeerConnectionFactory, sourceLabel: String, targetLanguage: String) {
        self.factory = factory
        self.sourceLabel = sourceLabel
        self.targetLanguage = targetLanguage
        super.init()
    }

    func connect(accessToken: String) async throws {
        let config = RTCConfiguration()
        config.iceServers = []
        config.sdpSemantics = .unifiedPlan

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]
        )

        let pc = factory.peerConnection(with: config, constraints: constraints, delegate: self)
        peerConnection = pc

        let audioSource = factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
        let audioTrack = factory.audioTrack(with: audioSource, trackId: "interp-mic-\(targetLanguage)")
        pc.add(audioTrack, streamIds: ["local"])

        let channelConfig = RTCDataChannelConfiguration()
        channelConfig.isOrdered = true
        let channel = pc.dataChannel(forLabel: "oai-events", configuration: channelConfig)
        channel?.delegate = self
        dataChannel = channel

        let offerConstraints = RTCMediaConstraints(
            mandatoryConstraints: ["OfferToReceiveAudio": "true"],
            optionalConstraints: nil
        )

        let offer = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RTCSessionDescription, Error>) in
            pc.offer(for: offerConstraints) { sdp, error in
                if let sdp {
                    continuation.resume(returning: sdp)
                } else {
                    continuation.resume(throwing: error ?? RTCChatError(message: "Offer generation failed for \(self.sourceLabel)."))
                }
            }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pc.setLocalDescription(offer) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/realtime/translations/calls?model=gpt-realtime-translate")!)
        request.httpMethod = "POST"
        request.setValue("application/sdp", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = offer.sdp.data(using: .utf8)

        let (answerData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: answerData, encoding: .utf8) ?? "Unknown"
            throw RTCChatError(message: "SDP exchange failed for \(sourceLabel): \(body)")
        }

        guard let answerSDP = String(data: answerData, encoding: .utf8) else {
            throw RTCChatError(message: "Invalid SDP answer for \(sourceLabel).")
        }

        let answer = RTCSessionDescription(type: .answer, sdp: answerSDP)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pc.setRemoteDescription(answer) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func stop() {
        sendEvent(["type": "session.close"])
        dataChannel?.close()
        peerConnection?.close()
        remoteAudioTrack = nil
        dataChannel = nil
        peerConnection = nil
    }

    func setOutputAudioEnabled(_ enabled: Bool) {
        remoteAudioTrack?.isEnabled = enabled
    }

    private func sendEvent(_ event: [String: Any]) {
        guard let dc = dataChannel, dc.readyState == .open,
              let data = try? JSONSerialization.data(withJSONObject: event) else { return }
        dc.sendData(RTCDataBuffer(data: data, isBinary: false))
    }
}

extension RealtimeTranslationSession: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams: [RTCMediaStream]) {
        if let audioTrack = rtpReceiver.track as? RTCAudioTrack {
            remoteAudioTrack = audioTrack
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove rtpReceiver: RTCRtpReceiver) {}
}

extension RealtimeTranslationSession: RTCDataChannelDelegate {
    nonisolated func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        if dataChannel.readyState == .open {
            sendEvent([
                "type": "session.update",
                "session": [
                    "audio": [
                        "input": [
                            "transcription": ["model": "gpt-realtime-whisper"],
                            "noise_reduction": ["type": "near_field"],
                        ],
                        "output": [
                            "language": targetLanguage,
                        ],
                    ],
                ],
            ])
        }
    }

    nonisolated func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        guard let object = try? JSONSerialization.jsonObject(with: buffer.data) as? [String: Any] else { return }
        let eventType = object["type"] as? String ?? ""

        switch eventType {
        case "session.input_transcript.completed", "session.input_transcript.done":
            let transcript = ((object["transcript"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !transcript.isEmpty {
                onInputTranscriptCompleted?(transcript)
            }
        case "session.output_transcript.delta":
            let delta = (object["delta"] as? String) ?? ""
            if !delta.isEmpty {
                onOutputTranscriptDelta?(delta)
            }
        case "session.output_transcript.done", "session.output_transcript.completed":
            onOutputTranscriptDone?()
        case "error":
            let message = ((object["error"] as? [String: Any])?["message"] as? String) ?? "Unknown realtime error"
            onError?(message)
        default:
            break
        }
    }
}

private struct RTCChatError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
