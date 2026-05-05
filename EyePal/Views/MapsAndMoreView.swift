import SwiftUI
import CoreLocation
import AVFoundation

private let alaViaBaseURL = URL(string: "https://via.inclu.si")!

struct MapsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @StateObject private var viewModel = MapsViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    soundscapeHomeCard
                    queryCard
                    focusedIntersectionCard
                    routePlacesCard
                    intersectionsCard
                }
                .padding()
            }
            .navigationTitle("Maps")
        }
        .onAppear {
            viewModel.bind(settingsStore: settingsStore)
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

                Button("Around Me") {
                    viewModel.calloutAroundMe()
                }
                .buttonStyle(.bordered)

                Button("Ahead of Me") {
                    viewModel.calloutAheadOfMe()
                }
                .buttonStyle(.bordered)

                Button("Nearby Markers") {
                    viewModel.calloutNearbyMarkers()
                }
                .buttonStyle(.bordered)

                Button("Along Street Guide") {
                    viewModel.calloutAlongStreetGuide()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.focusedIntersection == nil)
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

    private var queryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Search a road or house number, then EyePal will focus the nearest exit or intersection.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Country", selection: $viewModel.countryCode) {
                ForEach(MapsViewModel.supportedCountryCodes, id: \.self) { code in
                    Text(code).tag(code)
                }
            }
            .pickerStyle(.segmented)

            TextField("Street name or full address", text: $viewModel.query)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.words)
                .submitLabel(.search)
                .onSubmit {
                    viewModel.searchByQuery()
                }

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
                    Label(viewModel.isLocating ? "Locating..." : "Use Current Location", systemImage: "location")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isLoading || viewModel.isLocating)
            }

            Text(viewModel.statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityLabel(viewModel.statusText)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var focusedIntersectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Focused Intersection")
                .font(.headline)

            if let focused = viewModel.focusedIntersection {
                Text(viewModel.intersectionHeading(for: focused))
                    .font(.title3.weight(.semibold))
                if let addressLabel = focused.addressLabel, !addressLabel.isEmpty {
                    Text(addressLabel)
                        .font(.subheadline)
                }
                Text(viewModel.intersectionDetails(for: focused))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button("Back") {
                        viewModel.moveBackward()
                    }
                    .buttonStyle(.bordered)

                    Button("Forward") {
                        viewModel.moveForward()
                    }
                    .buttonStyle(.borderedProminent)
                }

                HStack(spacing: 12) {
                    Button("Turn Left") {
                        viewModel.turnLeft()
                    }
                    .buttonStyle(.bordered)

                    Button("Turn Right") {
                        viewModel.turnRight()
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Text("No focused intersection yet.")
                    .foregroundStyle(.secondary)
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
}

struct MoreView: View {
    @StateObject private var floorStore = FloorRecordStore()

    var body: some View {
        NavigationStack {
            FloorDetectionListView()
                .environmentObject(floorStore)
                .navigationTitle("More")
        }
    }
}

private struct FloorDetectionListView: View {
    @EnvironmentObject private var floorStore: FloorRecordStore
    @State private var selectedRecord: FloorRecord?

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
                .accessibilityAction(named: Text("Default")) {
                    selectedRecord = record
                }
                .accessibilityAction(named: Text("Delete")) {
                    floorStore.delete(record)
                }
                .swipeActions {
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
private final class MapsViewModel: ObservableObject {
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
    private var speechCooldown: TimeInterval = 2.5

    func bind(settingsStore: SettingsStore) {
        speechCooldown = settingsStore.speechCooldown
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

    func calloutNearbyMarkers() {
        guard !routePlaces.isEmpty else {
            announce(text: "Nearby Markers unavailable on this segment.")
            return
        }
        let spokenPlaces = routePlaces.prefix(4).map(routePlaceSummary).joined(separator: ". ")
        announce(text: "Nearby Markers. \(spokenPlaces)")
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
        } catch {
            routePlaces = []
            announce(text: intersectionHeading(for: current))
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
    private let engine = AVAudioEngine()
    private let environment = AVAudioEnvironmentNode()

    init() {
        engine.attach(environment)
        engine.connect(environment, to: engine.mainMixerNode, format: nil)
        environment.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
        environment.reverbBlend = 0.15
        environment.distanceAttenuationParameters.referenceDistance = 1
        configureAudioSession()
        startEngineIfNeeded()
    }

    func play(side: RouteSide) {
        startEngineIfNeeded()
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
        guard let format, let buffer = makeToneBuffer(frequency: side.frequency, format: format) else { return }
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: environment, format: format)
        player.position = side.point
        player.scheduleBuffer(buffer, at: nil, options: .interrupts) { [weak self, weak player] in
            guard let self, let player else { return }
            self.engine.detach(player)
        }
        player.play()
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    private func startEngineIfNeeded() {
        if !engine.isRunning {
            try? engine.start()
        }
    }

    private func makeToneBuffer(frequency: Double, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(format.sampleRate * 0.16)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        let channel = buffer.floatChannelData![0]
        for frame in 0 ..< Int(frameCount) {
            let progress = Double(frame) / format.sampleRate
            let envelope = min(1.0, Double(frame) / 600.0) * min(1.0, Double(Int(frameCount) - frame) / 600.0)
            channel[frame] = Float(sin(2 * .pi * frequency * progress) * 0.24 * envelope)
        }
        return buffer
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
        let json = try await post(path: "/api/geocode/autobbox", body: [
            "query": query,
            "countryCode": countryCode,
        ])
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
        let json = try await post(path: "/api/overpass/segment", body: [
            "roadName": roadName,
            "countryCode": countryCode,
        ])
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