import AVFoundation
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import UIKit

#if canImport(MWDATCore) && canImport(MWDATCamera)
import MWDATCamera
import MWDATCore

/// Pairing progress, flattened so the settings screen does not have to name an
/// SDK type that only exists in one half of the build.
enum MetaGlassesRegistrationState: Equatable {
    case notStarted
    case registering
    case registered
}

/// One pair of glasses reported by the SDK.
struct MetaGlassesDevice: Identifiable, Equatable {
    let id: String
    let name: String
}

/// Everything the settings screen needs to render, without exposing the SDK.
@MainActor
final class MetaGlassesService: ObservableObject {
    static let shared = MetaGlassesService()

    /// Set once `Wearables.configure()` has succeeded. Everything else in this
    /// type is gated on it, because touching `Wearables.shared` before
    /// `configure()` is a `fatalError` in the SDK rather than a thrown error,
    /// so there is no way to recover from it at the call site.
    private(set) var isConfigured = false
    private(set) var configurationError: String?

    private(set) var registrationState: MetaGlassesRegistrationState = .notStarted
    private(set) var devices: [MetaGlassesDevice] = []
    private(set) var hasCompatibleDevice = true
    private(set) var isStreaming = false
    private(set) var isStartingStream = false
    private(set) var lastError: String?

    /// Most recent decoded frame from the glasses camera. This is what the
    /// recognition features capture from when the glasses are the source.
    @Published private(set) var latestFrame: UIImage?

    /// JPEG data from an explicit `capturePhoto` request.
    @Published private(set) var capturedPhoto: UIImage?

    private var wearables: WearablesInterface?
    private var deviceSelector: AutoDeviceSelector?
    private var deviceSession: DeviceSession?
    private var camera: Camera?
    private var deviceMonitorTask: Task<Void, Never>?
    private var registrationTask: Task<Void, Never>?
    private var deviceStreamTask: Task<Void, Never>?
    private var compatibilityTokens: [String: AnyListenerToken] = [:]
    private var sessionStateToken: AnyListenerToken?
    private var streamStateToken: AnyListenerToken?
    private var videoFrameToken: AnyListenerToken?
    private var photoDataToken: AnyListenerToken?
    private let ciContext = CIContext()

    /// Meta documents only 2, 7, 15, 24 and 30 as legal stream frame rates.
    /// 2 is deliberate: every feature here reads stills, not video, and a slow
    /// stream leaves the glasses link free for the frames we actually ask for.
    private static let requestedFrameRate: UInt = 2

    private init() {}

    // MARK: - Configuration

    /// Brings the SDK up once per process.
    ///
    /// Returns false instead of throwing so every caller can degrade to "no
    /// glasses" rather than having to handle an error at each entry point. It is
    /// safe to call repeatedly; the SDK's `configure()` is not re-entrant, so it
    /// is attempted at most once.
    @discardableResult
    func configureIfNeeded() -> Bool {
        guard !Self.didAttemptConfigure else { return isConfigured }
        Self.didAttemptConfigure = true

        applyRuntimeCredentials()

        do {
            try Wearables.configure()
            isConfigured = true
            configurationError = nil
            wearables = Wearables.shared
            startObserving()
        } catch {
            isConfigured = false
            // The SDK's description names the bundle, app id and the credential
            // it rejected, which is the single most useful thing to show here.
            configurationError = error.localizedDescription
        }
        return isConfigured
    }

    private static var didAttemptConfigure = false

    private static func registrationState(from state: RegistrationState) -> MetaGlassesRegistrationState {
        switch state {
        case .registering: return .registering
        case .registered: return .registered
        default: return .notStarted
        }
    }

    /// Writes the credentials the user entered in Settings into the SDK's
    /// `MWDAT` Info.plist dictionary just before `configure()` reads it.
    ///
    /// The SDK reads these from the bundle at configure time, so injecting them
    /// here is what lets the app ship without developer credentials compiled in.
    private func applyRuntimeCredentials() {
        let credentials = MetaGlassesCredentials.current
        // `infoDictionary` hands back the bundle's live mutable dictionary, so
        // assigning through its subscript is what actually changes what the SDK
        // reads. Copying it into a local `var` would mutate a value-type copy
        // and have no effect at all.
        guard let info = Bundle.main.infoDictionary else { return }
        var mwdat = (info["MWDAT"] as? [String: Any]) ?? [:]

        // Only overwrite a build-time provided value when the user has entered
        // one, so a build that already carries credentials keeps working.
        func put(_ key: String, _ value: String) {
            let existing = (mwdat[key] as? String) ?? ""
            let resolved = value.isEmpty ? existing : value
            if !resolved.isEmpty { mwdat[key] = resolved }
        }

        put("MetaAppID", credentials.appID)
        put("ClientToken", credentials.clientToken)
        put("TeamID", credentials.teamID)

        info["MWDAT"] = mwdat
    }

    /// The SDK reuses the Info.plist value for its own developer-mode override.
    /// Credentials supplied in Settings take precedence because they were just
    /// written into the bundle by `applyRuntimeCredentials()`.
    var hasCredentials: Bool {
        MetaGlassesCredentials.current.isComplete
    }

    // MARK: - Observation

    private func startObserving() {
        guard let wearables else { return }

        registrationTask = Task { [weak self] in
            for await state in wearables.registrationStateStream() {
                self?.registrationState = Self.registrationState(from: state)
            }
        }

        deviceStreamTask = Task { [weak self] in
            for await devices in wearables.devicesStream() {
                self?.apply(devices: devices)
            }
        }
    }

    private func apply(devices identifiers: [DeviceIdentifier]) {
        devices = identifiers.map { identifier in
            let device = wearables?.deviceForIdentifier(identifier)
            return MetaGlassesDevice(
                id: identifier,
                name: device?.nameOrId() ?? String(describing: identifier)
            )
        }
        monitorCompatibility(identifiers: identifiers)
    }

    /// A glasses that needs a firmware update can never produce frames, and the
    /// failure otherwise looks like "the camera is broken".
    private func monitorCompatibility(identifiers: [DeviceIdentifier]) {
        let present = Set(identifiers.map { $0 })
        compatibilityTokens = compatibilityTokens.filter { present.contains($0.key) }

        for identifier in identifiers where compatibilityTokens[identifier] == nil {
            guard let device = wearables?.deviceForIdentifier(identifier) else { continue }
            let name = device.nameOrId()
            let token = device.addCompatibilityListener { [weak self] compatibility in
                guard compatibility == .deviceUpdateRequired else { return }
                Task { @MainActor in
                    self?.hasCompatibleDevice = false
                    self?.lastError = "\(name)"
                }
            }
            compatibilityTokens[identifier] = token
        }
    }

    // MARK: - Pairing

    /// Opens the Meta AI flow. The approval comes back as a URL, which
    /// `handleIncomingURL` must be given from the app root.
    func startRegistration() {
        guard configureIfNeeded(), let wearables else { return }
        isStartingStream = true
        Task { [weak self] in
            defer { self?.isStartingStream = false }
            do {
                try await wearables.startRegistration()
            } catch {
                self?.lastError = error.localizedDescription
            }
        }
    }

    /// Must be called for the `metaWearablesAction` callback, from the app root
    /// rather than from whichever screen happens to be showing. A callback that
    /// arrives while the pairing screen is not mounted is dropped, and pairing
    /// then loops back to the Meta AI app forever.
    func handleIncomingURL(_ url: URL) {
        guard configureIfNeeded() else { return }
        guard url.query?.contains("metaWearablesAction") == true else { return }
        Task { [weak self] in
            do {
                try await Wearables.shared.handleUrl(url)
            } catch {
                self?.lastError = error.localizedDescription
            }
        }
    }

    // MARK: - Streaming

    /// Starts the glasses camera and keeps the latest frame in `latestFrame`.
    func startStreaming() {
        guard configureIfNeeded(), let wearables else { return }
        guard deviceSession == nil else {
            if deviceSession?.state == .started, camera == nil { addCamera() }
            return
        }
        isStartingStream = true

        let selector = deviceSelector ?? AutoDeviceSelector(wearables: wearables)
        deviceSelector = selector

        // Auto-select only makes sense once, but a reconnect after the glasses
        // were folded needs to hear about the device coming back.
        if deviceMonitorTask == nil {
            deviceMonitorTask = Task { [weak self] in
                for await device in selector.activeDeviceStream() {
                    guard let self else { return }
                    if device == nil { self.stopStreamingSilently() }
                }
            }
        }

        Task { [weak self] in
            guard let self else { return }
            defer { self.isStartingStream = false }
            do {
                let session = try await wearables.createSession(deviceSelector: selector)
                self.deviceSession = session
                // Subscribe before start() so no initial transition is missed.
                self.observe(session: session)
                try session.start()
            } catch DeviceSessionError.noEligibleDevice {
                self.lastError = nil
                self.deviceSession = nil
            } catch {
                self.lastError = error.localizedDescription
                self.deviceSession = nil
            }
        }
    }

    private func observe(session: DeviceSession) {
        sessionStateToken = session.statePublisher.listen { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .started:
                    // A camera can only be added to a started session.
                    if self.camera == nil { self.addCamera() }
                case .idle, .stopped:
                    // The glasses cut their camera when doffed or folded.
                    self.camera = nil
                    self.deviceSession = nil
                    self.isStreaming = false
                    self.latestFrame = nil
                case .starting, .stopping, .paused:
                    self.isStreaming = false
                }
            }
        }
    }

    private func addCamera() {
        guard let session = deviceSession, session.state == .started else { return }
        let config = StreamConfiguration(
            videoCodec: .raw,
            resolution: .low,
            frameRate: Self.requestedFrameRate
        )
        do {
            guard let newCamera = try session.addCamera(config: config) else {
                lastError = nil
                return
            }
            camera = newCamera
            observe(stream: newCamera.stream)
            newCamera.stream.start()
        } catch {
            camera = nil
            lastError = error.localizedDescription
        }
    }

    private func observe(stream: MWDATCamera.Stream) {
        streamStateToken = stream.statePublisher.listen { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .streaming:
                    self.isStreaming = true
                    self.lastError = nil
                case .stopped, .waitingForDevice, .starting, .stopping, .paused:
                    self.isStreaming = false
                }
            }
        }

        videoFrameToken = stream.videoFramePublisher.listen { [weak self] videoFrame in
            guard let image = Self.image(from: videoFrame.sampleBuffer) else { return }
            Task { @MainActor in
                self?.latestFrame = image
            }
        }

        photoDataToken = stream.photoDataPublisher.listen { [weak self] photoData in
            guard let image = UIImage(data: photoData.data) else { return }
            Task { @MainActor in
                self?.capturedPhoto = image
            }
        }
    }

    /// `.raw` is requested so the sample buffer already carries a pixel buffer
    /// and no codec is involved. With `hvc1` the SDK hands back compressed
    /// samples that need a VideoToolbox session to turn into an image.
    private nonisolated static func image(from sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Explicit still capture. The SDK pauses the stream for this so the photo
    /// gets the whole link, which makes it sharper than a stream frame.
    func capturePhoto() {
        _ = camera?.stream.capturePhoto(format: .jpeg)
    }

    func stopStreaming() {
        stopStreamingSilently()
    }

    private func stopStreamingSilently() {
        camera?.stop()
        camera = nil
        deviceSession?.stop()
        deviceSession = nil
        isStreaming = false
        latestFrame = nil
    }

    func clearError() {
        lastError = nil
    }
}
#else
/// Placeholder so the settings screen and the Vision page compile unchanged when
/// the Wearables SDK is not part of the build.
@MainActor
final class MetaGlassesService: ObservableObject {
    static let shared = MetaGlassesService()
    static var isLinked: Bool { false }

    private(set) var isConfigured = false
    private(set) var configurationError: String? = NSLocalizedString("metaGlasses.notLinked", comment: "")
    private(set) var registrationState: MetaGlassesRegistrationState = .notStarted
    private(set) var devices: [MetaGlassesDevice] = []
    private(set) var hasCompatibleDevice = true
    private(set) var isStreaming = false
    private(set) var isStartingStream = false
    private(set) var lastError: String?
    private(set) var hasCredentials = false
    @Published private(set) var latestFrame: UIImage?
    @Published private(set) var capturedPhoto: UIImage?

    private init() {}
    @discardableResult func configureIfNeeded() -> Bool { false }
    func startRegistration() {}
    func handleIncomingURL(_ url: URL) {}
    func startStreaming() {}
    func stopStreaming() {}
    func capturePhoto() {}
    func clearError() {}
}
#endif

/// Developer credentials for the Wearables Developer Center, kept out of the
/// build. Entered once under Settings > Meta Glasses.
struct MetaGlassesCredentials: Equatable {
    var appID: String
    var clientToken: String
    var teamID: String

    var isComplete: Bool {
        !appID.isEmpty && !clientToken.isEmpty
    }

    private static let appIDKey = "metaGlasses.appID"
    private static let clientTokenKey = "metaGlasses.clientToken"
    private static let teamIDKey = "metaGlasses.teamID"

    static var current: MetaGlassesCredentials {
        let defaults = UserDefaults.standard
        return MetaGlassesCredentials(
            appID: defaults.string(forKey: appIDKey) ?? "",
            clientToken: defaults.string(forKey: clientTokenKey) ?? "",
            teamID: defaults.string(forKey: teamIDKey) ?? ""
        )
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(appID, forKey: Self.appIDKey)
        defaults.set(clientToken, forKey: Self.clientTokenKey)
        defaults.set(teamID, forKey: Self.teamIDKey)
    }
}
