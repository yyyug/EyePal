import Foundation

enum AppFeature: String, CaseIterable, Identifiable {
    case quickRecognition
    case detailsRecognition
    case readText
    case maps
    case faces

    static let defaultOrder: [AppFeature] = AppFeature.allCases
    static let maxTabFeatureCount = 4

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .quickRecognition:
            return "Quick Recognition"
        case .detailsRecognition:
            return "Details Recognition"
        case .readText:
            return "Read Text"
        case .maps:
            return "Maps"
        case .faces:
            return "Faces"
        }
    }

    var tabTitle: String {
        switch self {
        case .quickRecognition:
            return "Quick"
        case .detailsRecognition:
            return "Details"
        case .readText:
            return "Read Text"
        case .maps:
            return "Maps"
        case .faces:
            return "Faces"
        }
    }

    var systemImageName: String {
        switch self {
        case .quickRecognition:
            return "camera.viewfinder"
        case .detailsRecognition:
            return "sparkles.rectangle.stack"
        case .readText:
            return "text.viewfinder"
        case .maps:
            return "map"
        case .faces:
            return "person.crop.rectangle"
        }
    }

    static func normalizedOrder(from rawValues: [String]) -> [AppFeature] {
        var unique: [AppFeature] = []

        for rawValue in rawValues {
            guard let feature = AppFeature(rawValue: rawValue), !unique.contains(feature) else { continue }
            unique.append(feature)
        }

        for feature in defaultOrder where !unique.contains(feature) {
            unique.append(feature)
        }

        return unique
    }
}