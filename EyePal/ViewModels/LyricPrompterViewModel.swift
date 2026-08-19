import Foundation
import UIKit

@MainActor
final class LyricPrompterViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var savedSongs: [LyricSong] = []
    @Published var currentSong: LyricSong?
    @Published var searchResults: [LyricSearchResult] = []
    @Published var searchLog: [String] = []
    @Published var isSearching = false
    @Published var isLoadingLyrics = false
    @Published var errorMessage: String?
    @Published var isPlaying = false

    private let service = LyricPrompterService()
    private let announcer = AccessibilityAnnouncementCenter()
    private var playbackTask: Task<Void, Never>?
    private var advanceOffset: TimeInterval = 0
    private weak var settingsStore: SettingsStore?
    private weak var openAIStore: OpenAISubscriptionStore?

    var savedSongsURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let base = appSupport.appendingPathComponent("EyePal", isDirectory: true)
        return base.appendingPathComponent("lyrics.json")
    }

    func bind(settings: SettingsStore, openAIStore: OpenAISubscriptionStore) {
        self.settingsStore = settings
        self.openAIStore = openAIStore
    }

    func loadSaved() {
        guard FileManager.default.fileExists(atPath: savedSongsURL.path),
              let data = try? Data(contentsOf: savedSongsURL),
              let songs = try? JSONDecoder().decode([LyricSong].self, from: data) else {
            savedSongs = []
            return
        }
        savedSongs = songs
    }

    func saveCurrentSong() {
        guard let song = currentSong else { return }
        if let index = savedSongs.firstIndex(where: { $0.id == song.id }) {
            savedSongs[index] = song
        } else {
            savedSongs.insert(song, at: 0)
        }
        persistSongs()
    }

    func deleteSong(_ song: LyricSong) {
        savedSongs.removeAll { $0.id == song.id }
        if currentSong?.id == song.id { currentSong = nil }
        persistSongs()
    }

    func selectSong(_ song: LyricSong) {
        currentSong = song
        searchText = "\(song.title) - \(song.artist)"
    }

    func search() async {
        let input = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        guard let settings = settingsStore else {
            errorMessage = "Settings unavailable."
            return
        }

        isSearching = true
        errorMessage = nil
        searchResults = []
        searchLog = ["Searching: \(input)"]

        let results = await service.searchAllSources(
            searchText: input,
            provider: LyricLLMProvider(rawValue: settings.lyricLLMProvider) ?? .codex,
            modelID: settings.lyricModelID,
            apiKey: settings.lyricAPIKey,
            baseURL: settings.lyricBaseURL,
            codexStore: openAIStore
        )

        if results.isEmpty {
            searchLog.append("No results found.")
            errorMessage = "No results found for \"\(input)\"."
            announcer.announce("No results found for \(input)", minimumInterval: 0)
            isSearching = false
        } else {
            for r in results {
                searchLog.append("[\(r.source)] \(r.trackName) - \(r.artistName) synced=\(r.hasSyncedLyrics)")
            }
            searchResults = results
            isSearching = false
        }
    }

    func loadSelectedResult(_ result: LyricSearchResult) {
        isLoadingLyrics = true
        currentSong = service.loadLyrics(from: result)
        isLoadingLyrics = false
    }

    func dismissResults() {
        searchResults = []
    }

    func playFromStart(offset: TimeInterval) {
        guard let song = currentSong, song.hasTimestamps else { return }
        stopPlayback()
        isPlaying = true
        advanceOffset = offset

        playbackTask = Task { [weak self] in
            guard let self else { return }
            let linesWithTime = song.lines.filter { $0.startTime != nil }
            guard let firstTime = linesWithTime.first?.startTime else {
                await MainActor.run { self.isPlaying = false }
                return
            }
            let waitTime = max(0, firstTime - offset)
            try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            guard !Task.isCancelled else { return }
            for line in linesWithTime {
                guard !Task.isCancelled else { break }
                await MainActor.run { self.announcer.announce(line.text, minimumInterval: 0) }
                if let nextTime = self.nextTimestamp(after: line.startTime!, in: linesWithTime) {
                    let delay = max(0, nextTime - line.startTime! - offset)
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
            await MainActor.run { self.isPlaying = false }
        }
    }

    func playFromNow(offset: TimeInterval) {
        guard let song = currentSong, song.hasTimestamps else { return }
        stopPlayback()
        isPlaying = true
        advanceOffset = offset

        // Focus will be moved by the view via @AccessibilityFocusState
        // The view observes isPlaying and focuses first line

        playbackTask = Task { [weak self] in
            guard let self else { return }
            let linesWithTime = song.lines.filter { $0.startTime != nil }
            guard linesWithTime.count >= 2 else {
                await MainActor.run { self.isPlaying = false }
                return
            }
            // First line is already focused by the view — VoiceOver reads it.
            // Start the timer from the first line's timestamp so we announce
            // the second line when its time arrives.
            for i in 1..<linesWithTime.count {
                guard !Task.isCancelled else { break }
                let prev = linesWithTime[i - 1]
                let curr = linesWithTime[i]
                let delay = max(0, curr.startTime! - prev.startTime! - offset)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await MainActor.run { self.announcer.announce(curr.text, minimumInterval: 0) }
            }
            await MainActor.run { self.isPlaying = false }
        }
    }

    func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        isPlaying = false
    }

    private func nextTimestamp(after time: Double, in lines: [LyricLine]) -> Double? {
        lines.first { $0.startTime! > time }?.startTime
    }

    private func persistSongs() {
        guard let data = try? JSONEncoder.prettyPrinted.encode(savedSongs) else { return }
        try? data.write(to: savedSongsURL, options: .atomic)
    }
}

private extension JSONEncoder {
    static var prettyPrinted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
