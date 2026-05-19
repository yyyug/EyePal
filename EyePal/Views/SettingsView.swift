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
            Section("Navigation") {
                NavigationLink("Feature Order") {
                    FeatureOrderSettingsView()
                        .environmentObject(settingsStore)
                }
            }

            Section("Speech") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Speech delay")
                    Slider(value: $settingsStore.speechCooldown, in: 1...6, step: 0.5)
                    Text("\(settingsStore.speechCooldown.formatted(.number.precision(.fractionLength(1)))) seconds")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Features") {
                NavigationLink("Details Recognition") {
                    DetailsDescriptionSettingsView()
                        .environmentObject(settingsStore)
                        .environmentObject(openAIStore)
                }

                NavigationLink("Quick Recognition") {
                    QuickRecognitionSettingsView()
                        .environmentObject(settingsStore)
                }

                NavigationLink("Faces") {
                    FaceRecognitionSettingsView()
                        .environmentObject(settingsStore)
                }

                NavigationLink("Maps") {
                    MapsSettingsView()
                        .environmentObject(settingsStore)
                }
            }
        }
        .navigationTitle("Settings")
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

                        VStack(alignment: .leading, spacing: 4) {
                            Text(feature.displayName)
                            Text(settingsStore.tabFeatures.contains(feature) ? "Tab" : "More")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.tertiary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Drag to reorder. You can also use the Move Up and Move Down actions.")
                    .accessibilityAction(named: Text("Move Up")) {
                        settingsStore.moveFeature(feature, by: -1)
                    }
                    .accessibilityAction(named: Text("Move Down")) {
                        settingsStore.moveFeature(feature, by: 1)
                    }
                }
                .onMove(perform: settingsStore.moveFeature)
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Feature Order")
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
            Section("General") {
                Toggle("Use Metric Units", isOn: $settingsStore.mapsMetricUnits)
                Toggle("Mix Audio With Other Apps", isOn: $settingsStore.mapsMixAudioWithOthers)
            }

            Section("Audio Beacon") {
                Picker("Beacon Style", selection: $settingsStore.mapsBeaconStyle) {
                    ForEach(MapsBeaconStyle.allCases, id: \.rawValue) { style in
                        Text(style.displayName).tag(style.rawValue)
                    }
                }

                Toggle("Beacon Melodies", isOn: $settingsStore.mapsBeaconMelodiesEnabled)
                Toggle("Beacon Audio Enabled", isOn: $settingsStore.mapsBeaconAudioEnabled)
                Toggle("Beacon Alerts", isOn: $settingsStore.mapsBeaconAlertsEnabled)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Beacon Volume")
                        Spacer()
                        Text(String(format: "%.2f", settingsStore.mapsBeaconVolume))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settingsStore.mapsBeaconVolume, in: 0...1, step: 0.05)
                }
            }

            Section("Voice and Other Audio") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Voice Volume")
                        Spacer()
                        Text(String(format: "%.2f", settingsStore.mapsVoiceVolume))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settingsStore.mapsVoiceVolume, in: 0...1, step: 0.05)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Other Volume")
                        Spacer()
                        Text(String(format: "%.2f", settingsStore.mapsOtherVolume))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settingsStore.mapsOtherVolume, in: 0...1, step: 0.05)
                }
            }

            Section("Callouts") {
                Toggle("Automatic Callouts", isOn: $settingsStore.mapsAutoCalloutsEnabled)
                Toggle("POI Callouts", isOn: poiCalloutsBinding)
                    .disabled(!settingsStore.mapsAutoCalloutsEnabled)
                Toggle("Mobility Callouts", isOn: mobilityCalloutsBinding)
                    .disabled(!settingsStore.mapsAutoCalloutsEnabled)
                Toggle("Beacon Callouts", isOn: $settingsStore.mapsDestinationSenseEnabled)
                    .disabled(!settingsStore.mapsAutoCalloutsEnabled)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Auto Callout Interval")
                        Spacer()
                        Text("\(Int(settingsStore.mapsAutoCalloutIntervalSeconds))s")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settingsStore.mapsAutoCalloutIntervalSeconds, in: 8...60, step: 1)
                }
            }

            Section("Street Preview") {
                Toggle("Include Unnamed Roads", isOn: $settingsStore.mapsPreviewIncludeUnnamedRoads)
            }

            Section("Spatial Audio") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Maximum Distance")
                        Spacer()
                        Text("\(Int(settingsStore.mapsMaxDistanceMeters)) m")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settingsStore.mapsMaxDistanceMeters, in: 10...200, step: 10)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Reverb Blend")
                        Spacer()
                        Text(String(format: "%.2f", settingsStore.mapsReverbBlend))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settingsStore.mapsReverbBlend, in: 0...0.5, step: 0.05)
                }
                
                Toggle("Head Tracking", isOn: $settingsStore.mapsHeadTrackingEnabled)
                    .help("Use AirPods motion sensors for immersive audio")

                Toggle("Background Audio", isOn: $settingsStore.mapsBackgroundAudioEnabled)

                Text("High-quality HRTF spatial audio with 3D rendering.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("Maps callout controls are available on the Maps tab: My Location, Around Me, Ahead of Me, Nearby Markers, and Along Street Guide.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Devices") {
                NavigationLink("Headphones and GPS") {
                    MapsDevicesSettingsView()
                }
            }
        }
        .navigationTitle("Maps")
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
            Section("Audio") {
                LabeledContent("Output") {
                    Text(monitor.audioOutputName)
                }
                LabeledContent("Headphone motion") {
                    Text(monitor.headphoneMotionAvailable ? "Available" : "Unavailable")
                }
            }

            Section("Location") {
                LabeledContent("Authorization") {
                    Text(monitor.locationPermissionLabel)
                }
                LabeledContent("GPS") {
                    Text(monitor.gpsStatusText)
                }

                Button("Request Location Permission") {
                    monitor.requestLocationPermission()
                }

                Button("Open System Settings") {
                    monitor.openSystemSettings()
                }
            }

            Section("Heading") {
                Text("Facing heading: \(Int(monitor.currentHeading.rounded()))°")
            }
        }
        .navigationTitle("Devices")
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }
}

@MainActor
private final class MapsDevicesMonitor: NSObject, ObservableObject, CLLocationManagerDelegate, UserHeadingProviderDelegate {
    @Published var audioOutputName = "Unknown"
    @Published var headphoneMotionAvailable = false
    @Published var locationPermissionLabel = "Not determined"
    @Published var gpsStatusText = "Unavailable"
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
            gpsStatusText = "Permission required"
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
        audioOutputName = route.outputs.first?.portName ?? "Unknown"
    }

    private func refreshLocationAuthorizationLabel() {
        switch locationManager.authorizationStatus {
        case .authorizedAlways:
            locationPermissionLabel = "Always"
        case .authorizedWhenInUse:
            locationPermissionLabel = "When In Use"
        case .denied:
            locationPermissionLabel = "Denied"
        case .restricted:
            locationPermissionLabel = "Restricted"
        case .notDetermined:
            locationPermissionLabel = "Not determined"
        @unknown default:
            locationPermissionLabel = "Unknown"
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
            Section("Action Controls") {
                Picker("Control Style", selection: selectedActionControlStyle) {
                    ForEach(RecognitionActionControlStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
            }

            Section("Details Buttons") {
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

                Text("Each button can use Product, Dish, Short Text, or your own Custom prompt.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if openAIStore.isSignedIn {
                Section {
                    Button("Sign Out", role: .destructive) {
                        openAIStore.signOut()
                    }
                }
            } else {
                Section {
                    Text("Not signed in.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Details Recognition")
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

    var body: some View {
        Form {
            Section {
                SecureField("API Key", text: $settingsStore.quickMoondreamAPIKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section("Take Photo") {
                Picker("Caption Length", selection: selectedCaptionLength) {
                    ForEach(QuickCaptionLength.allCases) { length in
                        Text(length.displayName).tag(length)
                    }
                }

                Text("This setting applies to Take Photo only. Continuous mode uses the short caption style.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Continuous Mode") {
                Picker("Capture Frequency", selection: selectedContinuousCaptureInterval) {
                    ForEach(QuickContinuousCaptureInterval.allCases) { interval in
                        Text(interval.displayName).tag(interval)
                    }
                }

                Text("Choose how often Continuous mode takes a picture. Each completed result is announced when available.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Quick Buttons") {
                Picker("Control Style", selection: selectedActionControlStyle) {
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

                Text("Set each button to Product, Dish, Short Text, or a Custom prompt.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            translationSection
        }
        .navigationTitle("Quick Recognition")
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
            Section("Translation") {
                Toggle("Enable Translation", isOn: $settingsStore.quickCaptionTranslationEnabled)
                    .disabled(!translationLanguageStore.hasAvailableLanguages)

                if translationLanguageStore.isLoading {
                    LabeledContent("Target Language") {
                        Text("Loading available languages...")
                            .foregroundStyle(.secondary)
                    }
                } else if let errorMessage = translationLanguageStore.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if translationLanguageStore.availableLanguages.isEmpty {
                    Text("No translation languages are currently available on this device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Target Language", selection: $settingsStore.quickCaptionTranslationTargetLanguage) {
                        Text("Choose a language").tag("")

                        ForEach(translationLanguageStore.availableLanguages) { language in
                            Text(language.displayName).tag(language.identifier)
                        }
                    }
                    .disabled(!settingsStore.quickCaptionTranslationEnabled)
                }

                Text("Translate Quick Recognition results into the language you choose below.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else {
            Section("Translation") {
                Text("Translation is unavailable on this device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        #else
        Section("Translation") {
            Text("Translation is unavailable on this device.")
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
            Section("Behavior") {
                Picker("Use", selection: $selectedKind) {
                    ForEach(RecognitionPresetKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }

                Text("Choose what this button does in the camera tab.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if selectedKind == .custom {
                Section("Custom") {
                    TextField("Button Name", text: $customTitle)
                        .textInputAutocapitalization(.words)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Prompt")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        TextEditor(text: $customPrompt)
                            .frame(minHeight: 120)
                    }

                    Text("This custom name and prompt are used when this button is set to Custom.")
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
            Section("Recognition") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Match sensitivity")
                    Slider(value: $settingsStore.faceMatchThreshold, in: 0.84...0.98, step: 0.01)
                    Text(settingsStore.faceMatchThreshold.formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("Suggest unknown faces", isOn: $settingsStore.suggestUnknownFaces)
            }

            Section("Saved Faces") {
                NavigationLink("Manage Saved Faces") {
                    SavedFacesView()
                }
            }

            Section("Training Tips") {
                Text("Save a face in bright, even lighting.")
                Text("Capture the person from a comfortable conversation distance.")
                Text("If recognition is inconsistent, save a fresh sample for that person.")
            }
        }
        .navigationTitle("Face Recognition")
    }
}

private struct SavedFacesView: View {
    @StateObject private var viewModel = SavedFacesViewModel()
    @State private var renamingProfile: FaceProfile?
    @State private var draftName = ""

    var body: some View {
        List {
            if viewModel.profiles.isEmpty {
                Text("No faces have been saved yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.profiles) { profile in
                    HStack {
                        Text(profile.name)
                        Spacer()
                        Button("Rename") {
                            draftName = profile.name
                            renamingProfile = profile
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .onDelete(perform: viewModel.deleteFaces)
            }
        }
        .navigationTitle("Saved Faces")
        .task {
            viewModel.loadProfiles()
        }
        .alert("Saved Faces Error", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("Rename Face", isPresented: Binding(get: { renamingProfile != nil }, set: { if !$0 { renamingProfile = nil } })) {
            TextField("Person's name", text: $draftName)
                .textInputAutocapitalization(.words)
            Button("Cancel", role: .cancel) {
                renamingProfile = nil
                draftName = ""
            }
            Button("Save") {
                guard let renamingProfile else { return }
                viewModel.renameProfile(id: renamingProfile.id, newName: draftName)
                self.renamingProfile = nil
                draftName = ""
            }
        } message: {
            Text("Enter a new name for this saved face.")
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
                errorMessage = "Unable to load translation languages right now."
                availableLanguages = []
            }
        } else {
            errorMessage = "Translation is unavailable on this device."
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
