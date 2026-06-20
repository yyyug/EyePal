import Foundation

enum LyricPrompterError: LocalizedError {
    case notSignedIn
    case invalidResponse
    case emptyResponse
    case backendError(String)

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
        store: OpenAISubscriptionStore
    ) async throws -> LyricLLMResponse {
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

        let body = makePayload(title: title, artist: artist)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LyricPrompterError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            _ = try await store.activeCredentials(forceRefresh: true)
            return try await searchLyrics(title: title, artist: artist, store: store)
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw LyricPrompterError.backendError("HTTP \(httpResponse.statusCode)")
        }

        let streamedText = try await readStreamedResponse(from: bytes)
        guard let jsonData = streamedText.data(using: .utf8) else {
            throw LyricPrompterError.invalidResponse
        }

        let response_obj = try JSONDecoder().decode(LyricLLMResponse.self, from: jsonData)
        guard !response_obj.lines.isEmpty else {
            throw LyricPrompterError.emptyResponse
        }

        return response_obj
    }

    private func makePayload(title: String, artist: String) -> [String: Any] {
        [
            "model": "gpt-5.4-mini",
            "instructions": makeInstructions(),
            "store": false,
            "stream": true,
            "input": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "input_text",
                            "text": "Find the lyrics for \"\(title)\" by \"\(artist)\". Return ONLY a JSON object with no other text. The JSON must have this exact structure: {\"title\": \"song title\", \"artist\": \"artist name\", \"hasTimestamps\": true/false, \"lines\": [{\"text\": \"lyric line\", \"startTime\": seconds or null}]}. Prefer timestamped lyrics from sources like YouTube captions or synced lyrics databases. If timestamped lyrics are available, set hasTimestamps to true and include startTime for each line (in seconds as a Double). If only plain text lyrics are available, set hasTimestamps to false and startTime to null for all lines. Do not include any text before or after the JSON."
                        ]
                    ]
                ]
            ]
        ]
    }

    private func makeInstructions() -> String {
        "You are a lyrics search assistant. You search the web for song lyrics and return structured JSON data. Always respond with ONLY valid JSON, no markdown, no explanation, no code fences."
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
}
