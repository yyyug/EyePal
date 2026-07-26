import Foundation
import CryptoKit
import CommonCrypto

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
        case .notSignedIn: return "Sign in with ChatGPT to search for lyrics."
        case .invalidResponse: return "The response could not be read."
        case .emptyResponse: return "No lyrics were found."
        case .backendError(let msg): return msg
        case .missingAPIKey: return "API key is required for this provider."
        case .invalidJSON: return "The AI returned invalid data. Please try again."
        case .noResults: return "No lyrics found for this song."
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
        async let qqResults = searchQQMusic(title: title, artist: artist)

        let (lrclib, qq) = await (lrclibResults, qqResults)
        var allResults = lrclib + qq

        var deduplicated: [LyricSearchResult] = []
        var seenKeys: Set<String> = []
        for result in allResults {
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
        if !artist.isEmpty { urlStr += "&artist_name=\(artist.urlEncoded)" }
        guard let url = URL(string: urlStr) else { return [] }
        var request = URLRequest(url: url)
        request.setValue("LyricPrompter-EyePal/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await session.data(for: request) else { return [] }
        guard let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let trackName = item["trackName"] as? String,
                  let artistName = item["artistName"] as? String else { return nil }
            let syncedLyrics = item["syncedLyrics"] as? String
            let plainLyrics = item["plainLyrics"] as? String
            return LyricSearchResult(
                source: .lrclib, trackName: trackName, artistName: artistName,
                albumName: item["albumName"] as? String,
                hasSyncedLyrics: syncedLyrics != nil && !syncedLyrics!.isEmpty,
                syncedLyrics: syncedLyrics, plainLyrics: plainLyrics
            )
        }
    }

    // MARK: - QQ Music

    private func searchQQMusic(title: String, artist: String) async -> [LyricSearchResult] {
        let keyword = artist.isEmpty ? title : "\(title) \(artist)"
        let payload: [String: Any] = [
            "req_1": [
                "method": "DoSearchForQQMusicDesktop",
                "module": "music.search.SearchCgiService",
                "param": ["num_per_page": "5", "page_num": "1", "query": keyword, "search_type": 0]
            ]
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload),
              let url = URL(string: "https://u.y.qq.com/cgi-bin/musicu.fcg") else { return [] }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://c.y.qq.com/", forHTTPHeaderField: "Referer")
        request.httpBody = body

        guard let (data, _) = try? await session.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let req1 = json["req_1"] as? [String: Any],
              let dataDict = req1["data"] as? [String: Any],
              let bodyDict = dataDict["body"] as? [String: Any],
              let songList = bodyDict["song_list"] as? [[String: Any]] else { return [] }

        var results: [LyricSearchResult] = []
        for song in songList.prefix(5) {
            guard let mid = song["mid"] as? String,
                  let name = song["name"] as? String else { continue }
            let singers = (song["singer"] as? [[String: Any]]) ?? []
            let artistName = singers.compactMap { $0["name"] as? String }.joined(separator: ", ")
            let albumMid = (song["album"] as? [String: Any])?["mid"] as? String

            if let lyrics = await fetchQQMusicLyrics(songMid: mid) {
                results.append(LyricSearchResult(
                    source: .qqmusic, trackName: name, artistName: artistName,
                    albumName: nil, hasSyncedLyrics: lyrics.hasSynced,
                    syncedLyrics: lyrics.synced, plainLyrics: lyrics.plain
                ))
            }
        }
        return results
    }

    private func fetchQQMusicLyrics(songMid: String) async -> (synced: String?, plain: String?, hasSynced: Bool)? {
        let callback = "MusicJsonCallback_lrc"
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        let params = [
            "callback": callback, "pcachetime": "\(ts)", "songmid": songMid,
            "g_tk": "5381", "jsonpCallback": callback, "loginUin": "0",
            "hostUin": "0", "format": "jsonp", "inCharset": "utf8",
            "outCharset": "utf8", "notice": "0", "platform": "yqq", "needNewCode": "0"
        ]
        let queryString = params.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        guard let url = URL(string: "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?\(queryString)") else { return nil }

        var request = URLRequest(url: url)
        request.setValue("https://c.y.qq.com/", forHTTPHeaderField: "Referer")

        guard let (data, _) = try? await session.data(for: request),
              let raw = String(data: data, encoding: .utf8) else { return nil }

        let jsonStr: String
        if raw.hasPrefix("\(callback)(") && raw.hasSuffix(")") {
            jsonStr = String(raw.dropFirst(callback.count + 1).dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            jsonStr = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let jsonData = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { return nil }

        let lyricBase64 = json["lyric"] as? String ?? ""
        guard !lyricBase64.isEmpty else { return nil }

        guard let lyricData = Data(base64Encoded: lyricBase64),
              let rawString = String(data: lyricData, encoding: .utf8) else { return nil }

        // Try QRC decryption if content looks like hex-encoded QRC
        let lrcString: String
        if rawString.allSatisfy({ $0.isHexDigit || $0 == "\n" || $0 == "\r" }) && rawString.count > 100 {
            lrcString = Self.decryptQRC(rawString) ?? rawString
        } else {
            lrcString = rawString
        }

        let hasSynced = lrcString.contains("[0")
        return (synced: hasSynced ? lrcString : nil, plain: hasSynced ? extractPlainFromLRC(lrcString) : lrcString, hasSynced: hasSynced)
    }

    // MARK: - QRC Decrypt

    static func decryptQRC(_ encrypted: String) -> String? {
        guard let hexData = encrypted.data(using: .ascii) else { return nil }
        let bytes = (0..<hexData.count / 2).compactMap { i -> UInt8? in
            let start = hexData.startIndex + i * 2
            let end = hexData.startIndex + (i + 1) * 2
            let byteSlice = hexData[start..<end]
            guard let str = String(data: byteSlice, encoding: .ascii) else { return nil }
            return UInt8(str, radix: 16)
        }
        guard bytes.count % 8 == 0, !bytes.isEmpty else { return nil }

        let keyBytes: [UInt8] = Array("!@#)(*$%123ZXC!@!@#)(NHL)".utf8)

        // TripleDES decryption using CommonCrypto
        var decrypted = [UInt8](repeating: 0, count: bytes.count)
        var dataOutMoved = 0

        bytes.withUnsafeBytes { inputPtr in
            decrypted.withUnsafeMutableBytes { outputPtr in
                _ = CCCrypt(
                    CCOperation(kCCDecrypt),
                    CCAlgorithm(kCCAlgorithm3DES),
                    CCOptions(kCCOptionECBMode),
                    keyBytes, keyBytes.count,
                    nil,
                    inputPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    bytes.count,
                    outputPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    bytes.count,
                    &dataOutMoved
                )
            }
        }

        let decryptedData = Data(decrypted)

        // Try zlib decompression
        if let decompressed = try? (decryptedData as NSData).decompressed(using: .zlib) {
            return String(data: decompressed as Data, encoding: .utf8)
        }

        // If not compressed, return raw decrypted
        return String(data: decryptedData, encoding: .utf8)
    }

    // MARK: - Load selected lyrics

    func loadLyrics(from result: LyricSearchResult) -> LyricSong {
        if let synced = result.syncedLyrics, result.hasSyncedLyrics {
            let lines = parseLRC(synced)
            return LyricSong(title: result.trackName, artist: result.artistName, lines: lines, hasTimestamps: true)
        } else if let plain = result.plainLyrics {
            let lines = plain.components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map { LyricLine(text: $0) }
            return LyricSong(title: result.trackName, artist: result.artistName, lines: lines, hasTimestamps: false)
        }
        return LyricSong(title: result.trackName, artist: result.artistName, lines: [], hasTimestamps: false)
    }

    // MARK: - LLM fallback

    func searchLyricsLLM(
        title: String, artist: String, provider: LyricLLMProvider,
        modelID: String, apiKey: String, baseURL: String, codexStore: OpenAISubscriptionStore?
    ) async throws -> LyricLLMResponse {
        switch provider {
        case .codex: return try await searchLyricsCodex(title: title, artist: artist, modelID: modelID, store: codexStore)
        case .gemini: return try await searchLyricsGemini(title: title, artist: artist, modelID: modelID, apiKey: apiKey, baseURL: baseURL)
        case .openai: return try await searchLyricsOpenAI(title: title, artist: artist, modelID: modelID, apiKey: apiKey, baseURL: baseURL)
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
        if let accountID = credentials.accountID, !accountID.isEmpty { request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-ID") }
        let body: [String: Any] = ["model": modelID, "instructions": makeInstructions(), "store": false, "stream": true, "tools": [["type": "web_search"]], "tool_choice": "auto", "input": [["role": "user", "content": [["type": "input_text", "text": makeLyricPrompt(title: title, artist: artist)]]]]]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw LyricPrompterError.invalidResponse }
        if httpResponse.statusCode == 401 { _ = try await store.activeCredentials(forceRefresh: true); return try await searchLyricsCodex(title: title, artist: artist, modelID: modelID, store: store) }
        guard (200..<300).contains(httpResponse.statusCode) else { let data = try await collectData(from: bytes); throw LyricPrompterError.backendError(String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)") }
        return try parseLyricJSON(try await readStreamedResponse(from: bytes))
    }

    // MARK: - Gemini

    private func searchLyricsGemini(title: String, artist: String, modelID: String, apiKey: String, baseURL: String) async throws -> LyricLLMResponse {
        guard !apiKey.isEmpty else { throw LyricPrompterError.missingAPIKey }
        let base = baseURL.isEmpty ? "https://generativelanguage.googleapis.com/v1beta" : baseURL
        guard let url = URL(string: "\(base)/models/\(modelID):generateContent?key=\(apiKey)") else { throw LyricPrompterError.invalidResponse }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = ["contents": [["parts": [["text": makeInstructions() + "\n\n" + makeLyricPrompt(title: title, artist: artist)]]]], "generationConfig": ["temperature": 0.3, "maxOutputTokens": 4096]]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else { throw LyricPrompterError.backendError(String(data: data, encoding: .utf8) ?? "Error") }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let candidates = json["candidates"] as? [[String: Any]], let content = candidates.first?["content"] as? [String: Any], let parts = content["parts"] as? [[String: Any]], let text = parts.first?["text"] as? String else { throw LyricPrompterError.invalidResponse }
        return try parseLyricJSON(text)
    }

    // MARK: - OpenAI API

    private func searchLyricsOpenAI(title: String, artist: String, modelID: String, apiKey: String, baseURL: String) async throws -> LyricLLMResponse {
        guard !apiKey.isEmpty else { throw LyricPrompterError.missingAPIKey }
        let base = baseURL.isEmpty ? "https://api.openai.com/v1" : baseURL
        guard let url = URL(string: "\(base)/chat/completions") else { throw LyricPrompterError.invalidResponse }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = ["model": modelID, "temperature": 0.3, "max_tokens": 4096, "messages": [["role": "system", "content": makeInstructions()], ["role": "user", "content": makeLyricPrompt(title: title, artist: artist)]]]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else { throw LyricPrompterError.backendError(String(data: data, encoding: .utf8) ?? "Error") }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let choices = json["choices"] as? [[String: Any]], let content = choices.first?["message"] as? [String: Any], let text = content["content"] as? String else { throw LyricPrompterError.invalidResponse }
        return try parseLyricJSON(text)
    }

    // MARK: - Helpers

    private func makeInstructions() -> String { "You are a lyrics search assistant. You search the web for song lyrics and return structured JSON data. Always respond with ONLY valid JSON, no markdown, no explanation, no code fences." }
    private func makeLyricPrompt(title: String, artist: String) -> String { "Find the lyrics for \"\(title)\" by \"\(artist)\". Return ONLY a JSON object with no other text. The JSON must have this exact structure: {\"title\": \"song title\", \"artist\": \"artist name\", \"hasTimestamps\": true/false, \"lines\": [{\"text\": \"lyric line\", \"startTime\": seconds or null}]}. Prefer timestamped lyrics from sources like YouTube captions or synced lyrics databases. If timestamped lyrics are available, set hasTimestamps to true and include startTime for each line (in seconds as a Double). If only plain text lyrics are available, set hasTimestamps to false and startTime to null for all lines. Do not include any text before or after the JSON." }
    private func parseSearchInput(_ input: String) -> (title: String, artist: String) { for sep in [" - ", " – ", " — ", " by ", " / "] { if let range = input.range(of: sep) { let title = String(input[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines); let artist = String(input[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines); if !title.isEmpty && !artist.isEmpty { return (title, artist) }; if !title.isEmpty { return (title, "") } } }; return (input, "") }
    private func parseLyricJSON(_ text: String) throws -> LyricLLMResponse { let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "^```json\\s*", with: "", options: .regularExpression).replacingOccurrences(of: "\\s*```$", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines); guard let jsonData = cleaned.data(using: .utf8) else { throw LyricPrompterError.invalidJSON }; let response = try JSONDecoder().decode(LyricLLMResponse.self, from: jsonData); guard !response.lines.isEmpty else { throw LyricPrompterError.emptyResponse }; return response }
    private func parseLRC(_ lrc: String) -> [LyricLine] { var lines: [LyricLine] = []; for line in lrc.components(separatedBy: .newlines) { let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines); guard trimmed.hasPrefix("[") else { continue }; if let closeBracket = trimmed.firstIndex(of: "]") { let timeStr = String(trimmed[trimmed.index(after: trimmed.startIndex)..<closeBracket]); let text = String(trimmed[trimmed.index(after: closeBracket)...]).trimmingCharacters(in: .whitespacesAndNewlines); if !text.isEmpty, let time = parseLRCTime(timeStr) { lines.append(LyricLine(text: text, startTime: time)) } } }; return lines }
    private func parseLRCTime(_ str: String) -> Double? { let parts = str.split(separator: ":"); guard parts.count == 2, let mins = Double(parts[0]), let secs = Double(parts[1]) else { return nil }; return mins * 60 + secs }
    private func extractPlainFromLRC(_ lrc: String) -> String { lrc.components(separatedBy: .newlines).compactMap { line -> String? in guard let closeBracket = line.firstIndex(of: "]") else { return nil }; let text = String(line[line.index(after: closeBracket)...]).trimmingCharacters(in: .whitespacesAndNewlines); return text.isEmpty ? nil : text }.joined(separator: "\n") }
    private func readStreamedResponse(from bytes: URLSession.AsyncBytes) async throws -> String { var streamedText = ""; for try await line in bytes.lines { if line.isEmpty { continue }; if line == "data: [DONE]" || line == "[DONE]" { break }; let payloadLine = line.hasPrefix("data: ") ? String(line.dropFirst(6)) : line; guard let lineData = payloadLine.data(using: .utf8), let event = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any], let eventType = event["type"] as? String, (eventType == "response.output_text.delta" || eventType == "response.text.delta"), let delta = event["delta"] as? String, !delta.isEmpty else { continue }; streamedText += delta }; let trimmed = streamedText.trimmingCharacters(in: .whitespacesAndNewlines); guard !trimmed.isEmpty else { throw LyricPrompterError.emptyResponse }; return trimmed }
    private func collectData(from bytes: URLSession.AsyncBytes) async throws -> Data { var data = Data(); for try await byte in bytes { data.append(byte) }; return data }
}

private extension String { var urlEncoded: String { addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self } }
