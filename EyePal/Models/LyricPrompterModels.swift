import Foundation

enum LyricLLMProvider: String, CaseIterable, Identifiable {
    case codex
    case gemini
    case openai

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex: return "ChatGPT (Codex)"
        case .gemini: return "Google Gemini"
        case .openai: return "OpenAI API"
        }
    }
}

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

struct LyricProviderModels {
    static let codex = ["gpt-4o-mini"]

    static let gemini = [
        "gemini-2.5-flash-preview-05-20",
        "gemini-2.0-flash",
        "gemini-2.0-flash-lite",
        "gemini-1.5-flash",
        "gemini-1.5-pro"
    ]

    static let openai = [
        "gpt-4o-mini",
        "gpt-4o",
        "gpt-4.1-mini",
        "gpt-4.1",
        "o4-mini",
        "o3",
        "gpt-3.5-turbo"
    ]
}
