import SwiftUI
import AVFoundation
import CoreLocation
#if canImport(Translation)
import Translation
#endif

struct SettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var openAIStore: OpenAISubscriptionStore

    var body: some View {
        Form {
            Section {
                NavigationLink(NSLocalizedString("settings.featureOrder", comment: "")) {
                    FeatureOrderSettingsView()
                        .environmentObject(settingsStore)
                }
            }

            Section(NSLocalizedString("settings.features", comment: "")) {
                NavigationLink(NSLocalizedString("feature.detailsRecognition", comment: "")) {
                    DetailsDescriptionSettingsView()
                        .environmentObject(settingsStore)
                        .environmentObject(openAIStore)
                }

                NavigationLink(NSLocalizedString("feature.quickRecognition", comment: "")) {
                    QuickRecognitionSettingsView()
                        .environmentObject(settingsStore)
                }

                NavigationLink(NSLocalizedString("feature.readText", comment: "")) {
                    ReadTextRecognitionSettingsView()
                        .environmentObject(settingsStore)
                }

                NavigationLink(NSLocalizedString("feature.faceRecognition", comment: "")) {
                    FaceRecognitionSettingsView()
                        .environmentObject(settingsStore)
                }

                NavigationLink(NSLocalizedString("feature.lyricPrompter", comment: "")) {
                    LyricPrompterSettingsView()
                        .environmentObject(settingsStore)
                        .environmentObject(openAIStore)
                }
            }
        }
        .navigationTitle(NSLocalizedString("tab.settings", comment: ""))
    }
}

private struct FeatureOrderSettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        List {
            Section {
                ForEach(settingsStore.orderedFeatures) { feature in
                    HStack {
                        Image(systemName: feature.systemImageName)
                            .foregroundStyle(.secondary)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.displayName)
                            Text(feature.featureDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(settingsStore.tabFeatures.contains(feature) ? NSLocalizedString("featureOrder.tab", comment: "") : NSLocalizedString("featureOrder.moreTab", comment: ""))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.tertiary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityHint(NSLocalizedString("featureOrder.dragHint", comment: ""))
                    .accessibilityAction(named: Text(NSLocalizedString("featureOrder.moveUp", comment: ""))) {
                        settingsStore.moveFeature(feature, by: -1)
                    }
                    .accessibilityAction(named: Text(NSLocalizedString("featureOrder.moveDown", comment: ""))) {
                        settingsStore.moveFeature(feature, by: 1)
                    }
                }
                .onMove(perform: settingsStore.moveFeature)
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle(NSLocalizedString("settings.featureOrder", comment: ""))
    }
}

private struct MapsSettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    private var poiCalloutsBinding: Binding<Bool> {
        Binding(
            get: {
                settingsStore.mapsPlaceSenseEnabled &&
                settingsStore.mapsLandmarkSenseEnabled &&
                settingsStore.mapsInformationSenseEnabled
            },
            set: { newValue in
                settingsStore.mapsPlaceSenseEnabled = newValue
                settingsStore.mapsLandmarkSenseEnabled = newValue
                settingsStore.mapsInformationSenseEnabled = newValue
            }
        )
    }

    private var mobilityCalloutsBinding: Binding<Bool> {
        Binding(
            get: {
                settingsStore.mapsMobilitySenseEnabled &&
                settingsStore.mapsSafetySenseEnabled &&
                settingsStore.mapsIntersectionSenseEnabled
            },
            set: { newValue in
                settingsStore.mapsMobilitySenseEnabled = newValue
                settingsStore.mapsSafetySenseEnabled = newValue
                settingsStore.mapsIntersectionSenseEnabled = newValue
            }
        )
    }
    
    var body: some View {
        Form {
            Section(NSLocalizedString("settings.general", comment: "")) {
                Toggle(NSLocalizedString("settings.useMetricUnits", comment: ""), isOn: $settingsStore.mapsMetricUnits)
                Toggle(NSLocalizedString("settings.mixAudioWithOtherApps", comment: ""), isOn: $settingsStore.mapsMixAudioWithOthers)
            }

            Section(NSLocalizedString("settings.audioBeacon", comment: "")) {
                Picker(NSLocalizedString("settings.beaconStyle", comment: ""), selection: $settingsStore.mapsBeaconStyle) {
                    ForEach(MapsBeaconStyle.allCases, id: \.rawValue) { style in
                        Text(style.displayName).tag(style.rawValue)
                    }
                }

                Toggle(NSLocalizedString("settings.beaconMelodies", comment: ""), isOn: $settingsStore.mapsBeaconMelodiesEnabled)
                Toggle(NSLocalizedString("settings.beaconAudioEnabled", comment: ""), isOn: $settingsStore.mapsBeaconAudioEnabled)
                Toggle(NSLocalizedString("settings.beaconAlerts", comment: ""), isOn: $settingsStore.mapsBeaconAlertsEnabled)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(NSLocalizedString("settings.beaconVolume", comment: ""))
                        Spacer()
                        Text(String(format: "%.2f", settingsStore.mapsBeaconVolume))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settingsStore.mapsBeaconVolume, in: 0...1, step: 0.05)
                }
            }

            Section(NSLocalizedString("settings.voiceAndOtherAudio", comment: "")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(NSLocalizedString("settings.voiceVolume", comment: ""))
                        Spacer()
                        Text(String(format: "%.2f", settingsStore.mapsVoiceVolume))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settingsStore.mapsVoiceVolume, in: 0...1, step: 0.05)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(NSLocalizedString("settings.otherVolume", comment: ""))
                        Spacer()
                        Text(String(format: "%.2f", settingsStore.mapsOtherVolume))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settingsStore.mapsOtherVolume, in: 0...1, step: 0.05)
                }
            }

            Section(NSLocalizedString("settings.callouts", comment: "")) {
                Toggle(NSLocalizedString("settings.automaticCallouts", comment: ""), isOn: $settingsStore.mapsAutoCalloutsEnabled)
                Toggle(NSLocalizedString("settings.poiCallouts", comment: ""), isOn: poiCalloutsBinding)
                    .disabled(!settingsStore.mapsAutoCalloutsEnabled)
                Toggle(NSLocalizedString("settings.mobilityCallouts", comment: ""), isOn: mobilityCalloutsBinding)
                    .disabled(!settingsStore.mapsAutoCalloutsEnabled)
                Toggle(NSLocalizedString("settings.beaconCallouts", comment: ""), isOn: $settingsStore.mapsDestinationSenseEnabled)
                    .disabled(!settingsStore.mapsAutoCalloutsEnabled)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(NSLocalizedString("settings.autoCalloutInterval", comment: ""))
                        Spacer()
                        Text("\(Int(settingsStore.mapsAutoCalloutIntervalSeconds))s")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settingsStore.mapsAutoCalloutIntervalSeconds, in: 8...60, step: 1)
                }
            }

            Section(NSLocalizedString("settings.streetPreview", comment: "")) {
                Toggle(NSLocalizedString("settings.includeUnnamedRoads", comment: ""), isOn: $settingsStore.mapsPreviewIncludeUnnamedRoads)
            }

            Section(NSLocalizedString("settings.spatialAudio", comment: "")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(NSLocalizedString("settings.maximumDistance", comment: ""))
                        Spacer()
                        Text("\(Int(settingsStore.mapsMaxDistanceMeters)) m")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settingsStore.mapsMaxDistanceMeters, in: 10...200, step: 10)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(NSLocalizedString("settings.reverbBlend", comment: ""))
                        Spacer()
                        Text(String(format: "%.2f", settingsStore.mapsReverbBlend))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settingsStore.mapsReverbBlend, in: 0...0.5, step: 0.05)
                }
                
                Toggle(NSLocalizedString("settings.headTracking", comment: ""), isOn: $settingsStore.mapsHeadTrackingEnabled)
                    .help(NSLocalizedString("settings.headTrackingHelp", comment: ""))

                Toggle(NSLocalizedString("settings.backgroundAudio", comment: ""), isOn: $settingsStore.mapsBackgroundAudioEnabled)

                Text(NSLocalizedString("settings.spatialAudioDesc", comment: ""))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text(NSLocalizedString("settings.mapsCalloutHelp", comment: ""))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section(NSLocalizedString("settings.devicesSection", comment: "")) {
                NavigationLink(NSLocalizedString("settings.headphonesAndGPS", comment: "")) {
                    MapsDevicesSettingsView()
                }
            }
        }
        .navigationTitle(NSLocalizedString("feature.maps", comment: ""))
        .onChange(of: settingsStore.mapsMaxDistanceMeters) { _ in
            applyMapsAudioSettings()
        }
        .onChange(of: settingsStore.mapsReverbBlend) { _ in
            applyMapsAudioSettings()
        }
        .onChange(of: settingsStore.mapsBeaconStyle) { _ in
            applyMapsRuntimeSettings()
        }
        .onChange(of: settingsStore.mapsBeaconMelodiesEnabled) { _ in
            applyMapsRuntimeSettings()
        }
        .onChange(of: settingsStore.mapsBeaconVolume) { _ in
            applyMapsRuntimeSettings()
        }
        .onChange(of: settingsStore.mapsOtherVolume) { _ in
            applyMapsRuntimeSettings()
        }
        .onChange(of: settingsStore.mapsMixAudioWithOthers) { _ in
            applyMapsRuntimeSettings()
        }
        .onAppear {
            applyMapsAudioSettings()
            applyMapsRuntimeSettings()
        }
    }

    private func applyMapsAudioSettings() {
        HRTFAudioEngine.shared.applyMapsAudioSettings(
            maxDistanceMeters: settingsStore.mapsMaxDistanceMeters,
            reverbBlend: settingsStore.mapsReverbBlend
        )
    }

    private func applyMapsRuntimeSettings() {
        HRTFAudioEngine.shared.applyMapsRuntimeSettings(
            beaconStyle: settingsStore.mapsBeaconStyle,
            beaconMelodiesEnabled: settingsStore.mapsBeaconMelodiesEnabled,
            beaconVolume: settingsStore.mapsBeaconVolume,
            otherVolume: settingsStore.mapsOtherVolume,
            mixAudioWithOthers: settingsStore.mapsMixAudioWithOthers
        )
    }
}

private struct MapsDevicesSettingsView: View {
    @StateObject private var monitor = MapsDevicesMonitor()

    var body: some View {
        Form {
            Section(NSLocalizedString("settings.audio", comment: "")) {
                LabeledContent(NSLocalizedString("settings.output", comment: "")) {
                    Text(monitor.audioOutputName)
                }
                LabeledContent(NSLocalizedString("settings.headphoneMotion", comment: "")) {
                    Text(monitor.headphoneMotionAvailable ? NSLocalizedString("settings.available", comment: "") : NSLocalizedString("settings.unavailable", comment: ""))
                }
            }

            Section(NSLocalizedString("settings.location", comment: "")) {
                LabeledContent(NSLocalizedString("settings.authorization", comment: "")) {
                    Text(monitor.locationPermissionLabel)
                }
                LabeledContent(NSLocalizedString("settings.gps", comment: "")) {
                    Text(monitor.gpsStatusText)
                }

                Button(NSLocalizedString("settings.requestLocationPermission", comment: "")) {
                    monitor.requestLocationPermission()
                }

                Button(NSLocalizedString("settings.openSystemSettings", comment: "")) {
                    monitor.openSystemSettings()
                }
            }

            Section(NSLocalizedString("settings.heading", comment: "")) {
                Text(NSLocalizedString("settings.facingHeading", comment: "") + " \(Int(monitor.currentHeading.rounded()))°")
            }
        }
        .navigationTitle(NSLocalizedString("feature.devices", comment: ""))
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }
}

@MainActor
private final class MapsDevicesMonitor: NSObject, ObservableObject, CLLocationManagerDelegate, UserHeadingProviderDelegate {
    @Published var audioOutputName = ""
    @Published var headphoneMotionAvailable = false
    @Published var locationPermissionLabel = ""
    @Published var gpsStatusText = ""
    @Published var currentHeading: Double = 0

    private let locationManager = CLLocationManager()
    private var headingProvider: UserHeadingProvider?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func start() {
        refreshAudioRoute()
        refreshLocationAuthorizationLabel()
        startHeadingProvider()

        let status = locationManager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            locationManager.startUpdatingLocation()
        }
    }

    func stop() {
        locationManager.stopUpdatingLocation()
        headingProvider?.stopUserHeadingUpdates()
        headingProvider = nil
    }

    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func userHeadingProvider(_ provider: UserHeadingProvider, didUpdateUserHeading heading: HeadingValue?) {
        guard let heading else { return }
        currentHeading = heading.value
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refreshLocationAuthorizationLabel()
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.startUpdatingLocation()
        } else {
            manager.stopUpdatingLocation()
            gpsStatusText = NSLocalizedString("settings.gpsPermissionRequired", comment: "")
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        let accuracy = max(0, Int(location.horizontalAccuracy.rounded()))
        gpsStatusText = String(format: "%.5f, %.5f (±%dm)", lat, lon, accuracy)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        gpsStatusText = "Error: \(error.localizedDescription)"
    }

    private func refreshAudioRoute() {
        let route = AVAudioSession.sharedInstance().currentRoute
        audioOutputName = route.outputs.first?.portName ?? NSLocalizedString("settings.unknown", comment: "")
    }

    private func refreshLocationAuthorizationLabel() {
        switch locationManager.authorizationStatus {
        case .authorizedAlways:
            locationPermissionLabel = NSLocalizedString("settings.authAlways", comment: "")
        case .authorizedWhenInUse:
            locationPermissionLabel = NSLocalizedString("settings.authWhenInUse", comment: "")
        case .denied:
            locationPermissionLabel = NSLocalizedString("settings.authDenied", comment: "")
        case .restricted:
            locationPermissionLabel = NSLocalizedString("settings.authRestricted", comment: "")
        case .notDetermined:
            locationPermissionLabel = NSLocalizedString("settings.authNotDetermined", comment: "")
        @unknown default:
            locationPermissionLabel = NSLocalizedString("settings.authUnknown", comment: "")
        }
    }

    private func startHeadingProvider() {
        headingProvider?.stopUserHeadingUpdates()

        if #available(iOS 14.4, *) {
            let headphoneProvider = HeadphoneMotionProvider()
            if headphoneProvider.isHeadphoneMotionAvailable {
                headphoneMotionAvailable = true
                headphoneProvider.delegate = self
                headphoneProvider.startUserHeadingUpdates()
                headingProvider = headphoneProvider
                return
            }
        }

        headphoneMotionAvailable = false
        let fallback = DeviceMotionProvider()
        fallback.delegate = self
        fallback.startUserHeadingUpdates()
        headingProvider = fallback
    }
}


#Preview {
    SettingsView()
        .environmentObject(SettingsStore())
        .environmentObject(OpenAISubscriptionStore())
}

private struct DetailsDescriptionSettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var openAIStore: OpenAISubscriptionStore
    @State private var showSignOutConfirmation = false

    private var selectedActionControlStyle: Binding<RecognitionActionControlStyle> {
        Binding(
            get: {
                RecognitionActionControlStyle(rawValue: settingsStore.detailsActionControlStyle) ?? .singleAdjustableControl
            },
            set: { settingsStore.detailsActionControlStyle = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section(NSLocalizedString("settings.actionControls", comment: "")) {
                Picker(NSLocalizedString("settings.controlStyle", comment: ""), selection: selectedActionControlStyle) {
                    ForEach(RecognitionActionControlStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
            }

            Section(NSLocalizedString("settings.detailsButtons", comment: "")) {
                ForEach(RecognitionButtonSlot.allCases) { slot in
                    NavigationLink {
                        RecognitionButtonSettingsEditor(
                            title: slot.displayName,
                            selectedKind: detailsPresetKindBinding(for: slot),
                            customTitle: detailsCustomTitleBinding(for: slot),
                            customPrompt: detailsCustomPromptBinding(for: slot)
                        )
                    } label: {
                        LabeledContent(slot.displayName) {
                            Text(settingsStore.detailsPreset(for: slot).title)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Text(NSLocalizedString("settings.detailsButtonsHelp", comment: ""))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if openAIStore.isSignedIn {
                Section {
                    Button(NSLocalizedString("common.signOut", comment: ""), role: .destructive) {
                        showSignOutConfirmation = true
                    }
                }
                .alert(NSLocalizedString("common.signOut", comment: ""), isPresented: $showSignOutConfirmation) {
                    Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {}
                    Button(NSLocalizedString("common.signOut", comment: ""), role: .destructive) {
                        openAIStore.signOut()
                    }
                } message: {
                    Text(NSLocalizedString("settings.signOutConfirm", comment: ""))
                }
            } else {
                Section {
                    Text(NSLocalizedString("settings.notSignedIn", comment: ""))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(NSLocalizedString("feature.detailsRecognition", comment: ""))
    }

    private func detailsPresetKindBinding(for slot: RecognitionButtonSlot) -> Binding<RecognitionPresetKind> {
        Binding(
            get: { settingsStore.detailsPresetKind(for: slot) },
            set: { newValue in
                switch slot {
                case .first:
                    settingsStore.detailsButton1PresetKind = newValue.rawValue
                case .second:
                    settingsStore.detailsButton2PresetKind = newValue.rawValue
                case .third:
                    settingsStore.detailsButton3PresetKind = newValue.rawValue
                case .fourth:
                    settingsStore.detailsButton4PresetKind = newValue.rawValue
                }
            }
        )
    }

    private func detailsCustomTitleBinding(for slot: RecognitionButtonSlot) -> Binding<String> {
        switch slot {
        case .first:
            return $settingsStore.detailsButton1CustomTitle
        case .second:
            return $settingsStore.detailsButton2CustomTitle
        case .third:
            return $settingsStore.detailsButton3CustomTitle
        case .fourth:
            return $settingsStore.detailsButton4CustomTitle
        }
    }

    private func detailsCustomPromptBinding(for slot: RecognitionButtonSlot) -> Binding<String> {
        switch slot {
        case .first:
            return $settingsStore.detailsButton1CustomPrompt
        case .second:
            return $settingsStore.detailsButton2CustomPrompt
        case .third:
            return $settingsStore.detailsButton3CustomPrompt
        case .fourth:
            return $settingsStore.detailsButton4CustomPrompt
        }
    }
}

private struct QuickRecognitionSettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @StateObject private var gemmaModelManager = GemmaModelManager.shared

    #if canImport(Translation)
    @StateObject private var translationLanguageStore = TranslationLanguageStore()
    #endif

    private var selectedCaptionLength: Binding<QuickCaptionLength> {
        Binding(
            get: { QuickCaptionLength(rawValue: settingsStore.quickCaptionLength) ?? .short },
            set: { settingsStore.quickCaptionLength = $0.rawValue }
        )
    }

    private var selectedContinuousCaptureInterval: Binding<QuickContinuousCaptureInterval> {
        Binding(
            get: { QuickContinuousCaptureInterval(rawValue: settingsStore.quickContinuousCaptureInterval) ?? .defaultInterval },
            set: { settingsStore.quickContinuousCaptureInterval = $0.rawValue }
        )
    }

    private var selectedActionControlStyle: Binding<RecognitionActionControlStyle> {
        Binding(
            get: { RecognitionActionControlStyle(rawValue: settingsStore.quickActionControlStyle) ?? .onScreenButtons },
            set: { settingsStore.quickActionControlStyle = $0.rawValue }
        )
    }

    private var selectedTriggerMode: Binding<QuickRecognitionTriggerMode> {
        Binding(
            get: { QuickRecognitionTriggerMode(rawValue: settingsStore.quickContinuousTriggerMode) ?? .time },
            set: { settingsStore.quickContinuousTriggerMode = $0.rawValue }
        )
    }

    private var gemmaOfflineSection: some View {
        Section(NSLocalizedString("gemma.sectionTitle", comment: "")) {
            ForEach(GemmaModelKind.allCases) { kind in
                GemmaModelRow(
                    kind: kind,
                    manager: gemmaModelManager,
                    isSelected: selectedGemmaModelKind.wrappedValue == kind,
                    onSelect: { selectedGemmaModelKind.wrappedValue = kind }
                )
            }
        }
    }

    private var selectedGemmaModelKind: Binding<GemmaModelKind> {
        Binding(
            get: { GemmaModelKind(rawValue: settingsStore.quickGemmaModelKind) ?? .e2b },
            set: { settingsStore.quickGemmaModelKind = $0.rawValue }
        )
    }

    private var selectedModelProvider: Binding<QuickModelProvider> {
        Binding(
            get: { QuickModelProvider(rawValue: settingsStore.quickModelProvider) ?? .gemma },
            set: { settingsStore.quickModelProvider = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section(NSLocalizedString("settings.modelProvider", comment: "")) {
                Picker(NSLocalizedString("settings.modelProvider", comment: ""), selection: selectedModelProvider) {
                    ForEach(QuickModelProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
            }

            if selectedModelProvider.wrappedValue == .moondream {
                Section(NSLocalizedString("settings.sectionAPIKey", comment: "")) {
                    SecureField(NSLocalizedString("settings.apiKey", comment: ""), text: $settingsStore.quickMoondreamAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }

            if selectedModelProvider.wrappedValue == .gemma {
                gemmaOfflineSection
            }

            Section(NSLocalizedString("settings.sectionTakePhoto", comment: "")) {
                Picker(NSLocalizedString("settings.captionLength", comment: ""), selection: selectedCaptionLength) {
                    ForEach(QuickCaptionLength.allCases) { length in
                        Text(length.displayName).tag(length)
                    }
                }
            }

            Section(NSLocalizedString("settings.continuousMode", comment: "")) {
                Picker(NSLocalizedString("settings.triggerMode", comment: ""), selection: selectedTriggerMode) {
                    ForEach(QuickRecognitionTriggerMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Picker(NSLocalizedString("settings.captureFrequency", comment: ""), selection: selectedContinuousCaptureInterval) {
                    ForEach(QuickContinuousCaptureInterval.allCases) { interval in
                        Text(interval.displayName).tag(interval)
                    }
                }
            }

            Section(NSLocalizedString("settings.quickButtons", comment: "")) {
                Picker(NSLocalizedString("settings.controlStyle", comment: ""), selection: selectedActionControlStyle) {
                    ForEach(RecognitionActionControlStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }

                ForEach(RecognitionButtonSlot.allCases) { slot in
                    NavigationLink {
                        RecognitionButtonSettingsEditor(
                            title: slot.displayName,
                            selectedKind: quickPresetKindBinding(for: slot),
                            customTitle: quickCustomTitleBinding(for: slot),
                            customPrompt: quickCustomPromptBinding(for: slot)
                        )
                    } label: {
                        LabeledContent(slot.displayName) {
                            Text(settingsStore.quickPreset(for: slot).title)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            translationSection
        }
        .navigationTitle(NSLocalizedString("feature.quickRecognition", comment: ""))
        #if canImport(Translation)
        .task {
            if #available(iOS 18.0, *) {
                await translationLanguageStore.loadLanguages()
                refreshSelectedLanguageIfNeeded()
            }
        }
        #endif
    }

    @ViewBuilder
    private var translationSection: some View {
        #if canImport(Translation)
        if #available(iOS 18.0, *) {
            Section(NSLocalizedString("settings.translation", comment: "")) {
                Toggle(NSLocalizedString("settings.enableTranslation", comment: ""), isOn: $settingsStore.quickCaptionTranslationEnabled)
                    .disabled(!translationLanguageStore.hasAvailableLanguages)

                if translationLanguageStore.isLoading {
                    LabeledContent(NSLocalizedString("settings.targetLanguage", comment: "")) {
                        Text(NSLocalizedString("settings.loadingLanguages", comment: ""))
                            .foregroundStyle(.secondary)
                    }
                } else if let errorMessage = translationLanguageStore.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if translationLanguageStore.availableLanguages.isEmpty {
                    Text(NSLocalizedString("settings.noTranslationLangs", comment: ""))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Picker(NSLocalizedString("settings.targetLanguage", comment: ""), selection: $settingsStore.quickCaptionTranslationTargetLanguage) {
                        Text(NSLocalizedString("settings.chooseLanguage", comment: "")).tag("")

                        ForEach(translationLanguageStore.availableLanguages) { language in
                            Text(language.displayName).tag(language.identifier)
                        }
                    }
                    .disabled(!settingsStore.quickCaptionTranslationEnabled)
                }
            }
        } else {
            Section(NSLocalizedString("settings.translation", comment: "")) {
                Text(NSLocalizedString("settings.translationUnavailable", comment: ""))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        #else
        Section(NSLocalizedString("settings.translation", comment: "")) {
            Text(NSLocalizedString("settings.translationUnavailable", comment: ""))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        #endif
    }

    #if canImport(Translation)
    private func refreshSelectedLanguageIfNeeded() {
        guard !translationLanguageStore.isLoading else { return }

        if translationLanguageStore.availableLanguages.isEmpty {
            settingsStore.quickCaptionTranslationTargetLanguage = ""
            settingsStore.quickCaptionTranslationEnabled = false
            return
        }

        if settingsStore.quickCaptionTranslationTargetLanguage.isEmpty {
            return
        }

        let selectedLanguageStillAvailable = translationLanguageStore.availableLanguages.contains {
            $0.identifier == settingsStore.quickCaptionTranslationTargetLanguage
        }

        if !selectedLanguageStillAvailable {
            settingsStore.quickCaptionTranslationTargetLanguage = ""
        }
    }
    #endif

    private func quickPresetKindBinding(for slot: RecognitionButtonSlot) -> Binding<RecognitionPresetKind> {
        Binding(
            get: { settingsStore.quickPresetKind(for: slot) },
            set: { newValue in
                switch slot {
                case .first:
                    settingsStore.quickButton1PresetKind = newValue.rawValue
                case .second:
                    settingsStore.quickButton2PresetKind = newValue.rawValue
                case .third:
                    settingsStore.quickButton3PresetKind = newValue.rawValue
                case .fourth:
                    settingsStore.quickButton4PresetKind = newValue.rawValue
                }
            }
        )
    }

    private func quickCustomTitleBinding(for slot: RecognitionButtonSlot) -> Binding<String> {
        switch slot {
        case .first:
            return $settingsStore.quickButton1CustomTitle
        case .second:
            return $settingsStore.quickButton2CustomTitle
        case .third:
            return $settingsStore.quickButton3CustomTitle
        case .fourth:
            return $settingsStore.quickButton4CustomTitle
        }
    }

    private func quickCustomPromptBinding(for slot: RecognitionButtonSlot) -> Binding<String> {
        switch slot {
        case .first:
            return $settingsStore.quickButton1CustomPrompt
        case .second:
            return $settingsStore.quickButton2CustomPrompt
        case .third:
            return $settingsStore.quickButton3CustomPrompt
        case .fourth:
            return $settingsStore.quickButton4CustomPrompt
        }
    }
}

private struct RecognitionButtonSettingsEditor: View {
    let title: String
    @Binding var selectedKind: RecognitionPresetKind
    @Binding var customTitle: String
    @Binding var customPrompt: String

    var body: some View {
        Form {
            Section(NSLocalizedString("settings.behavior", comment: "")) {
                Picker(NSLocalizedString("settings.use", comment: ""), selection: $selectedKind) {
                    ForEach(RecognitionPresetKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }

                Text(NSLocalizedString("settings.useHelp", comment: ""))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if selectedKind == .custom {
                Section(NSLocalizedString("settings.custom", comment: "")) {
                    TextField(NSLocalizedString("settings.buttonName", comment: ""), text: $customTitle)
                        .textInputAutocapitalization(.words)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString("settings.prompt", comment: ""))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        TextEditor(text: $customPrompt)
                            .frame(minHeight: 120)
                    }

                    Text(NSLocalizedString("settings.customHelp", comment: ""))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(title)
    }
}

private struct FaceRecognitionSettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        Form {
            Section(NSLocalizedString("settings.speech", comment: "")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("settings.speechDelay", comment: ""))
                    Slider(value: $settingsStore.faceSpeechCooldown, in: 1...6, step: 0.5)
                    Text("\(settingsStore.faceSpeechCooldown.formatted(.number.precision(.fractionLength(1)))) ") + Text(NSLocalizedString("settings.secondsUnit", comment: ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(NSLocalizedString("settings.recognition", comment: "")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("settings.matchSensitivity", comment: ""))
                    Slider(value: $settingsStore.faceMatchThreshold, in: 0.30...0.90, step: 0.01)
                    Text(settingsStore.faceMatchThreshold.formatted(.percent.precision(.fractionLength(0))))

                    Text(NSLocalizedString("settings.topMatchMargin", comment: ""))
                    Text(NSLocalizedString("settings.minGapPrefix", comment: "") + String(format: "%.3f", settingsStore.faceMatchMargin))
                    Slider(value: $settingsStore.faceMatchMargin, in: 0.01...0.10, step: 0.005)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle(NSLocalizedString("settings.suggestUnknownFaces", comment: ""), isOn: $settingsStore.suggestUnknownFaces)
            }

            Section(NSLocalizedString("settings.savedFacesSection", comment: "")) {
                NavigationLink(NSLocalizedString("feature.savedFaces", comment: "")) {
                    SavedFacesView()
                }
            }

            Section(NSLocalizedString("settings.recognitionLog", comment: "")) {
                if settingsStore.faceRecognitionLogs.isEmpty {
                    Text(NSLocalizedString("settings.noLogEntries", comment: ""))
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        let logText = settingsStore.faceRecognitionLogs.map { "[\($0.formattedTime)] \($0.message)" }.joined(separator: "\n")
                        UIPasteboard.general.string = logText
                    } label: {
                        Label(NSLocalizedString("settings.copyAllLogs", comment: ""), systemImage: "doc.on.doc")
                    }

                    Button(role: .destructive) {
                        FaceRecognitionLogStore.shared.clear()
                        settingsStore.faceRecognitionLogs = []
                    } label: {
                        Label(NSLocalizedString("settings.clearLog", comment: ""), systemImage: "trash")
                    }

                    ForEach(settingsStore.faceRecognitionLogs) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.formattedTime)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(entry.message)
                                .font(.caption)
                        }
                    }
                }
            }

            Section(NSLocalizedString("settings.trainingTips", comment: "")) {
                Text(NSLocalizedString("settings.tip1", comment: ""))
                Text(NSLocalizedString("settings.tip2", comment: ""))
                Text(NSLocalizedString("settings.tip3", comment: ""))
            }
        }
        .navigationTitle(NSLocalizedString("feature.faceRecognition", comment: ""))
    }
}

private struct ReadTextRecognitionSettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        Form {
            Section(NSLocalizedString("settings.ocrEngine", comment: "")) {
                Picker(NSLocalizedString("settings.ocrEngine", comment: ""), selection: Binding(
                    get: { OCREngineChoice(rawValue: settingsStore.ocrEngine) ?? .mlKit },
                    set: { settingsStore.ocrEngine = $0.rawValue }
                )) {
                    ForEach(OCREngineChoice.allCases) { choice in
                        Text(choice.displayTitle).tag(choice)
                    }
                }
            }
            Section(NSLocalizedString("settings.speech", comment: "")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("settings.speechDelay", comment: ""))
                    Slider(value: $settingsStore.readTextSpeechCooldown, in: 1...6, step: 0.5)
                    Text("\(settingsStore.readTextSpeechCooldown.formatted(.number.precision(.fractionLength(1)))) ") + Text(NSLocalizedString("settings.secondsUnit", comment: ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(NSLocalizedString("feature.readText", comment: ""))
    }
}

private struct SavedFacesView: View {
    @StateObject private var viewModel = SavedFacesViewModel()
    @State private var renamingProfile: FaceProfile?
    @State private var draftName = ""

    var body: some View {
        List {
            if viewModel.profiles.isEmpty {
                Text(NSLocalizedString("common.noFacesSaved", comment: ""))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.profiles) { profile in
                    Text(profile.name)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                viewModel.deleteFaces(at: IndexSet(integer: viewModel.profiles.firstIndex(where: { $0.id == profile.id }) ?? 0))
                            } label: {
                                Label(NSLocalizedString("common.delete", comment: ""), systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button {
                                draftName = profile.name
                                renamingProfile = profile
                            } label: {
                                Label(NSLocalizedString("common.rename", comment: ""), systemImage: "pencil")
                            }
                        }
                        .accessibilityAction(named: Text(NSLocalizedString("common.rename", comment: "") + " \(profile.name)")) {
                            draftName = profile.name
                            renamingProfile = profile
                        }
                }
                .onDelete(perform: viewModel.deleteFaces)
            }
        }
        .navigationTitle(NSLocalizedString("face.savedFaces", comment: ""))
        .task {
            viewModel.loadProfiles()
        }
        .alert(NSLocalizedString("face.savedFacesError", comment: ""), isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) {
            Button(NSLocalizedString("common.ok", comment: "")) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert(NSLocalizedString("face.renameFace", comment: ""), isPresented: Binding(get: { renamingProfile != nil }, set: { if !$0 { renamingProfile = nil } })) {
            TextField(NSLocalizedString("face.personName", comment: ""), text: $draftName)
                .textInputAutocapitalization(.words)
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {
                renamingProfile = nil
                draftName = ""
            }
            Button(NSLocalizedString("common.save", comment: "")) {
                guard let renamingProfile else { return }
                viewModel.renameProfile(id: renamingProfile.id, newName: draftName)
                self.renamingProfile = nil
                draftName = ""
            }
        } message: {
            Text(NSLocalizedString("face.renameMessage", comment: ""))
        }
    }
}

@MainActor
private final class SavedFacesViewModel: ObservableObject {
    @Published var profiles: [FaceProfile] = []
    @Published var errorMessage: String?

    private let faceStore = FaceStore()

    func loadProfiles() {
        Task {
            do {
                profiles = try await faceStore.loadProfiles()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func deleteFaces(at offsets: IndexSet) {
        let deletedProfiles = offsets.compactMap { index in
            profiles.indices.contains(index) ? profiles[index] : nil
        }
        let remainingProfiles = profiles.enumerated()
            .filter { !offsets.contains($0.offset) }
            .map(\.element)

        Task {
            do {
                for profile in deletedProfiles {
                    if let filename = profile.sampleImageFilename {
                        try await faceStore.deleteImage(named: filename)
                    }
                }
                try await faceStore.saveProfiles(remainingProfiles)
                profiles = remainingProfiles
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func renameProfile(id: UUID, newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        var updatedProfiles = profiles
        guard let profileIndex = updatedProfiles.firstIndex(where: { $0.id == id }) else { return }

        updatedProfiles[profileIndex].name = trimmedName
        updatedProfiles[profileIndex].updatedAt = .now

        Task {
            do {
                try await faceStore.saveProfiles(updatedProfiles)
                profiles = updatedProfiles
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#if canImport(Translation)
@MainActor
private final class TranslationLanguageStore: ObservableObject {
    @Published private(set) var availableLanguages: [TranslationLanguageOption] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    var hasAvailableLanguages: Bool {
        !availableLanguages.isEmpty
    }

    func loadLanguages() async {
        guard availableLanguages.isEmpty, !isLoading else { return }

        isLoading = true
        errorMessage = nil

        if #available(iOS 18.0, *) {
            do {
                let supportedLanguages = try await LanguageAvailability().supportedLanguages
                availableLanguages = supportedLanguages
                    .map(TranslationLanguageOption.init)
                    .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            } catch {
                errorMessage = NSLocalizedString("settings.unableToLoadLanguages", comment: "")
                availableLanguages = []
            }
        } else {
            errorMessage = NSLocalizedString("settings.translationUnavailable", comment: "")
            availableLanguages = []
        }

        isLoading = false
    }
}

private struct TranslationLanguageOption: Identifiable, Equatable {
    let identifier: String

    @available(iOS 18.0, *)
    init(language: Locale.Language) {
        if !language.maximalIdentifier.isEmpty {
            identifier = language.maximalIdentifier
        } else if !language.minimalIdentifier.isEmpty {
            identifier = language.minimalIdentifier
        } else {
            identifier = String(describing: language)
        }
    }

    var id: String { identifier }

    var displayName: String {
        if let localizedName = Locale.current.localizedString(forIdentifier: identifier), !localizedName.isEmpty {
            return localizedName
        }

        return identifier
    }
}
#endif

private struct LyricPrompterSettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var openAIStore: OpenAISubscriptionStore
    @State private var availableModels: [String] = []
    @State private var isLoadingModels = false
    @State private var modelError: String?

    private var selectedProvider: Binding<LyricLLMProvider> {
        Binding(
            get: { LyricLLMProvider(rawValue: settingsStore.lyricLLMProvider) ?? .codex },
            set: { settingsStore.lyricLLMProvider = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section(NSLocalizedString("settings.aiProvider", comment: "")) {
                Picker(NSLocalizedString("settings.provider", comment: ""), selection: selectedProvider) {
                    ForEach(LyricLLMProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }

                if selectedProvider.wrappedValue == .codex {
                    if openAIStore.isSignedIn {
                        Label(NSLocalizedString("settings.signedInWithChatGPT", comment: ""), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label(NSLocalizedString("settings.notSignedInLabel", comment: ""), systemImage: "xmark.circle")
                            .foregroundStyle(.red)
                    }
                } else {
                    TextField(NSLocalizedString("settings.apiKey", comment: ""), text: $settingsStore.lyricAPIKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()

                    TextField(NSLocalizedString("settings.baseURLOptional", comment: ""), text: $settingsStore.lyricBaseURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }

            Section(NSLocalizedString("settings.model", comment: "")) {
                if isLoadingModels {
                    HStack {
                        ProgressView()
                        Text(NSLocalizedString("settings.loadingModels", comment: ""))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Picker(NSLocalizedString("settings.model", comment: ""), selection: $settingsStore.lyricModelID) {
                        ForEach(availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                }

                if let modelError {
                    Text(modelError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button {
                    Task { await loadModels() }
                } label: {
                    Label(NSLocalizedString("settings.refreshModels", comment: ""), systemImage: "arrow.clockwise")
                }
                .disabled(isLoadingModels)
            }

            Section(NSLocalizedString("settings.playback", comment: "")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("settings.advanceOffset", comment: ""))
                    Slider(value: $settingsStore.lyricAdvanceOffset, in: 0...5, step: 0.5)
                    Text(settingsStore.lyricAdvanceOffset.formatted(.number.precision(.fractionLength(1)))) + Text(" " + NSLocalizedString("settings.secondsBeforeLyric", comment: ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(NSLocalizedString("settings.about", comment: "")) {
                Text(NSLocalizedString("settings.lyricAbout1", comment: ""))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(NSLocalizedString("settings.lyricAbout2", comment: ""))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(NSLocalizedString("feature.lyricPrompter", comment: ""))
        .onAppear {
            availableModels = defaultModels(for: selectedProvider.wrappedValue)
            if settingsStore.lyricModelID.isEmpty || !availableModels.contains(settingsStore.lyricModelID) {
                settingsStore.lyricModelID = availableModels.first ?? ""
            }
        }
    }

    private func defaultModels(for provider: LyricLLMProvider) -> [String] {
        switch provider {
        case .codex: return LyricProviderModels.codex
        case .gemini: return LyricProviderModels.gemini
        case .openai: return LyricProviderModels.openai
        }
    }

    private func loadModels() async {
        isLoadingModels = true
        modelError = nil

        let provider = selectedProvider.wrappedValue

        switch provider {
        case .codex:
            availableModels = LyricProviderModels.codex
            settingsStore.lyricModelID = availableModels.first ?? ""
        case .gemini:
            let key = settingsStore.lyricAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                modelError = NSLocalizedString("settings.enterAPIKeyFirst", comment: "")
                isLoadingModels = false
                return
            }
            let base = settingsStore.lyricBaseURL.isEmpty ? "https://generativelanguage.googleapis.com/v1beta" : settingsStore.lyricBaseURL
            if let models = try? await fetchGeminiModels(apiKey: key, baseURL: base) {
                availableModels = models
                if !models.contains(settingsStore.lyricModelID) {
                    settingsStore.lyricModelID = models.first ?? ""
                }
            } else {
                availableModels = LyricProviderModels.gemini
            }
        case .openai:
            let key = settingsStore.lyricAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                modelError = NSLocalizedString("settings.enterAPIKeyFirst", comment: "")
                isLoadingModels = false
                return
            }
            let base = settingsStore.lyricBaseURL.isEmpty ? "https://api.openai.com/v1" : settingsStore.lyricBaseURL
            if let models = try? await fetchOpenAIModels(apiKey: key, baseURL: base) {
                availableModels = models
                if !models.contains(settingsStore.lyricModelID) {
                    settingsStore.lyricModelID = models.first ?? ""
                }
            } else {
                availableModels = LyricProviderModels.openai
            }
        }

        isLoadingModels = false
    }

    private func fetchGeminiModels(apiKey: String, baseURL: String) async throws -> [String] {
        let urlStr = "\(baseURL)/models?key=\(apiKey)"
        guard let url = URL(string: urlStr) else { return [] }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else { return [] }
        return models.compactMap { $0["name"] as? String }
            .map { $0.replacingOccurrences(of: "models/", with: "") }
            .sorted()
    }

    private func fetchOpenAIModels(apiKey: String, baseURL: String) async throws -> [String] {
        let urlStr = "\(baseURL)/models"
        guard let url = URL(string: urlStr) else { return [] }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArr = json["data"] as? [[String: Any]] else { return [] }
        return dataArr.compactMap { $0["id"] as? String }.sorted()
    }
}

private struct GemmaModelRow: View {
    let kind: GemmaModelKind
    @ObservedObject var manager: GemmaModelManager
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        let state = manager.states[kind] ?? .notDownloaded

        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(kind.displayName)
                    .font(.body)
                    .fontWeight(isSelected ? .semibold : .regular)

                switch state {
                case .downloaded:
                    Text(NSLocalizedString("gemma.status.downloaded", comment: ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .downloading(let fraction):
                    ProgressView(value: min(max(fraction, 0), 1))
                        .progressViewStyle(.linear)
                    Text(String(format: NSLocalizedString("gemma.status.downloading", comment: ""), Int((fraction * 100).rounded())))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .failed(let message):
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                case .notDownloaded:
                    Text(NSLocalizedString("gemma.status.notDownloaded", comment: ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
                    .fontWeight(.semibold)
            }

            Button {
                switch state {
                case .downloaded:
                    manager.delete(kind)
                case .downloading:
                    manager.cancel(kind)
                case .failed, .notDownloaded:
                    manager.download(kind)
                }
            } label: {
                Text(title(for: state))
            }
            .disabled(false)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func title(for state: GemmaModelManager.DownloadState) -> String {
        switch state {
        case .downloaded:
            return NSLocalizedString("gemma.action.delete", comment: "")
        case .downloading:
            return NSLocalizedString("gemma.action.cancel", comment: "")
        case .failed, .notDownloaded:
            return NSLocalizedString("gemma.action.download", comment: "")
        }
    }
}
