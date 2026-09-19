import Foundation

enum RecognitionButtonSlot: Int, CaseIterable, Identifiable {
    case first = 1
    case second = 2
    case third = 3
    case fourth = 4

    var id: Int { rawValue }

    var displayName: String {
        String(format: NSLocalizedString("quick.slot", comment: ""), rawValue)
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
            return NSLocalizedString("preset.product", comment: "")
        case .dish:
            return NSLocalizedString("preset.dish", comment: "")
        case .shortText:
            return NSLocalizedString("preset.shortText", comment: "")
        case .custom:
            return NSLocalizedString("preset.custom", comment: "")
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
            return NSLocalizedString("quick.caption.concise", comment: "")
        case .normal:
            return NSLocalizedString("quick.caption.standard", comment: "")
        case .long:
            return NSLocalizedString("quick.caption.detailed", comment: "")
        }
    }

    /// Description prompt used by on-device models (Gemma / Apple), following the
    /// app's UI language.
    var onDevicePrompt: String {
        if QuickPromptLanguage.isChinese {
            switch self {
            case .short:
                return "請用一至兩句中文描述這張圖片。"
            case .normal:
                return "請用三至五句中文描述這張圖片。"
            case .long:
                return "請用六句或以上中文詳細描述這張圖片，內容越詳細越好。"
            }
        } else {
            switch self {
            case .short:
                return "Describe this image in 1 to 2 sentences."
            case .normal:
                return "Describe this image in 3 to 5 sentences."
            case .long:
                return "Describe this image in 6 or more sentences with as much detail as possible."
            }
        }
    }
}

enum QuickModelProvider: String, CaseIterable, Identifiable {
    case gemma
    case moondream
    case appleFoundation

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gemma:
            return NSLocalizedString("settings.modelProvider.gemma", comment: "")
        case .moondream:
            return NSLocalizedString("settings.modelProvider.moondream", comment: "")
        case .appleFoundation:
            return NSLocalizedString("settings.modelProvider.apple", comment: "")
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
        let formatKey: String
        let value: Int
        switch self {
        case .oneSecond:
            formatKey = "quick.interval.second"
            value = 1
        case .twoSeconds:
            formatKey = "quick.interval.seconds"
            value = 2
        case .threeSeconds:
            formatKey = "quick.interval.seconds"
            value = 3
        case .fiveSeconds:
            formatKey = "quick.interval.seconds"
            value = 5
        case .tenSeconds:
            formatKey = "quick.interval.seconds"
            value = 10
        case .thirtySeconds:
            formatKey = "quick.interval.seconds"
            value = 30
        case .oneMinute:
            formatKey = "quick.interval.minute"
            value = 1
        case .twoMinutes:
            formatKey = "quick.interval.minutes"
            value = 2
        }
        return String(format: NSLocalizedString(formatKey, comment: ""), value)
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
            return NSLocalizedString("quick.trigger.time", comment: "")
        case .onTheMove:
            return NSLocalizedString("quick.trigger.onTheMove", comment: "")
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
            return NSLocalizedString("quick.controlStyle.buttons", comment: "")
        case .singleAdjustableControl:
            return NSLocalizedString("quick.controlStyle.single", comment: "")
        }
    }
}

enum QuickPromptLanguage {
    /// True when the app's UI is Chinese (any variant). This follows the actual
    /// UI localization (NSLocalizedString language) rather than the raw OS
    /// language preference, so prompts match what the user reads in the app.
    static var isChinese: Bool {
        Bundle.main.preferredLocalizations.first?.lowercased().hasPrefix("zh") ?? false
    }
}

struct QuickQueryPreset: Identifiable, Equatable {
    let title: String
    let prompt: String
    let systemImageName: String

    var id: String { title }

    /// Chinese equivalent of the built-in prompt, used when Gemma runs on a
    /// Chinese-language device. Custom (user-typed) prompts pass through unchanged.
    var chinesePrompt: String {
        switch prompt {
        case "Describe the main product in this image with 1 or 2 sentences, including its brand, name and primary function":
            return "請用一至兩句描述圖片中的主要產品，包括品牌、名稱和主要功能。"
        case "Describe the layout of the food on the plate or tray. Use clock positions or spatial terms":
            return "請描述食物在盤子或托盤上的擺放位置，使用時鐘方向或空間詞語。"
        case "Describe the alphanumeric text visible in the image":
            return "請描述圖片中可見的英數字文字。"
        default:
            return prompt
        }
    }

    /// The prompt to send for the given engine. On-device models (Gemma / Apple)
    /// use Chinese on a Chinese-language UI; Moondream always uses English.
    func resolvedPrompt(onDevice: Bool) -> String {
        onDevice && QuickPromptLanguage.isChinese ? chinesePrompt : prompt
    }

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
