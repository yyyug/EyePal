import Foundation

struct LyricLine: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let startTime: Double?

    init(id: UUID = UUID(), text: String, startTime: Double? = nil) {
        self.id = id
        self.text = text
        self.startTime = startTime
    }
}

struct LyricSong: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var artist: String
    var lines: [LyricLine]
    var hasTimestamps: Bool
    let createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        artist: String,
        lines: [LyricLine],
        hasTimestamps: Bool,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.lines = lines
        self.hasTimestamps = hasTimestamps
        self.createdAt = createdAt
    }
}

struct LyricLLMResponse: Codable {
    let title: String
    let artist: String
    let hasTimestamps: Bool
    let lines: [LyricLLMLine]
}

struct LyricLLMLine: Codable {
    let text: String
    let startTime: Double?
}
