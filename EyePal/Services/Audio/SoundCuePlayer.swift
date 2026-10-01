import AVFoundation
import Foundation

/// Short audio cues.
///
/// Separate from speech on purpose: these are plain sounds played through the
/// normal output while `AccessibilityAnnouncementCenter` keeps handling the
/// spoken results, so a cue can never interrupt an announcement mid-sentence.
final class SoundCuePlayer {
    static let shared = SoundCuePlayer()

    /// Played when a monitored floor is reached.
    static let floorArrival = "bluegraya10-elevator-chimenotification-ding-recreation-287560"

    /// Held while a capture is waiting on the model, so the wait is audible
    /// instead of looking like the tap did nothing.
    static let recognitionPending = "paftdrunk-pa-dr-acid-flatulence-175942"

    private var players: [String: AVAudioPlayer] = [:]

    private init() {}

    func play(_ name: String) {
        // The pending cue is short and the recognition path can retry, so a
        // repeat call should not cut the previous one off mid-sound.
        guard players[name] == nil else {
            players[name]?.currentTime = 0
            players[name]?.play()
            return
        }
        guard let url = Self.url(for: name), let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.prepareToPlay()
        player.play()
        players[name] = player
    }

    func stop(_ name: String) {
        players[name]?.stop()
    }

    private static func url(for name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "mp3", subdirectory: "Sounds")
    }
}
