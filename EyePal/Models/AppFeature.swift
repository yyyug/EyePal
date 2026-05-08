import Foundation

enum AppFeature: String, CaseIterable, Identifiable {
    case floorDetection
    case chat
    case faces
    case maps
    case quickRecognition
    case detailsRecognition
    case readText

    static let defaultOrder: [AppFeature] = [
        .floorDetection,
        .chat,
        .faces,
        .maps,
        .quickRecognition,
        .detailsRecognition,
        .readText,
    ]
    static let maxTabFeatureCount = 4

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .floorDetection:
            return "Floor Detection"
        case .chat:
            return "Chat"
        case .faces:
            return "Faces"
        case .maps:
            return "Maps"
        case .quickRecognition:
            return "Quick Recognition"
        case .detailsRecognition:
            return "Details Recognition"
        case .readText:
            return "Read Text"
        }
    }

    var tabTitle: String {
        switch self {
        case .floorDetection:
            return "Floor"
        case .chat:
            return "Chat"
        case .faces:
            return "Faces"
        case .maps:
            return "Maps"
        case .quickRecognition:
            return "Quick"
        case .detailsRecognition:
            return "Details"
        case .readText:
            return "Read Text"
        }
    }

    var systemImageName: String {
        switch self {
        case .floorDetection:
            return "building.2"
        case .chat:
            return "waveform.and.mic"
        case .faces:
            return "person.crop.rectangle"
        case .maps:
            return "map"
        case .quickRecognition:
            return "camera.viewfinder"
        case .detailsRecognition:
            return "sparkles.rectangle.stack"
        case .readText:
            return "text.viewfinder"
        }
    }

    static func normalizedOrder(from rawValues: [String]) -> [AppFeature] {
        var unique: [AppFeature] = []

        for rawValue in rawValues {
            guard let feature = AppFeature(rawValue: rawValue), !unique.contains(feature) else { continue }
            unique.append(feature)
        }

        // Migrate legacy order values created before floor/chat were introduced.
        if !unique.contains(.floorDetection) || !unique.contains(.chat) {
            return defaultOrder
        }

        for feature in defaultOrder where !unique.contains(feature) {
            unique.append(feature)
        }

        return unique
    }
}