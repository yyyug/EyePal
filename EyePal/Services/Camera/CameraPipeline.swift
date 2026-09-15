import AVFoundation
import CoreImage
import SwiftUI
import UIKit

final class CameraPipeline: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case configuring
        case running
        case failed(String)
        case unauthorized
    }

    let session = AVCaptureSession()

    @Published private(set) var state: State = .idle

    var onSampleBuffer: ((CMSampleBuffer) -> Void)?

    private let sessionQueue = DispatchQueue(label: "com.eyepals.camera.session")
    private let outputQueue = DispatchQueue(label: "com.eyepals.camera.output")
    private let latestFrameQueue = DispatchQueue(label: "com.eyepals.camera.latest-frame")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let ciContext = CIContext()
    private var isConfigured = false
    private var latestSampleBuffer: CMSampleBuffer?
    // Accessed only on sessionQueue.
    private var shouldBeRunning = false
    // An interrupted session still reports isRunning == true but delivers no
    // frames, so restarts must not rely on isRunning alone.
    private var wasInterrupted = false
    private var interruptionObservers: [NSObjectProtocol] = []

    override init() {
        super.init()
        let center = NotificationCenter.default
        interruptionObservers.append(center.addObserver(
            forName: .AVCaptureSessionWasInterrupted,
            object: session,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.sessionQueue.async {
                self.wasInterrupted = true
            }
        })
        interruptionObservers.append(center.addObserver(
            forName: .AVCaptureSessionInterruptionEnded,
            object: session,
            queue: nil
        ) { [weak self] _ in
            self?.resumeIfNeeded()
        })
        interruptionObservers.append(center.addObserver(
            forName: .AVCaptureSessionRuntimeError,
            object: session,
            queue: nil
        ) { [weak self] _ in
            self?.resumeIfNeeded()
        })
        interruptionObservers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.resumeIfNeeded()
        })
    }

    deinit {
        interruptionObservers.forEach(NotificationCenter.default.removeObserver)
    }

    func start() {
        sessionQueue.async {
            self.shouldBeRunning = true
            self.startOnSessionQueue()
        }
    }

    func stop() {
        sessionQueue.async {
            self.shouldBeRunning = false
            self.wasInterrupted = false
            guard self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async {
                self.state = .idle
            }
        }
    }

    private func resumeIfNeeded() {
        sessionQueue.async {
            guard self.shouldBeRunning else { return }
            self.startOnSessionQueue()
        }
    }

    private func startOnSessionQueue() {
        configureIfNeeded()
        guard state != .unauthorized else { return }
        guard isConfigured else { return }
        if session.isRunning, !wasInterrupted { return }
        wasInterrupted = false
        session.startRunning()
        DispatchQueue.main.async {
            self.state = .running
        }
    }

    func currentFrameImage() -> UIImage? {
        guard let sampleBuffer = latestFrameQueue.sync(execute: { latestSampleBuffer }) else {
            return nil
        }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }

        // The video data output delivers buffers in the sensor's native (landscape)
        // orientation regardless of how the device is held. Physically rotate the
        // pixels to an upright portrait image (same approach used by face detection)
        // so OCR engines receive a truly upright image and don't depend on orientation
        // flags that rarely reflect the actual buffer rotation.
        let pixelW = CVPixelBufferGetWidth(pixelBuffer)
        let pixelH = CVPixelBufferGetHeight(pixelBuffer)
        let isPortraitBuffer = pixelH > pixelW
        let uprightCI = CIImage(cvPixelBuffer: pixelBuffer)
            .oriented(isPortraitBuffer ? .up : .right)
        guard let cgImage = ciContext.createCGImage(uprightCI, from: uprightCI.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }

        DispatchQueue.main.async {
            self.state = .configuring
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            let semaphore = DispatchSemaphore(value: 0)
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if !granted {
                    DispatchQueue.main.async {
                        self.state = .unauthorized
                    }
                }
                semaphore.signal()
            }
            semaphore.wait()
            guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        default:
            DispatchQueue.main.async {
                self.state = .unauthorized
            }
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .high

        do {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                throw CameraError.noCameraAvailable
            }

            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                throw CameraError.cannotAddInput
            }
            session.addInput(input)

            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            videoOutput.setSampleBufferDelegate(self, queue: outputQueue)

            guard session.canAddOutput(videoOutput) else {
                throw CameraError.cannotAddOutput
            }
            session.addOutput(videoOutput)

            session.commitConfiguration()
            isConfigured = true
        } catch {
            session.commitConfiguration()
            DispatchQueue.main.async {
                self.state = .failed(error.localizedDescription)
            }
        }
    }
}

extension CameraPipeline: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        latestFrameQueue.sync {
            latestSampleBuffer = sampleBuffer
        }
        onSampleBuffer?(sampleBuffer)
    }
}

private enum CameraError: LocalizedError {
    case noCameraAvailable
    case cannotAddInput
    case cannotAddOutput

    var errorDescription: String? {
        switch self {
        case .noCameraAvailable:
            return "No camera is available on this device."
        case .cannotAddInput:
            return "The camera input could not be configured."
        case .cannotAddOutput:
            return "The camera output could not be configured."
        }
    }
}
