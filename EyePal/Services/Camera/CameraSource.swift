import Foundation

/// Which camera every recognition feature reads from.
///
/// Stored in `UserDefaults` rather than passed down, because each feature owns
/// its own `CameraPipeline` and all of them have to agree on one source.
enum CameraSource: String, CaseIterable, Identifiable {
    case phone
    case glasses

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .phone:
            return NSLocalizedString("cameraSource.phone", comment: "")
        case .glasses:
            return NSLocalizedString("cameraSource.glasses", comment: "")
        }
    }

    /// Glasses are only offered when the Wearables SDK is actually part of this
    /// build, so the picker never shows an option that cannot work.
    static var availableCases: [CameraSource] {
        MetaGlassesService.isLinked ? allCases : [.phone]
    }

    private static let storageKey = "camera.source"

    /// Read on the session queue as well as the main thread, so it is a plain
    /// lookup rather than something observed.
    static var current: CameraSource {
        CameraSource(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .phone
    }

    static func set(_ source: CameraSource) {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: storageKey) != source.rawValue else { return }
        defaults.set(source.rawValue, forKey: storageKey)
        NotificationCenter.default.post(name: .eyePalCameraSourceDidChange, object: nil)
    }
}

extension Notification.Name {
    static let eyePalCameraSourceDidChange = Notification.Name("eyePalCameraSourceDidChange")
}
