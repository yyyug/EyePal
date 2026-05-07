import Foundation
import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {
    @AppStorage("speechCooldown") var speechCooldown = 2.5
    @AppStorage("faceMatchThreshold") var faceMatchThreshold = 0.87
    @AppStorage("suggestUnknownFaces") var suggestUnknownFaces = true
    @AppStorage("featureOrderData") private var featureOrderData = Data()
    @AppStorage("quickMoondreamAPIKey") var quickMoondreamAPIKey = ""
    @AppStorage("quickCaptionLength") var quickCaptionLength = QuickCaptionLength.short.rawValue
    @AppStorage("quickContinuousCaptureInterval") var quickContinuousCaptureInterval = QuickContinuousCaptureInterval.defaultInterval.rawValue
    @AppStorage("quickCaptionTranslationEnabled") var quickCaptionTranslationEnabled = false
    @AppStorage("quickCaptionTranslationTargetLanguage") var quickCaptionTranslationTargetLanguage = ""
    @AppStorage("mapsMaxDistanceMeters") var mapsMaxDistanceMeters = 100.0
    @AppStorage("mapsReverbBlend") var mapsReverbBlend = 0.15
    @AppStorage("mapsHeadTrackingEnabled") var mapsHeadTrackingEnabled = true
    @AppStorage("mapsAutoCalloutsEnabled") var mapsAutoCalloutsEnabled = true
    @AppStorage("mapsAutoCalloutIntervalSeconds") var mapsAutoCalloutIntervalSeconds = 20.0
    @AppStorage("mapsBackgroundAudioEnabled") var mapsBackgroundAudioEnabled = true
    @AppStorage("mapsBeaconAlertsEnabled") var mapsBeaconAlertsEnabled = true
    @AppStorage("mapsMetricUnits") var mapsMetricUnits = Locale.current.usesMetricSystem
    @AppStorage("mapsMixAudioWithOthers") var mapsMixAudioWithOthers = true
    @AppStorage("mapsPreviewIncludeUnnamedRoads") var mapsPreviewIncludeUnnamedRoads = false

    @AppStorage("mapsBeaconStyle") var mapsBeaconStyle = "current"
    @AppStorage("mapsBeaconMelodiesEnabled") var mapsBeaconMelodiesEnabled = false
    @AppStorage("mapsBeaconVolume") var mapsBeaconVolume = 0.75
    @AppStorage("mapsVoiceVolume") var mapsVoiceVolume = 0.75
    @AppStorage("mapsOtherVolume") var mapsOtherVolume = 0.75
    @AppStorage("mapsBeaconAudioEnabled") var mapsBeaconAudioEnabled = true

    @AppStorage("mapsPlaceSenseEnabled") var mapsPlaceSenseEnabled = true
    @AppStorage("mapsLandmarkSenseEnabled") var mapsLandmarkSenseEnabled = true
    @AppStorage("mapsInformationSenseEnabled") var mapsInformationSenseEnabled = true
    @AppStorage("mapsMobilitySenseEnabled") var mapsMobilitySenseEnabled = true
    @AppStorage("mapsSafetySenseEnabled") var mapsSafetySenseEnabled = true
    @AppStorage("mapsIntersectionSenseEnabled") var mapsIntersectionSenseEnabled = true
    @AppStorage("mapsDestinationSenseEnabled") var mapsDestinationSenseEnabled = true

    @AppStorage("quickButton1PresetKind") var quickButton1PresetKind = RecognitionButtonSlot.first.defaultPresetKind.rawValue
    @AppStorage("quickButton1CustomTitle") var quickButton1CustomTitle = QuickCustomQueryPreset.defaultTitle
    @AppStorage("quickButton1CustomPrompt") var quickButton1CustomPrompt = QuickCustomQueryPreset.defaultPrompt

    @AppStorage("quickButton2PresetKind") var quickButton2PresetKind = RecognitionButtonSlot.second.defaultPresetKind.rawValue
    @AppStorage("quickButton2CustomTitle") var quickButton2CustomTitle = QuickCustomQueryPreset.defaultTitle
    @AppStorage("quickButton2CustomPrompt") var quickButton2CustomPrompt = QuickCustomQueryPreset.defaultPrompt

    @AppStorage("quickButton3PresetKind") var quickButton3PresetKind = RecognitionButtonSlot.third.defaultPresetKind.rawValue
    @AppStorage("quickButton3CustomTitle") var quickButton3CustomTitle = QuickCustomQueryPreset.defaultTitle
    @AppStorage("quickButton3CustomPrompt") var quickButton3CustomPrompt = QuickCustomQueryPreset.defaultPrompt

    @AppStorage("quickButton4PresetKind") var quickButton4PresetKind = RecognitionButtonSlot.fourth.defaultPresetKind.rawValue
    @AppStorage("quickButton4CustomTitle") var quickButton4CustomTitle = QuickCustomQueryPreset.defaultTitle
    @AppStorage("quickButton4CustomPrompt") var quickButton4CustomPrompt = QuickCustomQueryPreset.defaultPrompt

    @AppStorage("detailsButton1PresetKind") var detailsButton1PresetKind = RecognitionButtonSlot.first.defaultPresetKind.rawValue
    @AppStorage("detailsButton1CustomTitle") var detailsButton1CustomTitle = DetailsCustomQueryPreset.defaultTitle
    @AppStorage("detailsButton1CustomPrompt") var detailsButton1CustomPrompt = DetailsCustomQueryPreset.defaultPrompt

    @AppStorage("detailsButton2PresetKind") var detailsButton2PresetKind = RecognitionButtonSlot.second.defaultPresetKind.rawValue
    @AppStorage("detailsButton2CustomTitle") var detailsButton2CustomTitle = DetailsCustomQueryPreset.defaultTitle
    @AppStorage("detailsButton2CustomPrompt") var detailsButton2CustomPrompt = DetailsCustomQueryPreset.defaultPrompt

    @AppStorage("detailsButton3PresetKind") var detailsButton3PresetKind = RecognitionButtonSlot.third.defaultPresetKind.rawValue
    @AppStorage("detailsButton3CustomTitle") var detailsButton3CustomTitle = DetailsCustomQueryPreset.defaultTitle
    @AppStorage("detailsButton3CustomPrompt") var detailsButton3CustomPrompt = DetailsCustomQueryPreset.defaultPrompt

    @AppStorage("detailsButton4PresetKind") var detailsButton4PresetKind = RecognitionButtonSlot.fourth.defaultPresetKind.rawValue
    @AppStorage("detailsButton4CustomTitle") var detailsButton4CustomTitle = DetailsCustomQueryPreset.defaultTitle
    @AppStorage("detailsButton4CustomPrompt") var detailsButton4CustomPrompt = DetailsCustomQueryPreset.defaultPrompt

    var orderedFeatures: [AppFeature] {
        get {
            guard
                let decoded = try? JSONDecoder().decode([String].self, from: featureOrderData),
                !decoded.isEmpty
            else {
                return AppFeature.defaultOrder
            }

            return AppFeature.normalizedOrder(from: decoded)
        }
        set {
            let normalized = AppFeature.normalizedOrder(from: newValue.map(\.rawValue))
            if let encoded = try? JSONEncoder().encode(normalized.map(\.rawValue)) {
                featureOrderData = encoded
            }
            objectWillChange.send()
        }
    }

    var tabFeatures: [AppFeature] {
        Array(orderedFeatures.prefix(AppFeature.maxTabFeatureCount))
    }

    var moreFeatures: [AppFeature] {
        Array(orderedFeatures.dropFirst(AppFeature.maxTabFeatureCount))
    }

    func moveFeature(from source: IndexSet, to destination: Int) {
        var features = orderedFeatures
        features.move(fromOffsets: source, toOffset: destination)
        orderedFeatures = features
    }

    func moveFeature(_ feature: AppFeature, by offset: Int) {
        let features = orderedFeatures
        guard let currentIndex = features.firstIndex(of: feature) else { return }

        let targetIndex = currentIndex + offset
        guard features.indices.contains(targetIndex) else { return }

        var updated = features
        updated.swapAt(currentIndex, targetIndex)
        orderedFeatures = updated
    }

    func quickPreset(for slot: RecognitionButtonSlot) -> QuickQueryPreset {
        let kind = quickPresetKind(for: slot)
        guard kind == .custom else {
            return QuickQueryPreset.builtInPreset(for: kind)
        }

        let customTitle = quickCustomTitle(for: slot).trimmingCharacters(in: .whitespacesAndNewlines)
        let customPrompt = quickCustomPrompt(for: slot).trimmingCharacters(in: .whitespacesAndNewlines)
        return QuickQueryPreset(
            title: customTitle.isEmpty ? QuickCustomQueryPreset.defaultTitle : customTitle,
            prompt: customPrompt.isEmpty ? QuickCustomQueryPreset.defaultPrompt : customPrompt,
            systemImageName: "slider.horizontal.3"
        )
    }

    func detailsPreset(for slot: RecognitionButtonSlot) -> QuickQueryPreset {
        let kind = detailsPresetKind(for: slot)
        guard kind == .custom else {
            return DetailsQueryPreset.builtInPreset(for: kind)
        }

        let customTitle = detailsCustomTitle(for: slot).trimmingCharacters(in: .whitespacesAndNewlines)
        let customPrompt = detailsCustomPrompt(for: slot).trimmingCharacters(in: .whitespacesAndNewlines)
        return QuickQueryPreset(
            title: customTitle.isEmpty ? DetailsCustomQueryPreset.defaultTitle : customTitle,
            prompt: customPrompt.isEmpty ? DetailsCustomQueryPreset.defaultPrompt : customPrompt,
            systemImageName: "slider.horizontal.3"
        )
    }

    func quickPresetKind(for slot: RecognitionButtonSlot) -> RecognitionPresetKind {
        RecognitionPresetKind(rawValue: quickPresetKindRawValue(for: slot)) ?? slot.defaultPresetKind
    }

    func detailsPresetKind(for slot: RecognitionButtonSlot) -> RecognitionPresetKind {
        RecognitionPresetKind(rawValue: detailsPresetKindRawValue(for: slot)) ?? slot.defaultPresetKind
    }

    private func quickPresetKindRawValue(for slot: RecognitionButtonSlot) -> String {
        switch slot {
        case .first:
            return quickButton1PresetKind
        case .second:
            return quickButton2PresetKind
        case .third:
            return quickButton3PresetKind
        case .fourth:
            return quickButton4PresetKind
        }
    }

    private func detailsPresetKindRawValue(for slot: RecognitionButtonSlot) -> String {
        switch slot {
        case .first:
            return detailsButton1PresetKind
        case .second:
            return detailsButton2PresetKind
        case .third:
            return detailsButton3PresetKind
        case .fourth:
            return detailsButton4PresetKind
        }
    }

    private func quickCustomTitle(for slot: RecognitionButtonSlot) -> String {
        switch slot {
        case .first:
            return quickButton1CustomTitle
        case .second:
            return quickButton2CustomTitle
        case .third:
            return quickButton3CustomTitle
        case .fourth:
            return quickButton4CustomTitle
        }
    }

    private func quickCustomPrompt(for slot: RecognitionButtonSlot) -> String {
        switch slot {
        case .first:
            return quickButton1CustomPrompt
        case .second:
            return quickButton2CustomPrompt
        case .third:
            return quickButton3CustomPrompt
        case .fourth:
            return quickButton4CustomPrompt
        }
    }

    private func detailsCustomTitle(for slot: RecognitionButtonSlot) -> String {
        switch slot {
        case .first:
            return detailsButton1CustomTitle
        case .second:
            return detailsButton2CustomTitle
        case .third:
            return detailsButton3CustomTitle
        case .fourth:
            return detailsButton4CustomTitle
        }
    }

    private func detailsCustomPrompt(for slot: RecognitionButtonSlot) -> String {
        switch slot {
        case .first:
            return detailsButton1CustomPrompt
        case .second:
            return detailsButton2CustomPrompt
        case .third:
            return detailsButton3CustomPrompt
        case .fourth:
            return detailsButton4CustomPrompt
        }
    }
}
