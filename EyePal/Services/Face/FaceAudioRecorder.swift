import AVFoundation
import Foundation

@MainActor
final class FaceAudioRecorder: NSObject {
    private var recorder: AVAudioRecorder?
    private var outputURL: URL?

    var isRecording: Bool { recorder?.isRecording ?? false }

    func start() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            return false
        }

        let fileName = "\(UUID().uuidString).m4a"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            outputURL = url
            self.recorder = recorder
            return recorder.record()
        } catch {
            return false
        }
    }

    func stop() -> URL? {
        guard let recorder else { return nil }
        guard recorder.isRecording else { return nil }
        recorder.stop()
        let url = outputURL
        self.recorder = nil
        outputURL = nil
        return url
    }

    func cancel() {
        guard let recorder else { return }
        if isRecording {
            recorder.stop()
        }
        if let url = outputURL {
            try? FileManager.default.removeItem(at: url)
        }
        self.recorder = nil
        outputURL = nil
    }
}