import Foundation

enum GemmaModelKind: String, CaseIterable, Identifiable, Codable {
    case e2b
    case e4b

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .e2b: return "Gemma 4 2B"
        case .e4b: return "Gemma 4 4B"
        }
    }

    var fileName: String {
        switch self {
        case .e2b: return "gemma-4-E2B-it.litertlm"
        case .e4b: return "gemma-4-E4B-it.litertlm"
        }
    }

    var downloadURL: URL {
        let base = "https://huggingface.co/litert-community/"
        switch self {
        case .e2b:
            return URL(string: base + "gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm")!
        case .e4b:
            return URL(string: base + "gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm")!
        }
    }

    var directoryName: String {
        switch self {
        case .e2b: return "gemma-4-E2B-it-litert-lm"
        case .e4b: return "gemma-4-E4B-it-litert-lm"
        }
    }
}
