import Foundation

enum LyricPrompterError: LocalizedError {
    case notSignedIn
    case invalidResponse
    case emptyResponse
    case backendError(String)
    case missingAPIKey
    case invalidJSON

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
        }
    }
}

final class LyricPrompterService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func searchLyrics(
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

    // MARK: - Codex (ChatGPT backend)

    private func searchLyricsCodex(
        title: String,
        artist: String,
        modelID: String,
        store: OpenAISubscriptionStore?
    ) async throws -> LyricLLMResponse {
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

        let body = makeCodexPayload(title: title, artist: artist, modelID: modelID)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LyricPrompterError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            _ = try await store.activeCredentials(forceRefresh: true)
            return try await searchLyricsCodex(title: title, artist: artist, modelID: modelID, store: store)
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let data = try await collectData(from: bytes)
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw LyricPrompterError.backendError(msg)
        }

        let streamedText = try await readStreamedResponse(from: bytes)
        return try parseLyricJSON(streamedText)
    }

    private func makeCodexPayload(title: String, artist: String, modelID: String) -> [String: Any] {
        [
            "model": modelID,
            "instructions": makeInstructions(),
            "store": false,
            "stream": true,
            "input": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "input_text",
                            "text": makeLyricPrompt(title: title, artist: artist)
                        ]
                    ]
                ]
            ]
        ]
    }

    // MARK: - Gemini

    private func searchLyricsGemini(
        title: String,
        artist: String,
        modelID: String,
        apiKey: String,
        baseURL: String
    ) async throws -> LyricLLMResponse {
        guard !apiKey.isEmpty else { throw LyricPrompterError.missingAPIKey }

        let base = baseURL.isEmpty ? "https://generativelanguage.googleapis.com/v1beta" : baseURL
        let urlStr = "\(base)/models/\(modelID):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlStr) else { throw LyricPrompterError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": makeInstructions() + "\n\n" + makeLyricPrompt(title: title, artist: artist)]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.3,
                "maxOutputTokens": 4096
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LyricPrompterError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw LyricPrompterError.backendError(msg)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw LyricPrompterError.invalidResponse
        }

        return try parseLyricJSON(text)
    }

    // MARK: - OpenAI API

    private func searchLyricsOpenAI(
        title: String,
        artist: String,
        modelID: String,
        apiKey: String,
        baseURL: String
    ) async throws -> LyricLLMResponse {
        guard !apiKey.isEmpty else { throw LyricPrompterError.missingAPIKey }

        let base = baseURL.isEmpty ? "https://api.openai.com/v1" : baseURL
        let urlStr = "\(base)/chat/completions"
        guard let url = URL(string: urlStr) else { throw LyricPrompterError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": modelID,
            "temperature": 0.3,
            "max_tokens": 4096,
            "messages": [
                ["role": "system", "content": makeInstructions()],
                ["role": "user", "content": makeLyricPrompt(title: title, artist: artist)]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LyricPrompterError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw LyricPrompterError.backendError(msg)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LyricPrompterError.invalidResponse
        }

        return try parseLyricJSON(content)
    }

    // MARK: - Shared

    private func makeInstructions() -> String {
        "You are a lyrics search assistant. You search the web for song lyrics and return structured JSON data. Always respond with ONLY valid JSON, no markdown, no explanation, no code fences."
    }

    private func makeLyricPrompt(title: String, artist: String) -> String {
        "Find the lyrics for \"\(title)\" by \"\(artist)\". Return ONLY a JSON object with no other text. The JSON must have this exact structure: {\"title\": \"song title\", \"artist\": \"artist name\", \"hasTimestamps\": true/false, \"lines\": [{\"text\": \"lyric line\", \"startTime\": seconds or null}]}. Prefer timestamped lyrics from sources like YouTube captions or synced lyrics databases. If timestamped lyrics are available, set hasTimestamps to true and include startTime for each line (in seconds as a Double). If only plain text lyrics are available, set hasTimestamps to false and startTime to null for all lines. Do not include any text before or after the JSON."
    }

    private func parseLyricJSON(_ text: String) throws -> LyricLLMResponse {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^```json\\s*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s*```$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = cleaned.data(using: .utf8) else {
            throw LyricPrompterError.invalidJSON
        }

        do {
            let response = try JSONDecoder().decode(LyricLLMResponse.self, from: jsonData)
            guard !response.lines.isEmpty else {
                throw LyricPrompterError.emptyResponse
            }
            return response
        } catch {
            throw LyricPrompterError.invalidJSON
        }
    }

    private func readStreamedResponse(from bytes: URLSession.AsyncBytes) async throws -> String {
        var streamedText = ""

        for try await line in bytes.lines {
            if line.isEmpty { continue }
            if line == "data: [DONE]" || line == "[DONE]" { break }

            let payloadLine: String
            if line.hasPrefix("data: ") {
                payloadLine = String(line.dropFirst(6))
            } else {
                payloadLine = line
            }

            guard let lineData = payloadLine.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let eventType = event["type"] as? String,
                  (eventType == "response.output_text.delta" || eventType == "response.text.delta"),
                  let delta = event["delta"] as? String,
                  !delta.isEmpty else { continue }

            streamedText += delta
        }

        let trimmed = streamedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LyricPrompterError.emptyResponse
        }
        return trimmed
    }

    private func collectData(from bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
        }
        return data
    }
}
