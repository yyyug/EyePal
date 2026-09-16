import Foundation

enum GemmaModelKind: String, CaseIterable, Identifiable, Codable {
    case e2b
    case e4b

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .e2b: return "Gemma 4 2B ~2.6GB"
        case .e4b: return "Gemma 4 4B ~3.5GB"
        }
    }

    var fileName: String {
        switch self {
        case .e2b: return "gemma-4-E2B-it.litertlm"
        case .e4b: return "gemma-4-E4B-it.litertlm"
        }
    }

    /// Candidate sources, fastest-first. `hf-mirror.com` is a drop-in Hugging Face
    /// mirror that is typically much faster from China / parts of Taiwan and
    /// South-East Asia; the official host is the fallback.
    var downloadURLs: [URL] {
        let path: String
        switch self {
        case .e2b:
            path = "litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm"
        case .e4b:
            path = "litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm"
        }
        return ["https://hf-mirror.com/", "https://huggingface.co/"]
            .compactMap { URL(string: $0 + path) }
    }

    var directoryName: String {
        switch self {
        case .e2b: return "gemma-4-E2B-it-litert-lm"
        case .e4b: return "gemma-4-E4B-it-litert-lm"
        }
    }
}
