import Foundation

enum AppFeature: String, CaseIterable, Identifiable {
    case floorDetection
    case chat
    case faces
    case quickRecognition
    case detailsRecognition
    case readText
    case lyricPrompter

    static let defaultOrder: [AppFeature] = [
        .floorDetection,
        .chat,
        .faces,
        .quickRecognition,
        .detailsRecognition,
        .readText,
        .lyricPrompter,
    ]
    static let maxTabFeatureCount = 4

    var id: String { rawValue }

    var displayName: String {
        NSLocalizedString(localizedKey, comment: "")
    }

    var tabTitle: String {
        NSLocalizedString(tabKey, comment: "")
    }

    var localizedKey: String {
        switch self {
        case .floorDetection: return "feature.floorDetection"
        case .chat: return "feature.chat"
        case .faces: return "feature.faceRecognition"
        case .quickRecognition: return "feature.quickRecognition"
        case .detailsRecognition: return "feature.detailsRecognition"
        case .readText: return "feature.readText"
        case .lyricPrompter: return "feature.lyricPrompter"
        }
    }

    var tabKey: String {
        switch self {
        case .floorDetection: return "tab.floor"
        case .chat: return "tab.chat"
        case .faces: return "tab.faces"
        case .quickRecognition: return "tab.quick"
        case .detailsRecognition: return "tab.details"
        case .readText: return "tab.readText"
        case .lyricPrompter: return "tab.lyrics"
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
        case .quickRecognition:
            return "camera.viewfinder"
        case .detailsRecognition:
            return "sparkles.rectangle.stack"
        case .readText:
            return "text.viewfinder"
        case .lyricPrompter:
            return "music.note.list"
        }
    }

    var featureDescription: String {
        switch self {
        case .floorDetection:
            return NSLocalizedString("feature.floorDetection.description", comment: "")
        case .chat:
            return NSLocalizedString("feature.chat.description", comment: "")
        case .faces:
            return NSLocalizedString("feature.faces.description", comment: "")
        case .quickRecognition:
            return NSLocalizedString("feature.quickRecognition.description", comment: "")
        case .detailsRecognition:
            return NSLocalizedString("feature.detailsRecognition.description", comment: "")
        case .readText:
            return NSLocalizedString("feature.readText.description", comment: "")
        case .lyricPrompter:
            return NSLocalizedString("feature.lyricPrompter.description", comment: "")
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