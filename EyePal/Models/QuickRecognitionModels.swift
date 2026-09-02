import Foundation

enum RecognitionButtonSlot: Int, CaseIterable, Identifiable {
    case first = 1
    case second = 2
    case third = 3
    case fourth = 4

    var id: Int { rawValue }

    var displayName: String {
        "Button \(rawValue)"
    }

    var defaultPresetKind: RecognitionPresetKind {
        switch self {
        case .first:
            return .custom
        case .second:
            return .product
        case .third:
            return .dish
        case .fourth:
            return .shortText
        }
    }
}

enum RecognitionPresetKind: String, CaseIterable, Identifiable {
    case product
    case dish
    case shortText
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .product:
            return "Product"
        case .dish:
            return "Dish"
        case .shortText:
            return "Short Text"
        case .custom:
            return "Custom"
        }
    }
}

enum QuickCaptionLength: String, CaseIterable, Identifiable {
    case short
    case normal
    case long

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .short:
            return "Concise"
        case .normal:
            return "Standard"
        case .long:
            return "Detailed"
        }
    }
}

enum QuickModelProvider: String, CaseIterable, Identifiable {
    case gemma
    case moondream

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gemma:
            return NSLocalizedString("settings.modelProvider.gemma", comment: "")
        case .moondream:
            return NSLocalizedString("settings.modelProvider.moondream", comment: "")
        }
    }
}

enum QuickContinuousCaptureInterval: Double, CaseIterable, Identifiable {
    case oneSecond = 1
    case twoSeconds = 2
    case threeSeconds = 3
    case fiveSeconds = 5
    case tenSeconds = 10
    case thirtySeconds = 30
    case oneMinute = 60
    case twoMinutes = 120

    static let defaultInterval: Self = .threeSeconds

    var id: Double { rawValue }

    var timeInterval: TimeInterval { rawValue }

    var displayName: String {
        switch self {
        case .oneSecond:
            return "1 second"
        case .twoSeconds:
            return "2 seconds"
        case .threeSeconds:
            return "3 seconds"
        case .fiveSeconds:
            return "5 seconds"
        case .tenSeconds:
            return "10 seconds"
        case .thirtySeconds:
            return "30 seconds"
        case .oneMinute:
            return "1 minute"
        case .twoMinutes:
            return "2 minutes"
        }
    }
}

enum QuickRecognitionTriggerMode: String, CaseIterable, Identifiable {
    case time
    case onTheMove

    static let defaultMode: Self = .time

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .time:
            return "Time interval"
        case .onTheMove:
            return "On the move"
        }
    }
}

enum RecognitionActionControlStyle: String, CaseIterable, Identifiable {
    case onScreenButtons
    case singleAdjustableControl

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .onScreenButtons:
            return "On-screen button layout"
        case .singleAdjustableControl:
            return "Single control (swipe up/down to choose)"
        }
    }
}

struct QuickQueryPreset: Identifiable, Equatable {
    let title: String
    let prompt: String
    let systemImageName: String

    var id: String { title }

    var localizedTitle: String {
        switch title {
        case "Product": return NSLocalizedString("preset.product", comment: "")
        case "Dish": return NSLocalizedString("preset.dish", comment: "")
        case "Short Text": return NSLocalizedString("preset.shortText", comment: "")
        case "Custom": return NSLocalizedString("preset.custom", comment: "")
        default: return title
        }
    }

    static let builtIn: [QuickQueryPreset] = [
        QuickQueryPreset(
            title: "Product",
            prompt: "Describe the main product in this image with 1 or 2 sentences, including its brand, name and primary function",
            systemImageName: "shippingbox.fill"
        ),
        QuickQueryPreset(
            title: "Dish",
            prompt: "Describe the layout of the food on the plate or tray. Use clock positions or spatial terms",
            systemImageName: "fork.knife.circle.fill"
        ),
        QuickQueryPreset(
            title: "Short Text",
            prompt: "Describe the alphanumeric text visible in the image",
            systemImageName: "text.magnifyingglass"
        )
    ]

    static func builtInPreset(for kind: RecognitionPresetKind) -> QuickQueryPreset {
        switch kind {
        case .product:
            return QuickQueryPreset(
                title: "Product",
                prompt: "Describe the main product in this image with 1 or 2 sentences, including its brand, name and primary function",
                systemImageName: "shippingbox.fill"
            )
        case .dish:
            return QuickQueryPreset(
                title: "Dish",
                prompt: "Describe the layout of the food on the plate or tray. Use clock positions or spatial terms",
                systemImageName: "fork.knife.circle.fill"
            )
        case .shortText:
            return QuickQueryPreset(
                title: "Short Text",
                prompt: "Describe the alphanumeric text visible in the image",
                systemImageName: "text.magnifyingglass"
            )
        case .custom:
            return QuickQueryPreset(
                title: QuickCustomQueryPreset.defaultTitle,
                prompt: QuickCustomQueryPreset.defaultPrompt,
                systemImageName: "slider.horizontal.3"
            )
        }
    }
}

enum QuickCustomQueryPreset {
    static let defaultTitle = "Custom"
    static let defaultPrompt = "Tell me how many men and women there and describe them; if not found, say No people found"
}

enum DetailsCustomQueryPreset {
    static let defaultTitle = "Custom"
    static let defaultPrompt = "For a blind user, first read visible text exactly. Then describe people, objects, layout, and orientation cues. Be concise and specific. Do not use markdown or double asterisks."
}

enum DetailsQueryPreset {
    static func builtInPreset(for kind: RecognitionPresetKind) -> QuickQueryPreset {
        switch kind {
        case .product:
            return QuickQueryPreset(
                title: "Product",
                prompt: "Describe the main product in this image with 1 or 2 sentences, including its brand, name, packaging details, and primary function.",
                systemImageName: "shippingbox.fill"
            )
        case .dish:
            return QuickQueryPreset(
                title: "Dish",
                prompt: "Describe the dish layout in detail for a blind user, including portions, relative positions, and likely ingredients.",
                systemImageName: "fork.knife.circle.fill"
            )
        case .shortText:
            return QuickQueryPreset(
                title: "Short Text",
                prompt: "Read the visible short text and numbers exactly, and mention where they appear in the scene.",
                systemImageName: "text.magnifyingglass"
            )
        case .custom:
            return QuickQueryPreset(
                title: DetailsCustomQueryPreset.defaultTitle,
                prompt: DetailsCustomQueryPreset.defaultPrompt,
                systemImageName: "slider.horizontal.3"
            )
        }
    }
}

enum QuickTranslationSupport {
    static func shouldAttemptTranslation(
        for caption: String,
        isTranslationEnabled: Bool,
        targetLanguageIdentifier: String?
    ) -> Bool {
        let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCaption.isEmpty else { return false }
        guard isTranslationEnabled else { return false }
        guard let targetLanguageIdentifier, !targetLanguageIdentifier.isEmpty else { return false }

        let targetCode = Locale(identifier: targetLanguageIdentifier).language.languageCode?.identifier.lowercased()
        let sourceCode = Locale(identifier: "en-US").language.languageCode?.identifier.lowercased()
        return targetCode != nil && targetCode != sourceCode
    }
}
