import SwiftUI
import CoreLocation
import AVFoundation
import MapKit
import Combine

private let alaViaBaseURL = URL(string: "https://via.inclu.si")!

struct MapsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var openAIStore: OpenAISubscriptionStore
    @StateObject private var viewModel = MapsViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    soundscapeHomeCard
                    markerCard
                    guidedRouteCard
                    beaconCard
                    autoCalloutCard
                }
                .padding()
            }
            .navigationTitle("Maps")
            .navigationDestination(for: AlongStreetRoute.self) { _ in
                AlongStreetGuideView(viewModel: viewModel)
                    .environmentObject(openAIStore)
            }
        }
        .onAppear {
            viewModel.bind(settingsStore: settingsStore)
        }
        .onDisappear {
            viewModel.unbind()
        }
        .alert(
            "Maps Error",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var soundscapeHomeCard: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 8) {
                Button("My Location") {
                    viewModel.calloutMyLocation()
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("My Location")
                .accessibilityHint("Announces your current location and heading")

                Button("Around Me") {
                    viewModel.playAroundMeSpatialAudio()
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Around Me")
                .accessibilityHint("Plays spatial audio cues of nearby places")

                Button("Ahead of Me") {
                    viewModel.playAheadOfMeSpatialAudio()
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Ahead of Me")
                .accessibilityHint("Plays spatial audio cues of places ahead")

                Button("Nearby Markers") {
                    viewModel.calloutNearbyMarkers()
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Nearby Markers")
                .accessibilityHint("Lists saved markers nearby")

                NavigationLink(value: AlongStreetRoute()) {
                    Text("Along Street Guide")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Current Road")
                    .font(.headline)
                Text(viewModel.currentRoadText)
                    .font(.subheadline.weight(.semibold))
                Text(viewModel.statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let focused = viewModel.focusedIntersection {
                    Divider()
                    Text(viewModel.intersectionHeading(for: focused))
                        .font(.subheadline.weight(.semibold))
                    Text(viewModel.intersectionDetails(for: focused))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var markerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Markers")
                .font(.headline)

            HStack(spacing: 12) {
                Button {
                    viewModel.saveFocusedAsMarker()
                } label: {
                    Label("Save Marker", systemImage: "mappin.and.ellipse")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    viewModel.calloutNearbyMarkers()
                } label: {
                    Label("Read Markers", systemImage: "list.bullet")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if viewModel.savedMarkers.isEmpty {
                Text("No saved markers.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.savedMarkers.prefix(3)) { marker in
                    HStack {
                        Text(marker.title)
                        Spacer()
                        Button(role: .destructive) {
                            viewModel.deleteMarker(marker)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                    .font(.footnote)
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var guidedRouteCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Guided Routes")
                .font(.headline)

            HStack(spacing: 12) {
                Button {
                    viewModel.saveGuidedRouteFromCurrentIntersections()
                } label: {
                    Label("Save Route", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    viewModel.toggleFirstGuidedRoute()
                } label: {
                    Label(viewModel.activeGuidedRoute == nil ? "Start Route" : "Stop Route", systemImage: "figure.walk")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.guidedRoutes.isEmpty && viewModel.activeGuidedRoute == nil)
            }

            if let active = viewModel.activeGuidedRoute {
                Text("Active: \(active.name)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("No active guided route.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var beaconCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Audio Beacon")
                .font(.headline)

            HStack(spacing: 12) {
                Button {
                    viewModel.armBeaconFromFocusedIntersection()
                } label: {
                    Label("Arm Beacon", systemImage: "dot.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    viewModel.clearBeacon()
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.activeBeacon == nil)
            }

            Text(viewModel.activeBeacon?.title ?? "No active beacon")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var autoCalloutCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Auto Callouts", isOn: Binding(
                get: { viewModel.autoCalloutsEnabled },
                set: { viewModel.setAutoCalloutsEnabled($0) }
            ))

            Text("Auto callouts run in the background cadence and announce nearby roads, places, markers, and beacon cues.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct AlongStreetRoute: Hashable {}

private struct AlongStreetGuideView: View {
    @ObservedObject var viewModel: MapsViewModel
    @EnvironmentObject private var openAIStore: OpenAISubscriptionStore
    @State private var showingCountryPicker = false
    @State private var showingDetail = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                queryCard
                intersectionsCard
                routePlacesCard
            }
            .padding()
        }
        .navigationTitle("Along Street Guide")
        .navigationDestination(isPresented: $showingDetail) {
            IntersectionDetailView(viewModel: viewModel)
                .environmentObject(openAIStore)
        }
    }

    private var queryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Search a road or house number, then EyePal will focus the nearest intersection.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Text("Country")
                Spacer()
                Button {
                    showingCountryPicker = true
                } label: {
                    HStack(spacing: 4) {
                        if viewModel.countryCode.isEmpty {
                            Text("Not set")
                                .foregroundStyle(.secondary)
                        } else {
                            Text(Locale.current.localizedString(forRegionCode: viewModel.countryCode) ?? viewModel.countryCode)
                        }
                        Image(systemName: "chevron.up.chevron.down")
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }

            TextField("Street name or full address", text: $viewModel.query)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.words)
                .submitLabel(.search)
                .onSubmit { viewModel.searchByQuery() }

            HStack(spacing: 12) {
                Button {
                    viewModel.searchByQuery()
                } label: {
                    Label(viewModel.isLoading ? "Searching..." : "Search", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isLoading || viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    viewModel.loadFromCurrentLocation()
                } label: {
                    Label(viewModel.isLocating ? "Locating..." : "Use Location", systemImage: "location")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isLoading || viewModel.isLocating)
            }

            Text(viewModel.statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .sheet(isPresented: $showingCountryPicker) {
            CountryPickerSheet(selectedCode: $viewModel.countryCode)
        }
    }

    private var intersectionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Intersection List")
                .font(.headline)

            if viewModel.intersections.isEmpty {
                Text("Search a road or use current location first.")
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(Array(viewModel.intersections.enumerated()), id: \.element.id) { index, intersection in
                        Button {
                            viewModel.select(index: index)
                            showingDetail = true
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(viewModel.intersectionHeading(for: intersection))
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(viewModel.intersectionDetails(for: intersection))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding()
                            .background(index == viewModel.focusedIndex ? Color.accentColor.opacity(0.14) : Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var routePlacesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Route Places")
                .font(.headline)

            if viewModel.routePlaces.isEmpty {
                Text("No OSM places on the current segment.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.routePlaces) { place in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.routePlaceSummary(place))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct CountryPickerSheet: View {
    @Binding var selectedCode: String
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    private static let allCountries: [(code: String, name: String)] = {
        Locale.isoRegionCodes
            .compactMap { code -> (code: String, name: String)? in
                guard let name = Locale.current.localizedString(forRegionCode: code), !name.isEmpty else { return nil }
                return (code: code, name: name)
            }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }()

    private var filtered: [(code: String, name: String)] {
        if searchText.isEmpty { return Self.allCountries }
        return Self.allCountries.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.code.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Button {
                    selectedCode = ""
                    dismiss()
                } label: {
                    HStack {
                        Text("Not set")
                            .foregroundStyle(.secondary)
                        Spacer()
                        if selectedCode.isEmpty {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)

                ForEach(filtered, id: \.code) { country in
                    Button {
                        selectedCode = country.code
                        dismiss()
                    } label: {
                        HStack {
                            Text(country.name)
                            Spacer()
                            Text(country.code)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if selectedCode == country.code {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .searchable(text: $searchText, prompt: "Search country")
            .navigationTitle("Select Country")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct IntersectionDetailView: View {
    @ObservedObject var viewModel: MapsViewModel
    @EnvironmentObject private var openAIStore: OpenAISubscriptionStore

    private var paidEnabled: Bool { openAIStore.isSignedIn }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let intersection = viewModel.focusedIntersection {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(viewModel.intersectionHeading(for: intersection))
                            .font(.title3.weight(.bold))
                        if let addr = intersection.addressLabel, !addr.isEmpty {
                            Text("Address: \(addr)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Text(viewModel.intersectionDetails(for: intersection))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 16) {
                            Label(intersection.leftRoad ?? "-", systemImage: "arrow.turn.up.left")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Label(intersection.rightRoad ?? "-", systemImage: "arrow.turn.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                } else {
                    Text("No intersection selected.")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("OSM Places")
                        .font(.headline)
                    if viewModel.routePlaces.isEmpty {
                        Text("No OSM places on this segment.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.routePlaces) { place in
                            Text(viewModel.routePlaceSummary(place))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 2)
                        }
                    }
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        Button {
                            viewModel.describeStreetview()
                        } label: {
                            Label(viewModel.isDescribingStreetview ? "Loading..." : "Street View", systemImage: "photo.on.rectangle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!paidEnabled || viewModel.isDescribingStreetview)
                        .opacity(paidEnabled ? 1 : 0.42)

                        Button {
                            viewModel.advance30m()
                        } label: {
                            Label("Advance 30m", systemImage: "arrow.up.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!paidEnabled || viewModel.isDescribingStreetview)
                        .opacity(paidEnabled ? 1 : 0.42)
                    }
                    if !paidEnabled {
                        Text("Sign in to ChatGPT to enable Street View description and Advance 30m.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !viewModel.streetviewDescription.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Street View Description")
                            .font(.headline)
                        Text(viewModel.streetviewDescription)
                            .font(.body)
                    }
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }

                VStack(spacing: 12) {
                    HStack(spacing: 16) {
                        Button {
                            viewModel.moveBackward()
                        } label: {
                            Label("Back", systemImage: "arrow.backward")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            viewModel.moveForward()
                        } label: {
                            Label("Forward", systemImage: "arrow.forward")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    HStack(spacing: 16) {
                        Button {
                            viewModel.turnLeft()
                        } label: {
                            Label("Turn Left", systemImage: "arrow.turn.up.left")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            viewModel.turnRight()
                        } label: {
                            Label("Turn Right", systemImage: "arrow.turn.up.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Text(viewModel.statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Intersection Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}
struct MoreView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var openAIStore: OpenAISubscriptionStore
    @StateObject private var floorStore = FloorRecordStore()

    private enum MoreDestination: Hashable {
        case floorDetection
        case settings
        case streetPreview
        case feature(AppFeature)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink(value: MoreDestination.floorDetection) {
                        Label("Floor Detection", systemImage: "building.2")
                    }

                    NavigationLink(value: MoreDestination.settings) {
                        Label("Settings", systemImage: "gearshape")
                    }
                    
                    NavigationLink(value: MoreDestination.streetPreview) {
                        Label("Street Preview", systemImage: "ear.and.waveform")
                    }
                }

                if !settingsStore.moreFeatures.isEmpty {
                    Section("More Features") {
                        ForEach(settingsStore.moreFeatures) { feature in
                            NavigationLink(value: MoreDestination.feature(feature)) {
                                Label(feature.displayName, systemImage: feature.systemImageName)
                            }
                        }
                    }
                }
            }
                .navigationTitle("More")
                .navigationDestination(for: MoreDestination.self) { destination in
                    switch destination {
                    case .floorDetection:
                        FloorDetectionListView()
                            .environmentObject(floorStore)
                    case .settings:
                        SettingsView()
                            .environmentObject(settingsStore)
                            .environmentObject(openAIStore)
                    case .streetPreview:
                        StreetPreviewView()
                    case .feature(let feature):
                        moreFeatureView(for: feature)
                    }
                }
        }
    }

    @ViewBuilder
    private func moreFeatureView(for feature: AppFeature) -> some View {
        switch feature {
        case .quickRecognition:
            QuickRecognitionView()
        case .detailsRecognition:
            DetailsDescriptionView()
        case .readText:
            ReadTextView()
        case .maps:
            MapsView()
        case .faces:
            FaceRecognitionView()
        }
    }
}

private struct FloorDetectionListView: View {
    @EnvironmentObject private var floorStore: FloorRecordStore
    @State private var selectedRecord: FloorRecord?
    @State private var editingRecord: FloorRecord?

    var body: some View {
        List {
            ForEach(floorStore.records) { record in
                Button {
                    selectedRecord = record
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(record.name), \(record.floorLabel)")
                        Text(String(format: "Altitude %.2f m", record.altitudeMeters))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(record.name), \(record.floorLabel)")
                .accessibilityAction(named: Text("Edit")) {
                    editingRecord = record
                }
                .accessibilityAction(named: Text("Open")) {
                    selectedRecord = record
                }
                .accessibilityAction(named: Text("Delete")) {
                    floorStore.delete(record)
                }
                .swipeActions {
                    Button {
                        editingRecord = record
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        floorStore.delete(record)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .onDelete { offsets in
                floorStore.delete(at: offsets)
            }
        }
        .navigationTitle("Floor Detection")
        .navigationDestination(item: $selectedRecord) { record in
            FloorMonitorView(record: record)
        }
        .sheet(item: $editingRecord) { record in
            FloorRecordNameEditorView(record: record)
                .environmentObject(floorStore)
        }
        .toolbar {
            NavigationLink {
                FloorRecordEditorView()
                    .environmentObject(floorStore)
            } label: {
                Label("Add", systemImage: "plus")
            }
        }
    }
}

private struct FloorRecordNameEditorView: View {
    let record: FloorRecord

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var floorStore: FloorRecordStore
    @State private var name: String
    @FocusState private var isNameFocused: Bool

    init(record: FloorRecord) {
        self.record = record
        _name = State(initialValue: record.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Edit Name") {
                    TextField("Name", text: $name)
                        .focused($isNameFocused)
                        .submitLabel(.done)
                        .onSubmit(save)
                }
            }
            .navigationTitle("Edit Record")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isNameFocused = true
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        floorStore.updateName(for: record, name: trimmedName)
        dismiss()
    }
}

private struct FloorRecordEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var floorStore: FloorRecordStore
    @StateObject private var altitudeMonitor = AltitudeMonitor()
    @State private var name = ""
    @State private var floorLabel = ""
    @State private var addSecondFloor = false
    @State private var secondFloorLabel = ""
    @State private var firstAltitudeSnapshot: Double?
    @FocusState private var focusedField: EditorField?

    private enum EditorField {
        case name
        case floor
    }

    var body: some View {
        Form {
            Section("Add Floor Record") {
                TextField("Name", text: $name)
                    .focused($focusedField, equals: .name)
                    .submitLabel(.next)
                    .onSubmit {
                        focusedField = .floor
                    }

                LabeledContent("Altitude") {
                    Text(altitudeMonitor.altitudeDisplayText)
                }

                TextField("Floor", text: $floorLabel)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .floor)
            }

            if addSecondFloor {
                Section("Add Another Floor") {
                    TextField("Another Floor", text: $secondFloorLabel)
                        .keyboardType(.numberPad)

                    LabeledContent("Latest Altitude") {
                        Text(altitudeMonitor.altitudeDisplayText)
                    }
                }
            }

            Section {
                Button("加入樓層") {
                    firstAltitudeSnapshot = altitudeMonitor.currentAltitudeMeters
                    addSecondFloor = true
                }
                .disabled(
                    addSecondFloor ||
                    name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    floorLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    altitudeMonitor.currentAltitudeMeters == nil
                )

                Button("Finish") {
                    if addSecondFloor {
                        floorStore.addRecords(
                            name: name,
                            firstFloorLabel: floorLabel,
                            firstAltitudeMeters: firstAltitudeSnapshot,
                            secondFloorLabel: secondFloorLabel,
                            secondAltitudeMeters: altitudeMonitor.currentAltitudeMeters
                        )
                    } else {
                        floorStore.addRecord(
                            name: name,
                            floorLabel: floorLabel,
                            altitudeMeters: altitudeMonitor.currentAltitudeMeters
                        )
                    }
                    dismiss()
                }
                .disabled(
                    name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    floorLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    altitudeMonitor.currentAltitudeMeters == nil ||
                    (addSecondFloor && secondFloorLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                )
            }
        }
        .navigationTitle("Floor Detection")
        .onAppear {
            altitudeMonitor.start()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                focusedField = .name
            }
        }
        .onDisappear {
            altitudeMonitor.stop()
        }
    }
}

private struct FloorMonitorView: View {
    let record: FloorRecord
    @StateObject private var altitudeMonitor = AltitudeMonitor()
    private let announcer = AccessibilityAnnouncementCenter()
    @State private var hasAnnouncedArrival = false

    var body: some View {
        Form {
            Section {
                Text("\(record.name), \(record.floorLabel)")
                LabeledContent("Current Altitude") {
                    Text(altitudeMonitor.altitudeDisplayText)
                }
            }
        }
        .navigationTitle(record.name)
        .onAppear {
            altitudeMonitor.start()
        }
        .onDisappear {
            altitudeMonitor.stop()
        }
        .onChange(of: altitudeMonitor.currentAltitudeMeters) { altitude in
            guard let altitude else { return }
            let withinRange = abs(altitude - record.altitudeMeters) <= 0.3
            if withinRange && !hasAnnouncedArrival {
                announcer.announce("Arrived at floor \(record.floorLabel)", minimumInterval: 0)
                hasAnnouncedArrival = true
            } else if !withinRange {
                hasAnnouncedArrival = false
            }
        }
    }
}

private struct MapIntersection: Identifiable {
    let id: String
    let currentRoad: String
    let crossRoad: String
    let intersectionType: String
    let directionToNext: String?
    let distanceToNext: Int
    let addressLabel: String?
    let addressSource: String?
    let lat: Double
    let lon: Double
    let heading: Double
    let leftRoad: String?
    let rightRoad: String?
}

private struct RoutePlace: Identifiable {
    let id: String
    let title: String
    let kindLabel: String
    let addressLabel: String
    let lat: Double
    let lon: Double
    let sortMeters: Int
    let side: RouteSide
}

private enum RouteSide {
    case left
    case right
    case center

    var point: AVAudio3DPoint {
        switch self {
        case .left:
            return AVAudio3DPoint(x: -3, y: 0, z: -1)
        case .right:
            return AVAudio3DPoint(x: 3, y: 0, z: -1)
        case .center:
            return AVAudio3DPoint(x: 0, y: 0, z: -1)
        }
    }

    var frequency: Double {
        switch self {
        case .left:
            return 620
        case .center:
            return 820
        case .right:
            return 980
        }
    }

    var spokenLabel: String {
        switch self {
        case .left:
            return "left"
        case .center:
            return "ahead"
        case .right:
            return "right"
        }
    }
}

private struct FloorRecord: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let name: String
    let floorLabel: String
    let altitudeMeters: Double
}

private struct SavedMarker: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let title: String
    let subtitle: String
    let lat: Double
    let lon: Double
    let createdAt: Date
}

private struct GuidedWaypoint: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let title: String
    let lat: Double
    let lon: Double
}

private struct GuidedRoute: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let name: String
    let description: String
    let waypoints: [GuidedWaypoint]
    let createdAt: Date
}

private struct BeaconTarget: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let title: String
    let lat: Double
    let lon: Double
    let triggerRadiusMeters: Double
}

@MainActor
private final class MarkerStore: ObservableObject {
    @Published private(set) var markers: [SavedMarker] = []
    private let key = "maps.savedMarkers.v1"
    private let defaults = UserDefaults.standard

    init() {
        load()
    }

    func add(title: String, subtitle: String, lat: Double, lon: Double) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        markers.insert(
            SavedMarker(
                id: UUID(),
                title: trimmed,
                subtitle: subtitle,
                lat: lat,
                lon: lon,
                createdAt: Date()
            ),
            at: 0
        )
        save()
    }

    func delete(_ marker: SavedMarker) {
        markers.removeAll { $0.id == marker.id }
        save()
    }

    private func load() {
        guard let data = defaults.data(forKey: key), let decoded = try? JSONDecoder().decode([SavedMarker].self, from: data) else {
            markers = []
            return
        }
        markers = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(markers) {
            defaults.set(data, forKey: key)
        }
    }
}

@MainActor
private final class GuidedRouteStore: ObservableObject {
    @Published private(set) var routes: [GuidedRoute] = []
    private let key = "maps.guidedRoutes.v1"
    private let defaults = UserDefaults.standard

    init() {
        load()
    }

    func add(name: String, description: String, waypoints: [GuidedWaypoint]) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !waypoints.isEmpty else { return }
        routes.insert(
            GuidedRoute(
                id: UUID(),
                name: trimmed,
                description: description,
                waypoints: waypoints,
                createdAt: Date()
            ),
            at: 0
        )
        save()
    }

    private func load() {
        guard let data = defaults.data(forKey: key), let decoded = try? JSONDecoder().decode([GuidedRoute].self, from: data) else {
            routes = []
            return
        }
        routes = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(routes) {
            defaults.set(data, forKey: key)
        }
    }
}

@MainActor
private final class FloorRecordStore: ObservableObject {
    @Published private(set) var records: [FloorRecord] = []
    private let defaults = UserDefaults.standard
    private let key = "floorDetection.records.v1"

    init() {
        load()
    }

    func addRecord(name: String, floorLabel: String, altitudeMeters: Double?) {
        guard let altitudeMeters else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFloor = floorLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedFloor.isEmpty else { return }
        records.append(
            FloorRecord(
                id: UUID(),
                name: trimmedName,
                floorLabel: trimmedFloor,
                altitudeMeters: altitudeMeters
            )
        )
        save()
    }

    func addRecords(
        name: String,
        firstFloorLabel: String,
        firstAltitudeMeters: Double?,
        secondFloorLabel: String,
        secondAltitudeMeters: Double?,
    ) {
        addRecord(name: name, floorLabel: firstFloorLabel, altitudeMeters: firstAltitudeMeters)
        addRecord(name: name, floorLabel: secondFloorLabel, altitudeMeters: secondAltitudeMeters)
    }

    func delete(_ record: FloorRecord) {
        records.removeAll { $0.id == record.id }
        save()
    }

    func updateName(for record: FloorRecord, name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, let index = records.firstIndex(where: { $0.id == record.id }) else { return }

        records[index] = FloorRecord(
            id: record.id,
            name: trimmedName,
            floorLabel: record.floorLabel,
            altitudeMeters: record.altitudeMeters
        )
        save()
    }

    func delete(at offsets: IndexSet) {
        records.remove(atOffsets: offsets)
        save()
    }

    private func load() {
        guard let data = defaults.data(forKey: key), let decoded = try? JSONDecoder().decode([FloorRecord].self, from: data) else {
            records = []
            return
        }
        records = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: key)
        }
    }
}

@MainActor
private final class MapsViewModel: ObservableObject, UserHeadingProviderDelegate {
    static let supportedCountryCodes = ["HK", "TW", "JP", "US"]

    @Published var query = ""
    @Published var countryCode = "HK"
    @Published var statusText = "Search a road or use current location."
    @Published var intersections: [MapIntersection] = []
    @Published var focusedIndex = 0
    @Published var routePlaces: [RoutePlace] = []
    @Published var isLoading = false
    @Published var isLocating = false
    @Published var errorMessage: String?
    @Published var streetviewDescription = ""
    @Published var isDescribingStreetview = false
    @Published var savedMarkers: [SavedMarker] = []
    @Published var guidedRoutes: [GuidedRoute] = []
    @Published var activeGuidedRoute: GuidedRoute?
    @Published var activeBeacon: BeaconTarget?
    @Published var autoCalloutsEnabled = true

    var currentRoadText: String {
        focusedIntersection?.currentRoad ?? intersections.first?.currentRoad ?? "Not loaded"
    }

    var focusedIntersection: MapIntersection? {
        intersections.indices.contains(focusedIndex) ? intersections[focusedIndex] : nil
    }

    private let apiClient = AlaViaAPIClient()
    private let announcementCenter = AccessibilityAnnouncementCenter()
    private let locationProvider = CurrentLocationProvider()
    private let spatialAudio = SpatialAudioCuePlayer()
    private let markerStore = MarkerStore()
    private let guidedRouteStore = GuidedRouteStore()
    private var settingsStore: SettingsStore?
    private var autoCalloutTask: Task<Void, Never>?
    private var headingProvider: UserHeadingProvider?
    private var currentHeading: Double = 0
    private var cancellables: Set<AnyCancellable> = []
    private var beaconReachAnnounced = false
    private var speechCooldown: TimeInterval = 2.5

    func bind(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        speechCooldown = settingsStore.speechCooldown
        autoCalloutsEnabled = settingsStore.mapsAutoCalloutsEnabled

        HRTFAudioEngine.shared.applyMapsAudioSettings(
            maxDistanceMeters: settingsStore.mapsMaxDistanceMeters,
            reverbBlend: settingsStore.mapsReverbBlend
        )

        markerStore.$markers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.savedMarkers = $0 }
            .store(in: &cancellables)

        guidedRouteStore.$routes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.guidedRoutes = $0 }
            .store(in: &cancellables)

        savedMarkers = markerStore.markers
        guidedRoutes = guidedRouteStore.routes

        startHeadingTracking(enabled: settingsStore.mapsHeadTrackingEnabled)
        restartAutoCalloutsIfNeeded()
    }

    func unbind() {
        autoCalloutTask?.cancel()
        autoCalloutTask = nil
        stopHeadingTracking()
        cancellables.removeAll()
    }

    func setAutoCalloutsEnabled(_ enabled: Bool) {
        autoCalloutsEnabled = enabled
        settingsStore?.mapsAutoCalloutsEnabled = enabled
        restartAutoCalloutsIfNeeded()
    }

    func userHeadingProvider(_ provider: UserHeadingProvider, didUpdateUserHeading heading: HeadingValue?) {
        guard let heading else { return }
        currentHeading = heading.value
        HRTFAudioEngine.shared.updateListenerHeading(currentHeading)
    }

    func searchByQuery() {
        let rawQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawQuery.isEmpty else { return }

        Task {
            await runSearch(query: rawQuery)
        }
    }

    func loadFromCurrentLocation() {
        Task {
            isLocating = true
            statusText = "Getting current location..."
            do {
                let location = try await locationProvider.requestCurrentLocation()
                try? await apiClient.scanNearbyTiles(lat: location.coordinate.latitude, lon: location.coordinate.longitude)
                let reverse = try await apiClient.reverseRoad(lat: location.coordinate.latitude, lon: location.coordinate.longitude)
                query = reverse.displayName
                try await loadRoad(
                    using: reverse.roadName,
                    focusCoordinate: location.coordinate,
                    preferredBearing: location.course >= 0 ? location.course : nil,
                    statusPrefix: "GPS located: \(reverse.displayName)"
                )
            } catch {
                errorMessage = error.localizedDescription
                statusText = "GPS failed: \(error.localizedDescription)"
            }
            isLocating = false
        }
    }

    func select(index: Int) {
        guard intersections.indices.contains(index) else { return }
        focusedIndex = index
        Task {
            await refreshRoutePlacesAndAnnounce()
        }
    }

    func moveForward() {
        if focusedIndex < intersections.count - 1 {
            select(index: focusedIndex + 1)
            return
        }
        if let nextRoad = focusedIntersection?.rightRoad ?? focusedIntersection?.leftRoad {
            Task {
                try? await loadRoad(using: nextRoad, focusCoordinate: nil, preferredBearing: nil, statusPrefix: "Moved to connected street")
            }
        }
    }

    func moveBackward() {
        guard focusedIndex > 0 else { return }
        select(index: focusedIndex - 1)
    }

    func turnLeft() {
        guard let nextRoad = focusedIntersection?.leftRoad else { return }
        Task {
            try? await loadRoad(using: nextRoad, focusCoordinate: nil, preferredBearing: nil, statusPrefix: "Turned left")
        }
    }

    func turnRight() {
        guard let nextRoad = focusedIntersection?.rightRoad else { return }
        Task {
            try? await loadRoad(using: nextRoad, focusCoordinate: nil, preferredBearing: nil, statusPrefix: "Turned right")
        }
    }

    func describeStreetview() {
        guard let row = focusedIntersection else {
            statusText = "No intersection selected for street view."
            return
        }
        Task {
            isDescribingStreetview = true
            statusText = "Getting street view description..."
            do {
                let description = try await apiClient.describeStreetview(lat: row.lat, lon: row.lon, heading: row.heading)
                streetviewDescription = description
                statusText = "Street view description updated."
                announce(text: description)
            } catch {
                statusText = "Street view failed: \(error.localizedDescription)"
            }
            isDescribingStreetview = false
        }
    }

    func advance30m() {
        guard let row = focusedIntersection else { return }
        let shifted = destinationPoint(lat: row.lat, lon: row.lon, bearing: row.heading, distanceMeters: 30.0)
        Task {
            isDescribingStreetview = true
            statusText = "Getting advance 30m description..."
            do {
                let description = try await apiClient.describeStreetview(lat: shifted.lat, lon: shifted.lon, heading: row.heading)
                streetviewDescription = description
                statusText = "Advance 30m description updated."
                announce(text: description)
            } catch {
                statusText = "Advance 30m failed: \(error.localizedDescription)"
            }
            isDescribingStreetview = false
        }
    }
    func calloutMyLocation() {
        loadFromCurrentLocation()
    }

    func calloutAroundMe() {
        guard let current = focusedIntersection else {
            announce(text: "Around Me unavailable. Search a road first.")
            return
        }
        announce(text: "\(intersectionHeading(for: current)). \(intersectionDetails(for: current)).")
    }

    func playAroundMeSpatialAudio() {
        guard let current = focusedIntersection else {
            announce(text: "Around Me unavailable. Search a road first.")
            return
        }
        
        HRTFAudioEngine.shared.updateListenerHeading(currentHeading)

        // Play spatial audio cues for directions around current location
        HRTFAudioEngine.shared.playDirectionalCue(direction: .ahead)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            HRTFAudioEngine.shared.playDirectionalCue(direction: .left, frequency: 620)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            HRTFAudioEngine.shared.playDirectionalCue(direction: .right, frequency: 980)
        }
        
        announce(text: "\(intersectionHeading(for: current)). \(intersectionDetails(for: current)).")
    }

    func calloutAheadOfMe() {
        guard intersections.indices.contains(focusedIndex) else {
            announce(text: "Ahead of Me unavailable. Search a road first.")
            return
        }
        let nextIndex = focusedIndex + 1
        guard intersections.indices.contains(nextIndex) else {
            announce(text: "Ahead of Me: last intersection.")
            return
        }
        let next = intersections[nextIndex]
        announce(text: "Ahead of Me: \(intersectionHeading(for: next)).")
    }

    func playAheadOfMeSpatialAudio() {
        guard intersections.indices.contains(focusedIndex) else {
            announce(text: "Ahead of Me unavailable. Search a road first.")
            return
        }
        let nextIndex = focusedIndex + 1
        guard intersections.indices.contains(nextIndex) else {
            announce(text: "Ahead of Me: last intersection.")
            return
        }
        
        let next = intersections[nextIndex]
        
        HRTFAudioEngine.shared.updateListenerHeading(currentHeading)

        // Play spatial audio cue directly ahead
        HRTFAudioEngine.shared.playDirectionalCue(direction: .ahead, frequency: 820)
        
        announce(text: "Ahead of Me: \(intersectionHeading(for: next)).")
    }

    func calloutNearbyMarkers() {
        let saved = nearbySavedMarkersSummary(maxCount: 4)
        let routeBased = routePlaces.prefix(max(0, 4 - saved.count)).map(routePlaceSummary)
        let merged = (saved + routeBased).joined(separator: ". ")
        guard !merged.isEmpty else {
            announce(text: "Nearby Markers unavailable.")
            return
        }
        announce(text: "Nearby Markers. \(merged)")
    }

    func calloutAlongStreetGuide() {
        guard let current = focusedIntersection else {
            announce(text: "Along Street Guide unavailable. Search a road first.")
            return
        }
        announce(text: "Along Street Guide. \(intersectionHeading(for: current)).")
    }

    func intersectionHeading(for intersection: MapIntersection) -> String {
        let primary = intersection.addressLabel?.isEmpty == false ? (intersection.addressLabel ?? intersection.currentRoad) : intersection.currentRoad
        return "\(primary) - \(intersection.crossRoad)"
    }

    func intersectionDetails(for intersection: MapIntersection) -> String {
        let nextDirection = intersection.directionToNext ?? directionFromBearing(intersection.heading)
        let nextDistance = intersection.distanceToNext > 0 ? "\(intersection.distanceToNext) m" : "last intersection"
        return "\(intersection.intersectionType), next direction: \(nextDirection), next distance: \(nextDistance)"
    }

    func routePlaceSummary(_ place: RoutePlace) -> String {
        var parts = ["\(place.sortMeters)m: \(place.title)"]
        if !place.kindLabel.isEmpty && place.kindLabel != place.title {
            parts.append(place.kindLabel)
        }
        if !place.addressLabel.isEmpty && place.addressLabel != place.title {
            parts.append(place.addressLabel)
        }
        parts.append(place.side.spokenLabel)
        return parts.joined(separator: ", ")
    }

    func saveFocusedAsMarker() {
        guard let current = focusedIntersection else {
            announce(text: "Cannot save marker. Search a road first.")
            return
        }

        let title = current.addressLabel?.isEmpty == false ? (current.addressLabel ?? current.currentRoad) : current.currentRoad
        markerStore.add(
            title: title,
            subtitle: current.crossRoad,
            lat: current.lat,
            lon: current.lon
        )
        HRTFAudioEngine.shared.playSFX(.markerCreated)
        announce(text: "Marker saved: \(title)")
    }

    func deleteMarker(_ marker: SavedMarker) {
        markerStore.delete(marker)
        announce(text: "Marker deleted: \(marker.title)")
    }

    func saveGuidedRouteFromCurrentIntersections() {
        guard intersections.count >= 2 else {
            announce(text: "Cannot save guided route. Load at least two intersections.")
            return
        }

        let waypoints = intersections.prefix(8).map {
            GuidedWaypoint(
                id: UUID(),
                title: "\($0.currentRoad) - \($0.crossRoad)",
                lat: $0.lat,
                lon: $0.lon
            )
        }
        let routeName = intersections.first?.currentRoad ?? "Guided Route"
        guidedRouteStore.add(
            name: routeName,
            description: "Saved from current road exploration",
            waypoints: Array(waypoints)
        )
        HRTFAudioEngine.shared.playSFX(.guidedRouteStarted)
        announce(text: "Guided route saved: \(routeName)")
    }

    func toggleFirstGuidedRoute() {
        if activeGuidedRoute != nil {
            let name = activeGuidedRoute?.name ?? "route"
            activeGuidedRoute = nil
            announce(text: "Stopped guided route: \(name)")
            return
        }

        guard let first = guidedRoutes.first else {
            announce(text: "No guided routes available.")
            return
        }
        activeGuidedRoute = first
        HRTFAudioEngine.shared.playSFX(.guidedRouteStarted)
        announce(text: "Started guided route: \(first.name)")
    }

    func armBeaconFromFocusedIntersection() {
        guard let current = focusedIntersection else {
            announce(text: "Cannot arm beacon. Search a road first.")
            return
        }

        activeBeacon = BeaconTarget(
            id: UUID(),
            title: "\(current.currentRoad) - \(current.crossRoad)",
            lat: current.lat,
            lon: current.lon,
            triggerRadiusMeters: 30
        )
        beaconReachAnnounced = false
        HRTFAudioEngine.shared.playSFX(.beaconArmed)
        announce(text: "Beacon armed at \(activeBeacon?.title ?? "target").")
    }

    func clearBeacon() {
        activeBeacon = nil
        beaconReachAnnounced = false
        announce(text: "Beacon cleared")
    }

    private func startHeadingTracking(enabled: Bool) {
        stopHeadingTracking()
        guard enabled else { return }

        if #available(iOS 14.4, *), HeadphoneMotionProvider().isHeadphoneMotionAvailable {
            let provider = HeadphoneMotionProvider()
            provider.delegate = self
            provider.startUserHeadingUpdates()
            headingProvider = provider
        } else {
            let provider = DeviceMotionProvider()
            provider.delegate = self
            provider.startUserHeadingUpdates()
            headingProvider = provider
        }
    }

    private func stopHeadingTracking() {
        headingProvider?.stopUserHeadingUpdates()
        headingProvider = nil
    }

    private func restartAutoCalloutsIfNeeded() {
        autoCalloutTask?.cancel()
        autoCalloutTask = nil

        guard autoCalloutsEnabled else { return }
        let interval = max(8.0, settingsStore?.mapsAutoCalloutIntervalSeconds ?? 20.0)
        autoCalloutTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self.calloutAroundMe()
                self.calloutNearbyMarkers()
                self.checkBeaconProximity()
            }
        }
    }

    private func checkBeaconProximity() {
        guard let beacon = activeBeacon, let current = focusedIntersection else { return }
        let currentLocation = CLLocation(latitude: current.lat, longitude: current.lon)
        let beaconLocation = CLLocation(latitude: beacon.lat, longitude: beacon.lon)
        let distance = currentLocation.distance(from: beaconLocation)

        if distance <= beacon.triggerRadiusMeters {
            if !beaconReachAnnounced {
                beaconReachAnnounced = true
                HRTFAudioEngine.shared.playSFX(.beaconNearby)
                announce(text: "Beacon nearby. \(Int(distance)) meters to \(beacon.title).")
            }
        } else {
            beaconReachAnnounced = false
        }
    }

    private func nearbySavedMarkersSummary(maxCount: Int = 4) -> [String] {
        guard let current = focusedIntersection else { return [] }
        let currentLocation = CLLocation(latitude: current.lat, longitude: current.lon)
        return savedMarkers
            .map { marker -> (SavedMarker, Int) in
                let markerLocation = CLLocation(latitude: marker.lat, longitude: marker.lon)
                let distance = Int(currentLocation.distance(from: markerLocation).rounded())
                return (marker, distance)
            }
            .sorted { $0.1 < $1.1 }
            .prefix(maxCount)
            .map { "\($0.1)m: \($0.0.title), \($0.0.subtitle)" }
    }

    private func runSearch(query rawQuery: String) async {
        isLoading = true
        statusText = "Searching..."
        do {
            let geo = try await apiClient.autobbox(query: rawQuery, countryCode: countryCode)
            query = geo.displayName
            try await loadRoad(
                using: geo.roadName,
                focusCoordinate: geo.coordinate,
                preferredBearing: nil,
                statusPrefix: "Auto-located: \(geo.displayName)"
            )
        } catch {
            errorMessage = error.localizedDescription
            statusText = "Search failed: \(error.localizedDescription)"
            isLoading = false
        }
    }

    private func loadRoad(
        using roadName: String,
        focusCoordinate: CLLocationCoordinate2D?,
        preferredBearing: CLLocationDirection?,
        statusPrefix: String
    ) async throws {
        if let focusCoordinate {
            try? await apiClient.scanNearbyTiles(lat: focusCoordinate.latitude, lon: focusCoordinate.longitude)
        }
        let response = try await apiClient.fetchIntersections(roadName: roadName, countryCode: countryCode)
        intersections = response.intersections
        focusedIndex = findFocusedIntersectionIndex(intersections: response.intersections, focusCoordinate: focusCoordinate, preferredBearing: preferredBearing)
        routePlaces = []
        statusText = "\(statusPrefix). Loaded \(response.intersections.count) intersections on \(response.roadName)."
        isLoading = false
        await refreshRoutePlacesAndAnnounce()
    }

    private func refreshRoutePlacesAndAnnounce() async {
        guard intersections.indices.contains(focusedIndex) else {
            routePlaces = []
            return
        }

        let current = intersections[focusedIndex]
        let next = intersections.indices.contains(focusedIndex + 1) ? intersections[focusedIndex + 1] : nil
        guard let next else {
            routePlaces = []
            announce(text: intersectionHeading(for: current))
            return
        }

        do {
            let previous = focusedIndex > 0 ? intersections[focusedIndex - 1] : nil
            let places = try await apiClient.fetchRoutePlaces(start: current, end: next, roadName: current.currentRoad)
            routePlaces = places.map { place in
                RoutePlace(
                    id: place.id,
                    title: place.title,
                    kindLabel: place.kindLabel,
                    addressLabel: place.addressLabel,
                    lat: place.lat,
                    lon: place.lon,
                    sortMeters: place.sortMeters,
                    side: resolveRouteSide(previous: previous, current: current, next: next, place: place)
                )
            }
            await playSpatialSummary(for: routePlaces)
            let spokenPlaces = routePlaces.prefix(4).map(routePlaceSummary).joined(separator: ". ")
            let message = spokenPlaces.isEmpty
                ? intersectionHeading(for: current)
                : "\(intersectionHeading(for: current)). \(spokenPlaces)."
            announce(text: message)
            announceGuidedRouteProgressIfNeeded(current: current)
            checkBeaconProximity()
        } catch {
            routePlaces = []
            announce(text: intersectionHeading(for: current))
            announceGuidedRouteProgressIfNeeded(current: current)
            checkBeaconProximity()
        }
    }

    private func announce(text: String) {
        announcementCenter.announce(text, minimumInterval: speechCooldown)
    }

    private func playSpatialSummary(for places: [RoutePlace]) async {
        for place in places.prefix(3) {
            spatialAudio.play(side: place.side)
            try? await Task.sleep(nanoseconds: 180_000_000)
        }
    }

    private func announceGuidedRouteProgressIfNeeded(current: MapIntersection) {
        guard let route = activeGuidedRoute else { return }
        let currentLocation = CLLocation(latitude: current.lat, longitude: current.lon)
        let nearest = route.waypoints
            .map { waypoint -> (GuidedWaypoint, Double) in
                let target = CLLocation(latitude: waypoint.lat, longitude: waypoint.lon)
                return (waypoint, currentLocation.distance(from: target))
            }
            .min { $0.1 < $1.1 }

        guard let nearest else { return }
        if nearest.1 <= 30 {
            HRTFAudioEngine.shared.playSFX(.markerReached)
            announce(text: "Guided route point reached: \(nearest.0.title)")
        }
    }

    private func findFocusedIntersectionIndex(
        intersections: [MapIntersection],
        focusCoordinate: CLLocationCoordinate2D?,
        preferredBearing: CLLocationDirection?
    ) -> Int {
        guard let focusCoordinate, !intersections.isEmpty else { return 0 }
        let useBearing = preferredBearing.map { $0.isFinite } ?? false

        var bestIndex = 0
        var bestScore = Double.greatestFiniteMagnitude

        for (index, intersection) in intersections.enumerated() {
            let location = CLLocation(latitude: intersection.lat, longitude: intersection.lon)
            let distanceScore = CLLocation(latitude: focusCoordinate.latitude, longitude: focusCoordinate.longitude).distance(from: location)
            let bearingScore = useBearing ? angleDistance(intersection.heading, preferredBearing ?? 0) : 0
            let score = distanceScore * 4 + bearingScore
            if score < bestScore {
                bestScore = score
                bestIndex = index
            }
        }

        return bestIndex
    }

    private func resolveRouteSide(previous: MapIntersection?, current: MapIntersection, next: MapIntersection, place: AlaViaAPIClient.RoutePlacePayload) -> RouteSide {
        let routeVector = smoothedRouteVector(previous: previous, current: current, next: next)
        let dx = routeVector.dx
        let dy = routeVector.dy
        let pointDx = place.lon - current.lon
        let pointDy = place.lat - current.lat
        let cross = dx * pointDy - dy * pointDx
        if abs(cross) < 1e-9 {
            return .center
        }
        return cross > 0 ? .left : .right
    }

    private func smoothedRouteVector(previous: MapIntersection?, current: MapIntersection, next: MapIntersection) -> (dx: Double, dy: Double) {
        let prevDx = previous.map { current.lon - $0.lon } ?? 0
        let prevDy = previous.map { current.lat - $0.lat } ?? 0
        let nextDx = next.lon - current.lon
        let nextDy = next.lat - current.lat
        let dx = previous == nil ? nextDx : (prevDx + nextDx)
        let dy = previous == nil ? nextDy : (prevDy + nextDy)
        return (dx, dy)
    }

    private func destinationPoint(lat: Double, lon: Double, bearing: Double, distanceMeters: Double) -> (lat: Double, lon: Double) {
        let R = 6_371_000.0
        let bearingRad = bearing * .pi / 180
        let latRad = lat * .pi / 180
        let lonRad = lon * .pi / 180
        let angDist = distanceMeters / R
        let newLatRad = asin(sin(latRad) * cos(angDist) + cos(latRad) * sin(angDist) * cos(bearingRad))
        let newLonRad = lonRad + atan2(sin(bearingRad) * sin(angDist) * cos(latRad), cos(angDist) - sin(latRad) * sin(newLatRad))
        return (lat: newLatRad * 180 / .pi, lon: newLonRad * 180 / .pi)
    }
    private func angleDistance(_ a: Double, _ b: Double) -> Double {
        abs((((a - b).truncatingRemainder(dividingBy: 360)) + 540).truncatingRemainder(dividingBy: 360) - 180)
    }

    private func directionFromBearing(_ bearing: Double) -> String {
        let directions = ["North", "Northeast", "East", "Southeast", "South", "Southwest", "West", "Northwest"]
        let normalized = (bearing.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let index = Int((normalized / 45).rounded()) % directions.count
        return directions[index]
    }
}

private struct AlaViaGeocodeResult {
    let displayName: String
    let roadName: String
    let coordinate: CLLocationCoordinate2D?
}

private struct ReverseRoadResult {
    let displayName: String
    let roadName: String
}

private struct IntersectionResponse {
    let roadName: String
    let intersections: [MapIntersection]
}

private struct CurrentLocationProviderError: LocalizedError {
    let errorDescription: String?
}

private final class CurrentLocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestCurrentLocation() async throws -> CLLocation {
        if let continuation {
            continuation.resume(throwing: CurrentLocationProviderError(errorDescription: "Location request replaced by a new one."))
            self.continuation = nil
        }

        let status = manager.authorizationStatus
        if status == .denied || status == .restricted {
            throw CurrentLocationProviderError(errorDescription: "Location permission is unavailable.")
        }

        if status == .notDetermined {
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                self.manager.requestWhenInUseAuthorization()
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            continuation?.resume(throwing: CurrentLocationProviderError(errorDescription: "Location permission was denied."))
            continuation = nil
            return
        }

        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        continuation?.resume(returning: location)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

@MainActor
private final class AltitudeMonitor: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var currentAltitudeMeters: Double?
    @Published private(set) var altitudeDisplayText = "Unavailable"

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
    }

    func start() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let altitude = locations.last?.altitude, altitude.isFinite else { return }
        Task { @MainActor in
            currentAltitudeMeters = altitude
            altitudeDisplayText = String(format: "%.2f m", altitude)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            altitudeDisplayText = error.localizedDescription
        }
    }
}

private final class SpatialAudioCuePlayer {
    func play(side: RouteSide) {
        switch side {
        case .left:
            HRTFAudioEngine.shared.playDirectionalCue(direction: .left)
        case .right:
            HRTFAudioEngine.shared.playDirectionalCue(direction: .right)
        case .center:
            HRTFAudioEngine.shared.playDirectionalCue(direction: .center)
        }
    }
}

private final class AlaViaAPIClient {
    struct RoutePlacePayload {
        let id: String
        let title: String
        let kindLabel: String
        let addressLabel: String
        let lat: Double
        let lon: Double
        let sortMeters: Int
    }

    func autobbox(query: String, countryCode: String) async throws -> AlaViaGeocodeResult {
        var autobboxBody: [String: Any] = ["query": query]
        if !countryCode.isEmpty { autobboxBody["countryCode"] = countryCode }
        let json = try await post(path: "/api/geocode/autobbox", body: autobboxBody)
        let lat = json["lat"] as? Double
        let lon = json["lon"] as? Double
        return AlaViaGeocodeResult(
            displayName: json["displayName"] as? String ?? query,
            roadName: (json["roadName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? (json["roadName"] as? String ?? query) : query,
            coordinate: (lat != nil && lon != nil) ? CLLocationCoordinate2D(latitude: lat!, longitude: lon!) : nil
        )
    }

    func reverseRoad(lat: Double, lon: Double) async throws -> ReverseRoadResult {
        let json = try await post(path: "/api/geocode/reverse-road", body: [
            "lat": lat,
            "lon": lon,
        ])
        return ReverseRoadResult(
            displayName: json["displayName"] as? String ?? (json["roadName"] as? String ?? "Current location"),
            roadName: json["roadName"] as? String ?? ""
        )
    }

    func fetchIntersections(roadName: String, countryCode: String) async throws -> IntersectionResponse {
        var segmentBody: [String: Any] = ["roadName": roadName]
        if !countryCode.isEmpty { segmentBody["countryCode"] = countryCode }
        let json = try await post(path: "/api/overpass/segment", body: segmentBody)
        let rows = json["intersections"] as? [[String: Any]] ?? []
        return IntersectionResponse(
            roadName: json["roadName"] as? String ?? roadName,
            intersections: rows.enumerated().map { index, row in
                MapIntersection(
                    id: String(row["id"] as? Int ?? index),
                    currentRoad: row["streetName"] as? String ?? roadName,
                    crossRoad: firstCrossStreet(row) ?? (row["name"] as? String ?? "Unknown"),
                    intersectionType: row["type"] as? String ?? "Unknown",
                    directionToNext: row["directionToNext"] as? String,
                    distanceToNext: row["distanceToNext"] as? Int ?? 0,
                    addressLabel: row["addressLabel"] as? String,
                    addressSource: row["addressSource"] as? String,
                    lat: row["lat"] as? Double ?? 0,
                    lon: row["lon"] as? Double ?? 0,
                    heading: row["bearingToNext"] as? Double ?? row["heading"] as? Double ?? 0,
                    leftRoad: ((row["leftTurn"] as? [String: Any])?["roadName"] as? String) ?? row["leftRoad"] as? String,
                    rightRoad: ((row["rightTurn"] as? [String: Any])?["roadName"] as? String) ?? row["rightRoad"] as? String
                )
            }
        )
    }

    func fetchRoutePlaces(start: MapIntersection, end: MapIntersection, roadName: String) async throws -> [RoutePlacePayload] {
        let json = try await post(path: "/api/osm/route-places", body: [
            "roadName": roadName,
            "start": ["lat": start.lat, "lon": start.lon],
            "end": ["lat": end.lat, "lon": end.lon],
        ])
        let rows = json["places"] as? [[String: Any]] ?? []
        return rows.enumerated().map { index, row in
            RoutePlacePayload(
                id: row["id"] as? String ?? "place-\(index)",
                title: row["title"] as? String ?? row["name"] as? String ?? "Unnamed place",
                kindLabel: row["kindLabel"] as? String ?? row["type"] as? String ?? "",
                addressLabel: row["addressLabel"] as? String ?? "",
                lat: row["lat"] as? Double ?? 0,
                lon: row["lon"] as? Double ?? 0,
                sortMeters: row["sortMeters"] as? Int ?? row["distanceMeters"] as? Int ?? 0
            )
        }
    }

    func scanNearbyTiles(lat: Double, lon: Double) async throws {
        _ = try await post(path: "/api/osm/scan-nearby", body: [
            "lat": lat,
            "lon": lon,
            "radiusMeters": 1000,
            "zoom": 16,
        ])
    }

    func describeStreetview(lat: Double, lon: Double, heading: Double) async throws -> String {
        let json = try await post(path: "/api/overpass/streetview", body: [
            "lat": lat,
            "lon": lon,
            "heading": heading,
        ])
        return json["description"] as? String ?? json["text"] as? String ?? "No description available."
    }
    private func post(path: String, body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: alaViaBaseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CurrentLocationProviderError(errorDescription: "Invalid network response.")
        }
        let jsonObject = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        if !(200...299).contains(httpResponse.statusCode) {
            throw CurrentLocationProviderError(errorDescription: jsonObject["error"] as? String ?? "Request failed with status \(httpResponse.statusCode).")
        }
        return jsonObject
    }

    private func firstCrossStreet(_ row: [String: Any]) -> String? {
        if let crossStreets = row["crossStreets"] as? [String], let first = crossStreets.first, !first.isEmpty {
            return first
        }
        if let name = row["name"] as? String, name.contains("×") {
            return name.split(separator: "×").dropFirst().first.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        return nil
    }
}