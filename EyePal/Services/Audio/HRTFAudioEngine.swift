import AVFoundation
import CoreLocation

/// HRTF-enabled spatial audio engine with advanced 3D rendering
@MainActor
final class HRTFAudioEngine: NSObject {
    // MARK: - Singleton
    static let shared = HRTFAudioEngine()
    
    // MARK: - Properties
    private let audioEngine = AVAudioEngine()
    private var environmentNodes: [AVAudioEnvironmentNode] = []
    private var activePlayers: [AudioPlayerNode] = []
    private var userHeading: Double = 0.0
    private var userLocation: CLLocation?
    
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
        
        // Configure reverb for spatial awareness
        reverbUnit.loadFactoryPreset(.cathedral)
        
        do {
            try audioEngine.start()
        } catch {
            print("❌ Audio engine startup failed: \(error)")
        }
    }
    
    // MARK: - HRTF Environment Node Creation
    func createEnvironmentNode() -> AVAudioEnvironmentNode {
        let environment = AVAudioEnvironmentNode()
        
        // High-quality HRTF rendering algorithm
        let format = audioEngine.outputNode.outputFormat(forBus: 0)
        audioEngine.attach(environment)
        audioEngine.connect(environment, to: reverbUnit, format: format)
        
        // Configure HRTF parameters
        environment.renderingAlgorithm = .HRTFHQ
        environment.distanceAttenuationParameters.referenceDistance = 1.0
        environment.distanceAttenuationParameters.maximumDistance = 100.0
        environment.distanceAttenuationParameters.rolloffFactor = 1.0
        
        // Enable reverb for spatial context
        environment.reverbParameters.enable = true
        environment.reverbParameters.loadFactoryReverbPreset(.cathedral)
        environment.reverbParameters.level = 0.15
        environment.reverbBlend = 0.15
        
        environmentNodes.append(environment)
        return environment
    }
    
    // MARK: - Listener Orientation Update
    func updateListenerHeading(_ heading: Double) {
        userHeading = heading
        
        for environment in environmentNodes {
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
        
        let environment = environmentNodes.last ?? createEnvironmentNode()
        
        let player = AVAudioPlayerNode()
        audioEngine.attach(player)
        audioEngine.connect(player, to: environment, format: format)
        
        // Set 3D position
        player.position = position
        
        // Generate audio buffer
        if let buffer = generateToneBuffer(frequency: frequency, format: format, duration: duration) {
            player.scheduleBuffer(buffer, at: nil, options: .interrupts) { [weak self, weak player] in
                guard let self, let player else { return }
                self.audioEngine.detach(player)
                self.activePlayers.removeAll { $0 === player }
            }
        }
        
        try? player.play()
        activePlayers.append(player)
    }
    
    // MARK: - Directional Audio Cues (for Soundscape compatibility)
    func playDirectionalCue(direction: SpatialDirection, frequency: Double? = nil) {
        let freq = frequency ?? direction.frequency
        play3DSound(frequency: freq, position: direction.point, duration: 0.16)
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
            // Smooth envelope to prevent clicks
            let envelope = min(1.0, Double(frame) / 600.0) * min(1.0, Double(Int(frameCount) - frame) / 600.0)
            channel[frame] = Float(sin(2 * .pi * frequency * progress) * 0.24 * envelope)
        }
        
        return buffer
    }
    
    // MARK: - Cleanup
    func stop() {
        for player in activePlayers {
            player.stop()
            audioEngine.detach(player)
        }
        activePlayers.removeAll()
    }
    
    deinit {
        try? audioEngine.stop()
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
