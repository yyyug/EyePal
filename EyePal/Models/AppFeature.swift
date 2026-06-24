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
        switch self {
        case .floorDetection:
            return "Floor Detection"
        case .chat:
            return "Chat"
        case .faces:
            return "Faces"
        case .quickRecognition:
            return "Quick Recognition"
        case .detailsRecognition:
            return "Details Recognition"
        case .readText:
            return "Read Text"
        case .lyricPrompter:
            return "Lyric Prompter"
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
        case .quickRecognition:
            return "Quick"
        case .detailsRecognition:
            return "Details"
        case .readText:
            return "Read Text"
        case .lyricPrompter:
            return "Lyrics"
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
            return "Helps locate which floor you are on"
        case .chat:
            return "Real-time voice translation"
        case .faces:
            return "Face recognition and memory"
        case .quickRecognition:
            return "Snap a photo for instant scene description"
        case .detailsRecognition:
            return "Detailed scene description with follow-up chat"
        case .readText:
            return "OCR text recognition in multiple languages"
        case .lyricPrompter:
            return "Search and listen to song lyrics"
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