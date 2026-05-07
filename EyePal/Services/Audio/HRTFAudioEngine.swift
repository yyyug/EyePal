import AVFoundation
import CoreLocation

/// HRTF-enabled spatial audio engine with advanced 3D rendering
@MainActor
final class HRTFAudioEngine: NSObject {
    // MARK: - Singleton
    static let shared = HRTFAudioEngine()
    
    // MARK: - Properties
    private let audioEngine = AVAudioEngine()
    private var environmentNode: AVAudioEnvironmentNode?
    private var pooledPlayers: [AudioPlayerNode] = []
    private var nextPlayerIndex = 0
    private var userHeading: Double = 0.0
    private var userLocation: CLLocation?
    private var maxDistance: Float = 100.0
    private var reverbBlend: Float = 0.15
    
    // MARK: - Audio Engine Configuration
    private let mainMixer: AVAudioMixerNode
    private let reverbUnit: AVAudioUnitReverb
    
    // MARK: - Initialization
    override init() {
        mainMixer = audioEngine.mainMixerNode
        reverbUnit = AVAudioUnitReverb()
        
        super.init()
        
        configureAudioSession()
        setupAudioEngine()
    }
    
    // MARK: - Audio Session Setup for Background Playback
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        
        do {
            // Playback mode allows background execution
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.mixWithOthers, .defaultToSpeaker, .duckOthers]
            )
            
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("❌ Audio session setup failed: \(error)")
        }
    }
    
    // MARK: - Audio Engine Setup
    private func setupAudioEngine() {
        audioEngine.attach(reverbUnit)
        audioEngine.connect(reverbUnit, to: mainMixer, format: nil)

        let environment = createEnvironmentNode()
        setupPlayerPool(count: 6, environment: environment)
        
        // Configure reverb for spatial awareness
        reverbUnit.loadFactoryPreset(.cathedral)
        
        do {
            try audioEngine.start()
        } catch {
            print("❌ Audio engine startup failed: \(error)")
        }
    }
    
    // MARK: - HRTF Environment Node Creation
    private func createEnvironmentNode() -> AVAudioEnvironmentNode {
        let environment = AVAudioEnvironmentNode()

        audioEngine.attach(environment)
        audioEngine.connect(environment, to: reverbUnit, format: nil)

        environment.renderingAlgorithm = .HRTFHQ
        environment.distanceAttenuationParameters.referenceDistance = 1.0
        environment.distanceAttenuationParameters.maximumDistance = maxDistance
        environment.distanceAttenuationParameters.rolloffFactor = 1.0

        environment.reverbParameters.enable = true
        environment.reverbParameters.loadFactoryReverbPreset(.cathedral)
        environment.reverbParameters.level = reverbBlend
        environment.reverbBlend = reverbBlend

        environmentNode = environment
        return environment
    }

    private func setupPlayerPool(count: Int, environment: AVAudioEnvironmentNode) {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1) else { return }
        pooledPlayers.removeAll()
        pooledPlayers.reserveCapacity(count)

        for _ in 0..<count {
            let player = AVAudioPlayerNode()
            audioEngine.attach(player)
            audioEngine.connect(player, to: environment, format: format)
            pooledPlayers.append(player)
        }
    }

    private func nextPlayer() -> AVAudioPlayerNode? {
        guard !pooledPlayers.isEmpty else { return nil }
        let index = nextPlayerIndex % pooledPlayers.count
        nextPlayerIndex = (nextPlayerIndex + 1) % pooledPlayers.count
        return pooledPlayers[index]
    }

    func applyMapsAudioSettings(maxDistanceMeters: Double, reverbBlend: Double) {
        maxDistance = Float(max(10, min(200, maxDistanceMeters)))
        self.reverbBlend = Float(max(0, min(0.5, reverbBlend)))

        if let environment = environmentNode {
            environment.distanceAttenuationParameters.maximumDistance = maxDistance
            environment.reverbParameters.level = self.reverbBlend
            environment.reverbBlend = self.reverbBlend
        }
    }
    
    // MARK: - Listener Orientation Update
    func updateListenerHeading(_ heading: Double) {
        userHeading = heading

        if let environment = environmentNode {
            environment.listenerAngularOrientation = AVAudio3DAngularOrientation(
                yaw: Float(heading),
                pitch: 0.0,
                roll: 0.0
            )
        }
    }
    
    // MARK: - 3D Spatial Audio Playback
    func play3DSound(
        frequency: Double,
        position: AVAudio3DPoint,
        duration: TimeInterval = 0.2,
        atLocation: CLLocation? = nil
    ) {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
        guard let format else { return }
        
        guard environmentNode != nil else { return }

        // Skip rather than restart — restarting during VoiceOver can crash
        guard audioEngine.isRunning else { return }

        guard let player = nextPlayer() else { return }
        player.stop()
        
        // Set 3D position
        player.position = position
        
        // Generate audio buffer
        if let buffer = generateToneBuffer(frequency: frequency, format: format, duration: duration) {
            player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        }

        try? player.play()
    }
    
    // MARK: - Directional Audio Cues (for Soundscape compatibility)
    func playDirectionalCue(direction: SpatialDirection, frequency: Double? = nil) {
        let freq = frequency ?? direction.frequency
        play3DSound(frequency: freq, position: direction.point, duration: 0.16)
    }

    func playSFX(_ sfx: SoundscapeSFX) {
        let steps = sfx.pattern
        for (index, step) in steps.enumerated() {
            let delay = DispatchTime.now() + (Double(index) * 0.11)
            DispatchQueue.main.asyncAfter(deadline: delay) { [weak self] in
                self?.play3DSound(
                    frequency: step.frequency,
                    position: step.direction.point,
                    duration: step.duration
                )
            }
        }
    }
    
    // MARK: - Tone Buffer Generation
    private func generateToneBuffer(
        frequency: Double,
        format: AVAudioFormat,
        duration: TimeInterval
    ) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        
        buffer.frameLength = frameCount
        guard let channel = buffer.floatChannelData?[0] else { return nil }
        
        for frame in 0 ..< Int(frameCount) {
            let progress = Double(frame) / format.sampleRate
            let rampUp = min(1.0, Double(frame) / 800.0)
            let rampDown = min(1.0, Double(Int(frameCount) - frame) / 800.0)
            let envelope = rampUp * rampDown
            // Add harmonics for a richer, more musical tone
            let fundamental = sin(2 * .pi * frequency * progress) * 0.18
            let harmonic2 = sin(4 * .pi * frequency * progress) * 0.055
            let harmonic3 = sin(6 * .pi * frequency * progress) * 0.018
            channel[frame] = Float((fundamental + harmonic2 + harmonic3) * envelope)
        }
        
        return buffer
    }
    
    // MARK: - Cleanup
    func stop() {
        for player in pooledPlayers {
            player.stop()
        }
    }
    
    deinit {
        try? audioEngine.stop()
    }
}

enum SoundscapeSFX {
    case markerCreated
    case markerReached
    case beaconArmed
    case beaconNearby
    case guidedRouteStarted
    /// Rising 3-tone chime played before location / callout announcements
    case calloutStart
    /// Descending 2-tone chime played after callout sequence ends
    case calloutEnd

    var pattern: [(frequency: Double, direction: SpatialDirection, duration: TimeInterval)] {
        switch self {
        case .markerCreated:
            return [(820, .center, 0.14), (1046, .right, 0.14)]
        case .markerReached:
            return [(523, .left, 0.14), (784, .center, 0.14), (1046, .right, 0.14)]
        case .beaconArmed:
            return [(440, .behind, 0.16), (659, .center, 0.12)]
        case .beaconNearby:
            return [(880, .ahead, 0.10), (880, .ahead, 0.10)]
        case .guidedRouteStarted:
            return [(523, .left, 0.12), (784, .center, 0.12), (1046, .right, 0.12)]
        case .calloutStart:
            // Ascending left→right chime — like Soundscape's sense_location.wav
            return [(392, .left, 0.10), (523, .center, 0.10), (659, .right, 0.14)]
        case .calloutEnd:
            return [(659, .center, 0.10), (392, .center, 0.10)]
        }
    }
}

// MARK: - Spatial Direction Enum (Soundscape-compatible)
enum SpatialDirection {
    case left
    case right
    case center
    case ahead
    case behind
    case custom(bearing: Double)
    
    var point: AVAudio3DPoint {
        switch self {
        case .left:
            return AVAudio3DPoint(x: -3, y: 0, z: -1)
        case .right:
            return AVAudio3DPoint(x: 3, y: 0, z: -1)
        case .center:
            return AVAudio3DPoint(x: 0, y: 0, z: -1)
        case .ahead:
            return AVAudio3DPoint(x: 0, y: 0, z: -1)
        case .behind:
            return AVAudio3DPoint(x: 0, y: 0, z: 1)
        case .custom(let bearing):
            let radians = bearing.degreesToRadians - .pi / 2
            return AVAudio3DPoint(
                x: Float(3 * cos(radians)),
                y: 0,
                z: Float(3 * sin(radians))
            )
        }
    }
    
    var frequency: Double {
        switch self {
        case .left: return 620
        case .center, .ahead: return 820
        case .right: return 980
        case .behind: return 440
        case .custom: return 700
        }
    }
}

// MARK: - AudioPlayerNode Type Alias
typealias AudioPlayerNode = AVAudioPlayerNode
