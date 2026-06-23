import Foundation

enum LyricPrompterError: LocalizedError {
    case notSignedIn
    case invalidResponse
    case emptyResponse
    case backendError(String)
    case missingAPIKey
    case invalidJSON
    case noResults

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in with ChatGPT to search for lyrics."
        case .invalidResponse:
            return "The response could not be read."
        case .emptyResponse:
            return "No lyrics were found."
        case .backendError(let message):
            return message
        case .missingAPIKey:
            return "API key is required for this provider."
        case .invalidJSON:
            return "The AI returned invalid data. Please try again."
        case .noResults:
            return "No lyrics found for this song."
        }
    }
}

final class LyricPrompterService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Multi-source search

    func searchAllSources(
        searchText: String,
        provider: LyricLLMProvider,
        modelID: String,
        apiKey: String,
        baseURL: String,
        codexStore: OpenAISubscriptionStore?
    ) async -> [LyricSearchResult] {
        let (title, artist) = parseSearchInput(searchText)

        async let lrclibResults = searchLRCLIB(title: title, artist: artist)
        async let neteaseResults = searchNetEase(title: title, artist: artist)

        var allResults = await (lrclibResults, neteaseResults)

        var results = allResults.0 + allResults.1

        var deduplicated: [LyricSearchResult] = []
        var seenKeys: Set<String> = []
        for result in results {
            let key = "\(result.trackName.lowercased())-\(result.artistName.lowercased())"
            if seenKeys.contains(key) { continue }
            seenKeys.insert(key)
            deduplicated.append(result)
        }

        return deduplicated
    }

    // MARK: - LRCLIB

    private func searchLRCLIB(title: String, artist: String) async -> [LyricSearchResult] {
        var urlStr = "https://lrclib.net/api/search?track_name=\(title.urlEncoded)"
        if !artist.isEmpty {
            urlStr += "&artist_name=\(artist.urlEncoded)"
        }
        guard let url = URL(string: urlStr) else { return [] }

        var request = URLRequest(url: url)
        request.setValue("LyricPrompter-EyePal/1.0", forHTTPHeaderField: "User-Agent")

        guard let (data, _) = try? await session.data(for: request) else { return [] }
        guard let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

        return items.compactMap { item in
            guard let trackName = item["trackName"] as? String,
                  let artistName = item["artistName"] as? String else { return nil }
            let albumName = item["albumName"] as? String
            let syncedLyrics = item["syncedLyrics"] as? String
            let plainLyrics = item["plainLyrics"] as? String
            return LyricSearchResult(
                source: .lrclib,
                trackName: trackName,
                artistName: artistName,
                albumName: albumName,
                hasSyncedLyrics: syncedLyrics != nil && !syncedLyrics!.isEmpty,
                syncedLyrics: syncedLyrics,
                plainLyrics: plainLyrics
            )
        }
    }

    // MARK: - NetEase (網易雲)

    private func searchNetEase(title: String, artist: String) async -> [LyricSearchResult] {
        let searchURL = "https://music.163.com/api/search/get/web?s=\((title + " " + artist).urlEncoded)&type=1&limit=5"
        guard let url = URL(string: searchURL) else { return [] }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.163.com", forHTTPHeaderField: "Referer")

        guard let (data, _) = try? await session.data(for: request) else { return [] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let songs = result["songs"] as? [[String: Any]] else { return [] }

        var results: [LyricSearchResult] = []

        for song in songs.prefix(5) {
            guard let songID = song["id"] as? Int,
                  let name = song["name"] as? String else { continue }

            let artists = (song["artists"] as? [[String: Any]]) ?? []
            let artistName = artists.compactMap { $0["name"] as? String }.joined(separator: ", ")
            let album = (song["album"] as? [String: Any])
            let albumName = album?["name"] as? String

            if let lyrics = await fetchNetEaseLyrics(songID: songID) {
                results.append(LyricSearchResult(
                    source: .netease,
                    trackName: name,
                    artistName: artistName,
                    albumName: albumName,
                    hasSyncedLyrics: lyrics.hasSynced,
                    syncedLyrics: lyrics.synced,
                    plainLyrics: lyrics.plain
                ))
            }
        }

        return results
    }

    private func fetchNetEaseLyrics(songID: Int) async -> (synced: String?, plain: String?, hasSynced: Bool)? {
        let urlStr = "https://music.163.com/api/song/lyric?id=\(songID)&lv=1&tv=1"
        guard let url = URL(string: urlStr) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.163.com", forHTTPHeaderField: "Referer")

        guard let (data, _) = try? await session.data(for: request) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let lrc = json["lrc"] as? [String: Any],
              let plainLyrics = lrc["lyric"] as? String else { return nil }

        let tlrc = json["tlyric"] as? [String: Any]
        let translatedLyrics = tlrc?["lyric"] as? String

        let hasSynced = plainLyrics.contains("[0")

        let synced = hasSynced ? plainLyrics : nil
        let plain = hasSynced ? extractPlainFromLRC(plainLyrics) : plainLyrics

        return (synced: synced, plain: plain, hasSynced: hasSynced)
    }

    // MARK: - Load selected lyrics

    func loadLyrics(from result: LyricSearchResult) -> LyricSong {
        if let synced = result.syncedLyrics, result.hasSyncedLyrics {
            let lines = parseLRC(synced)
            return LyricSong(
                title: result.trackName,
                artist: result.artistName,
                lines: lines,
                hasTimestamps: true
            )
        } else if let plain = result.plainLyrics {
            let lines = plain.components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map { LyricLine(text: $0) }
            return LyricSong(
                title: result.trackName,
                artist: result.artistName,
                lines: lines,
                hasTimestamps: false
            )
        }
        return LyricSong(title: result.trackName, artist: result.artistName, lines: [], hasTimestamps: false)
    }

    // MARK: - LLM fallback

    func searchLyricsLLM(
        title: String,
        artist: String,
        provider: LyricLLMProvider,
        modelID: String,
        apiKey: String,
        baseURL: String,
        codexStore: OpenAISubscriptionStore?
    ) async throws -> LyricLLMResponse {
        switch provider {
        case .codex:
            return try await searchLyricsCodex(title: title, artist: artist, modelID: modelID, store: codexStore)
        case .gemini:
            return try await searchLyricsGemini(title: title, artist: artist, modelID: modelID, apiKey: apiKey, baseURL: baseURL)
        case .openai:
            return try await searchLyricsOpenAI(title: title, artist: artist, modelID: modelID, apiKey: apiKey, baseURL: baseURL)
        }
    }

    // MARK: - Codex

    private func searchLyricsCodex(title: String, artist: String, modelID: String, store: OpenAISubscriptionStore?) async throws -> LyricLLMResponse {
        guard let store else { throw LyricPrompterError.notSignedIn }
        let credentials = try await store.activeCredentials(forceRefresh: false)

        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/codex/responses")!)
        request.httpMethod = "POST"
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("EyePal/1.0", forHTTPHeaderField: "User-Agent")
        if let accountID = credentials.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-ID")
        }

        let body: [String: Any] = [
            "model": modelID,
            "instructions": makeInstructions(),
            "store": false,
            "stream": true,
            "tools": [["type": "web_search"]],
            "tool_choice": "auto",
            "input": [["role": "user", "content": [["type": "input_text", "text": makeLyricPrompt(title: title, artist: artist)]]]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw LyricPrompterError.invalidResponse }
        if httpResponse.statusCode == 401 {
            _ = try await store.activeCredentials(forceRefresh: true)
            return try await searchLyricsCodex(title: title, artist: artist, modelID: modelID, store: store)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let data = try await collectData(from: bytes)
            throw LyricPrompterError.backendError(String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)")
        }
        return try parseLyricJSON(try await readStreamedResponse(from: bytes))
    }

    // MARK: - Gemini

    private func searchLyricsGemini(title: String, artist: String, modelID: String, apiKey: String, baseURL: String) async throws -> LyricLLMResponse {
        guard !apiKey.isEmpty else { throw LyricPrompterError.missingAPIKey }
        let base = baseURL.isEmpty ? "https://generativelanguage.googleapis.com/v1beta" : baseURL
        guard let url = URL(string: "\(base)/models/\(modelID):generateContent?key=\(apiKey)") else { throw LyricPrompterError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = ["contents": [["parts": [["text": makeInstructions() + "\n\n" + makeLyricPrompt(title: title, artist: artist)]]]], "generationConfig": ["temperature": 0.3, "maxOutputTokens": 4096]]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw LyricPrompterError.backendError(String(data: data, encoding: .utf8) ?? "Error")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else { throw LyricPrompterError.invalidResponse }
        return try parseLyricJSON(text)
    }

    // MARK: - OpenAI API

    private func searchLyricsOpenAI(title: String, artist: String, modelID: String, apiKey: String, baseURL: String) async throws -> LyricLLMResponse {
        guard !apiKey.isEmpty else { throw LyricPrompterError.missingAPIKey }
        let base = baseURL.isEmpty ? "https://api.openai.com/v1" : baseURL
        guard let url = URL(string: "\(base)/chat/completions") else { throw LyricPrompterError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = ["model": modelID, "temperature": 0.3, "max_tokens": 4096, "messages": [["role": "system", "content": makeInstructions()], ["role": "user", "content": makeLyricPrompt(title: title, artist: artist)]]]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw LyricPrompterError.backendError(String(data: data, encoding: .utf8) ?? "Error")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let content = choices.first?["message"] as? [String: Any],
              let text = content["content"] as? String else { throw LyricPrompterError.invalidResponse }
        return try parseLyricJSON(text)
    }

    // MARK: - Shared helpers

    private func makeInstructions() -> String {
        "You are a lyrics search assistant. You search the web for song lyrics and return structured JSON data. Always respond with ONLY valid JSON, no markdown, no explanation, no code fences."
    }

    private func makeLyricPrompt(title: String, artist: String) -> String {
        "Find the lyrics for \"\(title)\" by \"\(artist)\". Return ONLY a JSON object with no other text. The JSON must have this exact structure: {\"title\": \"song title\", \"artist\": \"artist name\", \"hasTimestamps\": true/false, \"lines\": [{\"text\": \"lyric line\", \"startTime\": seconds or null}]}. Prefer timestamped lyrics from sources like YouTube captions or synced lyrics databases. If timestamped lyrics are available, set hasTimestamps to true and include startTime for each line (in seconds as a Double). If only plain text lyrics are available, set hasTimestamps to false and startTime to null for all lines. Do not include any text before or after the JSON."
    }

    private func parseSearchInput(_ input: String) -> (title: String, artist: String) {
        let separators = [" - ", " – ", " — ", " by ", " / "]
        for sep in separators {
            if let range = input.range(of: sep) {
                let title = String(input[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let artist = String(input[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty && !artist.isEmpty { return (title, artist) }
                if !title.isEmpty { return (title, "") }
            }
        }
        return (input, "")
    }

    private func parseLyricJSON(_ text: String) throws -> LyricLLMResponse {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^```json\\s*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s*```$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let jsonData = cleaned.data(using: .utf8) else { throw LyricPrompterError.invalidJSON }
        let response = try JSONDecoder().decode(LyricLLMResponse.self, from: jsonData)
        guard !response.lines.isEmpty else { throw LyricPrompterError.emptyResponse }
        return response
    }

    private func parseLRC(_ lrc: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        for line in lrc.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("[") else { continue }
            if let closeBracket = trimmed.firstIndex(of: "]") {
                let timeStr = String(trimmed[trimmed.index(after: trimmed.startIndex)..<closeBracket])
                let text = String(trimmed[trimmed.index(after: closeBracket)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty, let time = parseLRCTime(timeStr) {
                    lines.append(LyricLine(text: text, startTime: time))
                }
            }
        }
        return lines
    }

    private func parseLRCTime(_ str: String) -> Double? {
        let parts = str.split(separator: ":")
        guard parts.count == 2, let mins = Double(parts[0]), let secs = Double(parts[1]) else { return nil }
        return mins * 60 + secs
    }

    private func extractPlainFromLRC(_ lrc: String) -> String {
        lrc.components(separatedBy: .newlines)
            .compactMap { line -> String? in
                guard let closeBracket = line.firstIndex(of: "]") else { return nil }
                let text = String(line[line.index(after: closeBracket)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            }
            .joined(separator: "\n")
    }

    private func readStreamedResponse(from bytes: URLSession.AsyncBytes) async throws -> String {
        var streamedText = ""
        for try await line in bytes.lines {
            if line.isEmpty { continue }
            if line == "data: [DONE]" || line == "[DONE]" { break }
            let payloadLine = line.hasPrefix("data: ") ? String(line.dropFirst(6)) : line
            guard let lineData = payloadLine.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let eventType = event["type"] as? String,
                  (eventType == "response.output_text.delta" || eventType == "response.text.delta"),
                  let delta = event["delta"] as? String, !delta.isEmpty else { continue }
            streamedText += delta
        }
        let trimmed = streamedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LyricPrompterError.emptyResponse }
        return trimmed
    }

    private func collectData(from bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes { data.append(byte) }
        return data
    }
}

private extension String {
    var urlEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}
