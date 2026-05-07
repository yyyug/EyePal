import SwiftUI
import CoreLocation
import Network
import AVFoundation
import CoreMotion
import UIKit

private let suiteBaseURL = URL(string: "https://via.inclu.si")!

struct SoundscapeFeatureSuiteView: View {
    @StateObject private var viewModel = SoundscapeSuiteViewModel()
    @State private var showStandby = false

    var body: some View {
        List {
            Section("Main") {
                Button("Sleep / Standby") {
                    showStandby = true
                }
            }

            Section("Search") {
                NavigationLink("Search Results (Embedded)") {
                    SearchResultsEmbeddedView(viewModel: viewModel)
                }
                NavigationLink("Search Results (Modal)") {
                    SearchResultsModalLauncherView(viewModel: viewModel)
                }
                NavigationLink("Search Table") {
                    SearchTableView(viewModel: viewModel)
                }
                NavigationLink("Search Waypoint") {
                    SearchWaypointView(viewModel: viewModel)
                }
            }

            Section("Location") {
                NavigationLink("Location Detail") {
                    if let selected = viewModel.selectedPlace ?? viewModel.searchResults.first {
                        SuiteLocationDetailView(viewModel: viewModel, place: selected)
                    } else {
                        EmptyStateView(message: "Search or load nearby places first.")
                    }
                }
                NavigationLink("Street Preview") {
                    StreetPreviewSearchEntryView(viewModel: viewModel)
                }
                NavigationLink("Street Preview Place Search") {
                    StreetPreviewPlaceSwitcherView(viewModel: viewModel)
                }
            }

            Section("Markers and Routes") {
                NavigationLink("Markers and Routes Home") {
                    MarkersRoutesHomeView(viewModel: viewModel)
                }
            }

            Section("System") {
                NavigationLink("Devices") {
                    DevicesManagementView(viewModel: viewModel)
                }
                NavigationLink("Settings") {
                    SettingsView()
                }
                NavigationLink("Help and Tutorials") {
                    HelpAndTutorialsView(viewModel: viewModel)
                }
                NavigationLink("Offline Banner Scenarios") {
                    OfflineBannerView(viewModel: viewModel)
                }
                NavigationLink("System Dialogs") {
                    SystemDialogsView(viewModel: viewModel)
                }
            }
        }
        .navigationTitle("Soundscape Features")
        .overlay(alignment: .top) {
            if viewModel.isOffline {
                Text("Offline mode: live search is limited. Saved markers and routes remain available.")
                    .font(.footnote)
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(.orange)
                    .foregroundStyle(.white)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task {
            viewModel.bootstrap()
        }
        .fullScreenCover(isPresented: $showStandby) {
            StandbyView()
        }
    }
}

private struct EmptyStateView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

private struct SearchResultsEmbeddedView: View {
    @ObservedObject var viewModel: SoundscapeSuiteViewModel

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                TextField("Search place", text: $viewModel.searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .onSubmit {
                        Task { await viewModel.search() }
                    }

                Button {
                    Task { await viewModel.search() }
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSearching)
            }
            .padding(.horizontal)
            .padding(.top)

            if viewModel.isSearching {
                ProgressView("Searching")
                    .padding(.bottom, 8)
            }

            List(viewModel.searchResults) { place in
                NavigationLink {
                    SuiteLocationDetailView(viewModel: viewModel, place: place)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(place.title)
                        Text(place.subtitleText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    Button {
                        viewModel.addMarker(from: place)
                    } label: {
                        Label("Save Marker", systemImage: "mappin.and.ellipse")
                    }

                    Button {
                        viewModel.setBeacon(place)
                    } label: {
                        Label("Set Beacon", systemImage: "dot.radiowaves.left.and.right")
                    }
                    .tint(.indigo)
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("Embedded Results")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Nearby") {
                    Task { await viewModel.refreshNearby() }
                }
            }
        }
    }
}

private struct SearchResultsModalLauncherView: View {
    @ObservedObject var viewModel: SoundscapeSuiteViewModel
    @State private var showModal = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Open full search in modal style with marker and beacon actions.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Search") {
                showModal = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .navigationTitle("Modal Results")
        .sheet(isPresented: $showModal) {
            NavigationStack {
                SearchResultsEmbeddedView(viewModel: viewModel)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                showModal = false
                            }
                        }
                    }
            }
        }
    }
}

private struct SearchTableView: View {
    @ObservedObject var viewModel: SoundscapeSuiteViewModel

    var body: some View {
        List {
            Section("Recent Searches") {
                if viewModel.recentSearches.isEmpty {
                    Text("No recent searches")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.recentSearches, id: \.self) { row in
                        Button(row) {
                            viewModel.searchQuery = row
                            Task { await viewModel.search() }
                        }
                    }
                }
            }

            Section("Saved Markers") {
                if viewModel.markers.isEmpty {
                    Text("No markers")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.markers) { marker in
                        Text(marker.title)
                    }
                }
            }

            Section("Current Nearby") {
                if viewModel.searchResults.isEmpty {
                    Text("No nearby results loaded")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.searchResults.prefix(8)) { place in
                        Text(place.subtitleText)
                    }
                }
            }
        }
        .navigationTitle("Search Table")
    }
}

private struct SearchWaypointView: View {
    @ObservedObject var viewModel: SoundscapeSuiteViewModel
    @State private var routeName = ""
    @State private var selectedIDs = Set<String>()

    var body: some View {
        Form {
            Section("Route") {
                TextField("Route name", text: $routeName)
            }

            Section("Pick Waypoints") {
                if viewModel.searchResults.isEmpty {
                    Text("No search results. Search first.")
                        .foregroundStyle(.secondary)
                }

                ForEach(viewModel.searchResults) { place in
                    Toggle(isOn: Binding(
                        get: { selectedIDs.contains(place.id) },
                        set: { isOn in
                            if isOn {
                                selectedIDs.insert(place.id)
                            } else {
                                selectedIDs.remove(place.id)
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.title)
                            Text(place.subtitleText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                Button("Save Route") {
                    viewModel.createRoute(name: routeName, selectedPlaceIDs: Array(selectedIDs))
                    routeName = ""
                    selectedIDs.removeAll()
                }
                .disabled(routeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedIDs.count < 2)
            }
        }
        .navigationTitle("Search Waypoint")
    }
}

private struct SuiteLocationDetailView: View {
    @ObservedObject var viewModel: SoundscapeSuiteViewModel
    let place: SuitePlace

    var body: some View {
        Form {
            Section("Identity") {
                Text(place.title)
                Text("Category: \(place.category.displayName)")
                if let address = place.addressLabel, !address.isEmpty {
                    Text(address)
                }
                if let distance = place.distanceMeters {
                    Text("Distance: \(distance) m")
                }
            }

            Section("Actions") {
                Button("Set Beacon") {
                    viewModel.setBeacon(place)
                }
                Button("Save Marker") {
                    viewModel.addMarker(from: place)
                }
                Button("Use for Street Preview") {
                    viewModel.selectedPlace = place
                }
            }
        }
        .navigationTitle("Location Detail")
        .onAppear {
            viewModel.selectedPlace = place
        }
    }
}

private struct StreetPreviewSearchEntryView: View {
    @ObservedObject var viewModel: SoundscapeSuiteViewModel

    var body: some View {
        VStack(spacing: 14) {
            if let place = viewModel.selectedPlace ?? viewModel.searchResults.first {
                Text("Preview target: \(place.title)")
                NavigationLink("Open Street Preview") {
                    StreetPreviewView(initialLocation: place.location, initialHeading: viewModel.facingHeading)
                }
                .buttonStyle(.borderedProminent)
            } else if let current = viewModel.currentLocation {
                Text("Using current GPS location")
                NavigationLink("Open Street Preview") {
                    StreetPreviewView(initialLocation: current, initialHeading: viewModel.facingHeading)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("No target available yet.")
                    .foregroundStyle(.secondary)
            }

            Button("Load Nearby Places") {
                Task { await viewModel.refreshNearby() }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .navigationTitle("Street Preview")
    }
}

private struct StreetPreviewPlaceSwitcherView: View {
    @ObservedObject var viewModel: SoundscapeSuiteViewModel

    var body: some View {
        let places = viewModel.searchResults

        List(places, id: \.id) { place in
            StreetPreviewPlaceRow(
                place: place,
                isSelected: viewModel.selectedPlace?.id == place.id
            ) {
                viewModel.selectedPlace = place
            }
        }
        .navigationTitle("Preview Place Search")
    }
}

private struct StreetPreviewPlaceRow: View {
    let place: SoundscapePlace
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.title)
                    Text(place.subtitleText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.accent)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct MarkersRoutesHomeView: View {
    @ObservedObject var viewModel: SoundscapeSuiteViewModel
    @State private var selection = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $selection) {
                Text("Markers").tag(0)
                Text("Routes").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            if selection == 0 {
                MarkersListView(viewModel: viewModel)
            } else {
                RoutesListView(viewModel: viewModel)
            }
        }
        .navigationTitle("Markers and Routes")
    }
}

private struct MarkersListView: View {
    @ObservedObject var viewModel: SoundscapeSuiteViewModel
    @State private var editing: SuiteMarker?
    @State private var showingAdd = false

    var body: some View {
        List {
            if viewModel.markers.isEmpty {
                Text("No markers saved")
                    .foregroundStyle(.secondary)
            }

            ForEach(viewModel.markers) { marker in
                NavigationLink {
                    MarkerEditorView(viewModel: viewModel, marker: marker)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(marker.title)
                        Text(marker.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        viewModel.deleteMarker(marker)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }

                    Button {
                        editing = marker
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                }
            }
        }
        .sheet(item: $editing) { marker in
            NavigationStack {
                MarkerEditorView(viewModel: viewModel, marker: marker)
            }
        }
        .sheet(isPresented: $showingAdd) {
            NavigationStack {
                MarkerEditorView(viewModel: viewModel, marker: nil)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAdd = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
    }
}

private struct MarkerEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: SoundscapeSuiteViewModel
    let marker: SuiteMarker?
    @State private var title = ""
    @State private var subtitle = ""

    var body: some View {
        Form {
            Section("Marker") {
                TextField("Name", text: $title)
                TextField("Note", text: $subtitle)
            }

            Section {
                Button(marker == nil ? "Create Marker" : "Update Marker") {
                    if let marker {
                        viewModel.updateMarker(marker: marker, title: title, subtitle: subtitle)
                    } else {
                        viewModel.createMarkerAtCurrentLocation(title: title, subtitle: subtitle)
                    }
                    dismiss()
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let marker {
                    Button("Delete Marker", role: .destructive) {
                        viewModel.deleteMarker(marker)
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(marker == nil ? "Add Marker" : "Edit Marker")
        .onAppear {
            title = marker?.title ?? ""
            subtitle = marker?.subtitle ?? ""
        }
    }
}

private struct RoutesListView: View {
    @ObservedObject var viewModel: SoundscapeSuiteViewModel
    @State private var showingAdd = false

    var body: some View {
        List {
            if viewModel.routes.isEmpty {
                Text("No routes saved")
                    .foregroundStyle(.secondary)
            }

            ForEach(viewModel.routes) { route in
                NavigationLink {
                    RouteDetailView(viewModel: viewModel, route: route)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(route.name)
                        Text("\(route.waypoints.count) waypoints")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        viewModel.deleteRoute(route)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            NavigationStack {
                RouteEditorView(viewModel: viewModel, route: nil)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAdd = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
    }
}

private struct RouteDetailView: View {
    @ObservedObject var viewModel: SoundscapeSuiteViewModel
    let route: SuiteRoute

    var body: some View {
        Form {
            Section("Route") {
                Text(route.name)
                Text(route.description)
                    .foregroundStyle(.secondary)
                Text("Waypoints: \(route.waypoints.count)")
                    .foregroundStyle(.secondary)
            }

            Section("Guidance") {
                Button(viewModel.activeRoute?.id == route.id ? "Stop Route" : "Start Route") {
                    if viewModel.activeRoute?.id == route.id {
                        viewModel.stopRoute()
                    } else {
                        viewModel.startRoute(route)
                    }
                }

                Text(viewModel.activeRoute?.id == route.id ? viewModel.activeRouteProgressText : "Inactive")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Waypoints") {
                ForEach(route.waypoints) { waypoint in
                    NavigationLink {
                        WaypointDetailView(waypoint: waypoint)
                    } label: {
                        Text(waypoint.title)
                    }
                }
            }

            Section {
                NavigationLink("Edit Route") {
                    RouteEditorView(viewModel: viewModel, route: route)
                }
            }
        }
        .navigationTitle("Route Detail")
    }
}

private struct RouteEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: SoundscapeSuiteViewModel
    let route: SuiteRoute?

    @State private var name = ""
    @State private var descriptionText = ""
    @State private var selectedWaypointIDs = Set<UUID>()

    private var candidateWaypoints: [SuiteWaypoint] {
        var fromSearch = viewModel.searchResults.map { SuiteWaypoint(id: UUID(), title: $0.title, lat: $0.lat, lon: $0.lon) }
        let fromMarkers = viewModel.markers.map { SuiteWaypoint(id: UUID(), title: $0.title, lat: $0.lat, lon: $0.lon) }
        fromSearch.append(contentsOf: fromMarkers)
        return fromSearch
    }

    var body: some View {
        Form {
            Section("Route") {
                TextField("Route Name", text: $name)
                TextField("Description", text: $descriptionText)
            }

            Section("Waypoints") {
                if candidateWaypoints.isEmpty {
                    Text("Search places or save markers to add waypoints")
                        .foregroundStyle(.secondary)
                }
                ForEach(candidateWaypoints) { waypoint in
                    Toggle(isOn: Binding(
                        get: { selectedWaypointIDs.contains(waypoint.id) },
                        set: { isOn in
                            if isOn {
                                selectedWaypointIDs.insert(waypoint.id)
                            } else {
                                selectedWaypointIDs.remove(waypoint.id)
                            }
                        }
                    )) {
                        Text(waypoint.title)
                    }
                }
            }

            Section {
                Button(route == nil ? "Create Route" : "Update Route") {
                    let selected = candidateWaypoints.filter { selectedWaypointIDs.contains($0.id) }
                    if let route {
                        viewModel.updateRoute(route: route, name: name, description: descriptionText, waypoints: selected)
                    } else {
                        viewModel.createRoute(name: name, description: descriptionText, waypoints: selected)
                    }
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedWaypointIDs.count < 2)
            }
        }
        .navigationTitle(route == nil ? "Add Route" : "Edit Route")
        .onAppear {
            name = route?.name ?? ""
            descriptionText = route?.description ?? ""
        }
    }
}

private struct WaypointDetailView: View {
    let waypoint: SuiteWaypoint

    var body: some View {
        Form {
            Text("Waypoint: \(waypoint.title)")
            Text("Lat: \(waypoint.lat)")
            Text("Lon: \(waypoint.lon)")
        }
        .navigationTitle("Waypoint Detail")
    }
}

private struct DevicesManagementView: View {
    @ObservedObject var viewModel: SoundscapeSuiteViewModel

    var body: some View {
        Form {
            Section("Audio") {
                Text("Output: \(viewModel.audioOutputName)")
                Text("Headphone motion: \(viewModel.headphoneMotionAvailable ? "Available" : "Unavailable")")
            }

            Section("Sensors") {
                Text("Location authorization: \(viewModel.locationPermissionLabel)")
                Text("Facing heading: \(Int(viewModel.facingHeading.rounded()))°")
            }

            Section("Connection") {
                Text(viewModel.isOffline ? "Offline" : "Online")
            }
        }
        .navigationTitle("Devices")
    }
}

private struct HelpAndTutorialsView: View {
    @ObservedObject var viewModel: SoundscapeSuiteViewModel

    var body: some View {
        List {
            Section("Core") {
                Text("My Location: announces your road, heading, and GPS quality.")
                Text("Around Me: nearby categorized POIs with directional cues.")
                Text("Ahead of Me: forward-prioritized POIs and route progression.")
                Text("Markers: save custom places and receive arrival announcements.")
                Text("Routes: ordered waypoint guidance with completion callouts.")
            }

            Section("Current Session") {
                Text("Nearby places loaded: \(viewModel.searchResults.count)")
                Text("Saved markers: \(viewModel.markers.count)")
                Text("Saved routes: \(viewModel.routes.count)")
                Text("Active beacon: \(viewModel.activeBeaconTitle ?? "None")")
            }
        }
        .navigationTitle("Help")
    }
}

private struct OfflineBannerView: View {
    @ObservedObject var viewModel: SoundscapeSuiteViewModel

    var body: some View {
        VStack(spacing: 12) {
            Text(viewModel.isOffline ? "Offline" : "Online")
                .font(.headline)

            Text(viewModel.isOffline
                 ? "Network is unavailable. Search and cloud lookups are paused; local markers/routes still work."
                 : "Connected. Live nearby and search data are available.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Button("Refresh Nearby") {
                Task { await viewModel.refreshNearby() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isOffline)

            Spacer()
        }
        .padding()
        .navigationTitle("Offline Banner")
    }
}

private struct SystemDialogsView: View {
    @ObservedObject var viewModel: SoundscapeSuiteViewModel
    @State private var showReset = false
    @State private var showPermission = false

    var body: some View {
        Form {
            Button("Show Reset Confirmation") {
                showReset = true
            }

            Button("Show Permission Dialog") {
                showPermission = true
            }
        }
        .alert("Reset local data?", isPresented: $showReset) {
            Button("Reset", role: .destructive) {
                viewModel.resetLocalData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Markers and routes will be deleted from this device.")
        }
        .alert("Location permission required", isPresented: $showPermission) {
            Button("Open Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Enable location for accurate search, route guidance, and beacon behavior.")
        }
        .navigationTitle("System Dialogs")
    }
}

private struct SuitePlace: Identifiable, Hashable {
    let id: String
    let title: String
    let category: SuiteCategory
    let addressLabel: String?
    let lat: Double
    let lon: Double
    let distanceMeters: Int?
    let bearing: Double?

    var location: CLLocation {
        CLLocation(latitude: lat, longitude: lon)
    }

    var subtitleText: String {
        var parts: [String] = [category.displayName]
        if let distanceMeters {
            parts.append("\(distanceMeters)m")
        }
        if let addressLabel, !addressLabel.isEmpty {
            parts.append(addressLabel)
        }
        return parts.joined(separator: " • ")
    }
}

private enum SuiteCategory: String, Codable, CaseIterable {
    case transit
    case mobility
    case crossing
    case building
    case amenity
    case park
    case unknown

    var displayName: String {
        switch self {
        case .transit: return "Transit"
        case .mobility: return "Mobility"
        case .crossing: return "Crossing"
        case .building: return "Building"
        case .amenity: return "Amenity"
        case .park: return "Park"
        case .unknown: return "Place"
        }
    }

    var priority: Int {
        switch self {
        case .transit: return 100
        case .mobility: return 90
        case .crossing: return 80
        case .building: return 70
        case .amenity: return 60
        case .park: return 50
        case .unknown: return 10
        }
    }

    static func resolve(kind: String?, title: String) -> SuiteCategory {
        let combined = "\(kind ?? "") \(title)".lowercased()
        if combined.contains("bus") || combined.contains("train") || combined.contains("station") || combined.contains("metro") {
            return .transit
        }
        if combined.contains("stair") || combined.contains("lift") || combined.contains("elevator") || combined.contains("escalator") {
            return .mobility
        }
        if combined.contains("cross") || combined.contains("junction") || combined.contains("intersection") {
            return .crossing
        }
        if combined.contains("building") || combined.contains("tower") || combined.contains("mall") || combined.contains("school") {
            return .building
        }
        if combined.contains("playground") || combined.contains("park") || combined.contains("garden") {
            return .park
        }
        if combined.contains("shop") || combined.contains("restaurant") || combined.contains("hospital") || combined.contains("toilet") {
            return .amenity
        }
        return .unknown
    }
}

private struct SuiteMarker: Identifiable, Codable, Hashable {
    let id: UUID
    let title: String
    let subtitle: String
    let lat: Double
    let lon: Double
    let createdAt: Date
}

private struct SuiteWaypoint: Identifiable, Codable, Hashable {
    let id: UUID
    let title: String
    let lat: Double
    let lon: Double
}

private struct SuiteRoute: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let description: String
    let waypoints: [SuiteWaypoint]
    let createdAt: Date
}

@MainActor
private final class SoundscapeSuiteViewModel: ObservableObject {
    @Published var searchQuery = ""
    @Published var searchResults: [SuitePlace] = []
    @Published var recentSearches: [String] = []
    @Published var isSearching = false
    @Published var selectedPlace: SuitePlace?
    @Published var markers: [SuiteMarker] = []
    @Published var routes: [SuiteRoute] = []
    @Published var activeRoute: SuiteRoute?
    @Published var activeRouteProgressText = "No active route"
    @Published var activeBeaconTitle: String?
    @Published var isOffline = false
    @Published var currentLocation: CLLocation?
    @Published var facingHeading: Double = 0
    @Published var locationPermissionLabel = "Unknown"

    var audioOutputName: String {
        AVAudioSession.sharedInstance().currentRoute.outputs.first?.portName ?? "Unknown"
    }

    var headphoneMotionAvailable: Bool {
        if #available(iOS 14.4, *) {
            return CMHeadphoneMotionManager().isDeviceMotionAvailable
        }
        return false
    }

    private let store = SuitePersistenceStore()
    private let apiClient = SuiteBackendClient()
    private let locationTracker = SuiteLiveLocationTracker()
    private let connectivity = SuiteConnectivityMonitor()
    private let oneShotLocation = SuiteCurrentLocationProvider()
    private var activeBeacon: SuitePlace?
    private var reachedWaypointIDs = Set<UUID>()
    private var lastNearbyRefresh: Date?

    func bootstrap() {
        markers = store.loadMarkers()
        routes = store.loadRoutes()
        recentSearches = store.loadRecentSearches()

        locationTracker.onLocationUpdate = { [weak self] location in
            guard let self else { return }
            Task { @MainActor in
                self.currentLocation = location
                self.handleGuidanceProgress(location: location)
                self.refreshNearbyIfNeeded(location: location)
            }
        }
        locationTracker.onHeadingUpdate = { [weak self] heading in
            Task { @MainActor in
                self?.facingHeading = heading
            }
        }
        locationTracker.onAuthorizationUpdate = { [weak self] label in
            Task { @MainActor in
                self?.locationPermissionLabel = label
            }
        }
        locationTracker.start()

        connectivity.onChange = { [weak self] isOffline in
            Task { @MainActor in
                self?.isOffline = isOffline
            }
        }
        connectivity.start()

        if searchResults.isEmpty {
            Task { await refreshNearby() }
        }
    }

    func search() async {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            await refreshNearby()
            return
        }

        isSearching = true
        defer { isSearching = false }

        do {
            let geocode = try await apiClient.autobbox(query: trimmed)
            var merged: [SuitePlace] = []

            if let lat = geocode.lat, let lon = geocode.lon {
                let top = SuitePlace(
                    id: "geocode-\(lat)-\(lon)-\(trimmed)",
                    title: geocode.displayName,
                    category: .resolve(kind: geocode.kindLabel, title: geocode.displayName),
                    addressLabel: geocode.displayName,
                    lat: lat,
                    lon: lon,
                    distanceMeters: distanceFromCurrent(lat: lat, lon: lon),
                    bearing: bearingFromCurrent(lat: lat, lon: lon)
                )
                merged.append(top)

                let around = try await apiClient.fetchPlacesAround(lat: lat, lon: lon, radiusMeters: 450)
                merged.append(contentsOf: around.map {
                    SuitePlace(
                        id: $0.id,
                        title: $0.title,
                        category: .resolve(kind: $0.kindLabel, title: $0.title),
                        addressLabel: $0.addressLabel,
                        lat: $0.lat,
                        lon: $0.lon,
                        distanceMeters: $0.distanceMeters,
                        bearing: $0.bearing
                    )
                })
            }

            searchResults = rankAndDedupe(merged)
            selectedPlace = searchResults.first
            rememberSearch(trimmed)
        } catch {
            if searchResults.isEmpty {
                searchResults = markers.prefix(12).map {
                    SuitePlace(
                        id: "marker-\($0.id.uuidString)",
                        title: $0.title,
                        category: .amenity,
                        addressLabel: $0.subtitle,
                        lat: $0.lat,
                        lon: $0.lon,
                        distanceMeters: distanceFromCurrent(lat: $0.lat, lon: $0.lon),
                        bearing: bearingFromCurrent(lat: $0.lat, lon: $0.lon)
                    )
                }
            }
        }
    }

    func refreshNearby() async {
        if isOffline { return }

        do {
            let location = try await resolveCurrentLocation()
            let rows = try await apiClient.fetchPlacesAround(
                lat: location.coordinate.latitude,
                lon: location.coordinate.longitude,
                radiusMeters: 280
            )
            searchResults = rankAndDedupe(rows.map {
                SuitePlace(
                    id: $0.id,
                    title: $0.title,
                    category: .resolve(kind: $0.kindLabel, title: $0.title),
                    addressLabel: $0.addressLabel,
                    lat: $0.lat,
                    lon: $0.lon,
                    distanceMeters: $0.distanceMeters,
                    bearing: $0.bearing
                )
            })
            selectedPlace = selectedPlace ?? searchResults.first
            lastNearbyRefresh = Date()
        } catch {
            if searchResults.isEmpty {
                searchResults = []
            }
        }
    }

    func addMarker(from place: SuitePlace) {
        let marker = SuiteMarker(
            id: UUID(),
            title: place.title,
            subtitle: place.addressLabel ?? place.category.displayName,
            lat: place.lat,
            lon: place.lon,
            createdAt: Date()
        )
        markers.insert(marker, at: 0)
        store.saveMarkers(markers)
        announce("Marker saved: \(place.title)")
    }

    func createMarkerAtCurrentLocation(title: String, subtitle: String) {
        guard let currentLocation else { return }
        let marker = SuiteMarker(
            id: UUID(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            subtitle: subtitle,
            lat: currentLocation.coordinate.latitude,
            lon: currentLocation.coordinate.longitude,
            createdAt: Date()
        )
        markers.insert(marker, at: 0)
        store.saveMarkers(markers)
    }

    func updateMarker(marker: SuiteMarker, title: String, subtitle: String) {
        guard let index = markers.firstIndex(where: { $0.id == marker.id }) else { return }
        markers[index] = SuiteMarker(
            id: marker.id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            subtitle: subtitle,
            lat: marker.lat,
            lon: marker.lon,
            createdAt: marker.createdAt
        )
        store.saveMarkers(markers)
    }

    func deleteMarker(_ marker: SuiteMarker) {
        markers.removeAll { $0.id == marker.id }
        store.saveMarkers(markers)
    }

    func createRoute(name: String, selectedPlaceIDs: [String]) {
        let selected = searchResults.filter { selectedPlaceIDs.contains($0.id) }
        let waypoints = selected.map {
            SuiteWaypoint(id: UUID(), title: $0.title, lat: $0.lat, lon: $0.lon)
        }
        createRoute(name: name, description: "Created from search waypoints", waypoints: waypoints)
    }

    func createRoute(name: String, description: String, waypoints: [SuiteWaypoint]) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, waypoints.count >= 2 else { return }
        let route = SuiteRoute(
            id: UUID(),
            name: trimmed,
            description: description,
            waypoints: waypoints,
            createdAt: Date()
        )
        routes.insert(route, at: 0)
        store.saveRoutes(routes)
        announce("Route saved: \(trimmed)")
    }

    func updateRoute(route: SuiteRoute, name: String, description: String, waypoints: [SuiteWaypoint]) {
        guard let index = routes.firstIndex(where: { $0.id == route.id }) else { return }
        routes[index] = SuiteRoute(
            id: route.id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description,
            waypoints: waypoints,
            createdAt: route.createdAt
        )
        store.saveRoutes(routes)
    }

    func deleteRoute(_ route: SuiteRoute) {
        routes.removeAll { $0.id == route.id }
        store.saveRoutes(routes)
        if activeRoute?.id == route.id {
            stopRoute()
        }
    }

    func startRoute(_ route: SuiteRoute) {
        activeRoute = route
        reachedWaypointIDs.removeAll()
        activeRouteProgressText = "Guiding to waypoint 1 of \(route.waypoints.count)"
        announce("Route started: \(route.name)")
    }

    func stopRoute() {
        if let activeRoute {
            announce("Route stopped: \(activeRoute.name)")
        }
        activeRoute = nil
        reachedWaypointIDs.removeAll()
        activeRouteProgressText = "No active route"
    }

    func setBeacon(_ place: SuitePlace) {
        activeBeacon = place
        activeBeaconTitle = place.title
        announce("Beacon set: \(place.title)")
    }

    func resetLocalData() {
        markers = []
        routes = []
        activeRoute = nil
        activeRouteProgressText = "No active route"
        store.resetAll()
    }

    private func handleGuidanceProgress(location: CLLocation) {
        if let activeRoute {
            let remaining = activeRoute.waypoints.filter { !reachedWaypointIDs.contains($0.id) }
            guard let nextWaypoint = remaining.first else {
                activeRouteProgressText = "Route completed"
                announce("Route complete")
                stopRoute()
                return
            }

            let target = CLLocation(latitude: nextWaypoint.lat, longitude: nextWaypoint.lon)
            let distance = Int(location.distance(from: target).rounded())
            activeRouteProgressText = "Next waypoint: \(nextWaypoint.title), \(distance) meters"

            if distance <= 22 {
                reachedWaypointIDs.insert(nextWaypoint.id)
                announce("Waypoint reached: \(nextWaypoint.title)")
            }
        }

        if let activeBeacon {
            let beaconLoc = CLLocation(latitude: activeBeacon.lat, longitude: activeBeacon.lon)
            let distance = Int(location.distance(from: beaconLoc).rounded())
            if distance <= 25 {
                announce("Beacon nearby: \(activeBeacon.title)")
            }
        }
    }

    private func refreshNearbyIfNeeded(location: CLLocation) {
        currentLocation = location
        guard let lastNearbyRefresh else {
            Task { await refreshNearby() }
            return
        }
        if Date().timeIntervalSince(lastNearbyRefresh) > 40 {
            Task { await refreshNearby() }
        }
    }

    private func resolveCurrentLocation() async throws -> CLLocation {
        if let currentLocation {
            return currentLocation
        }
        return try await oneShotLocation.requestCurrentLocation()
    }

    private func distanceFromCurrent(lat: Double, lon: Double) -> Int? {
        guard let currentLocation else { return nil }
        return Int(currentLocation.distance(from: CLLocation(latitude: lat, longitude: lon)).rounded())
    }

    private func bearingFromCurrent(lat: Double, lon: Double) -> Double? {
        guard let currentLocation else { return nil }
        let to = CLLocation(latitude: lat, longitude: lon)
        let lat1 = currentLocation.coordinate.latitude * .pi / 180
        let lat2 = to.coordinate.latitude * .pi / 180
        let dLon = (to.coordinate.longitude - currentLocation.coordinate.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    private func rankAndDedupe(_ places: [SuitePlace]) -> [SuitePlace] {
        var seen = Set<String>()
        let deduped = places.filter {
            let key = $0.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }

        return deduped.sorted {
            let lhsDistance = $0.distanceMeters ?? 9999
            let rhsDistance = $1.distanceMeters ?? 9999
            let lhsScore = ($0.category.priority * 1000) - lhsDistance
            let rhsScore = ($1.category.priority * 1000) - rhsDistance
            if lhsScore == rhsScore {
                return lhsDistance < rhsDistance
            }
            return lhsScore > rhsScore
        }
    }

    private func rememberSearch(_ query: String) {
        recentSearches.removeAll { $0.caseInsensitiveCompare(query) == .orderedSame }
        recentSearches.insert(query, at: 0)
        recentSearches = Array(recentSearches.prefix(20))
        store.saveRecentSearches(recentSearches)
    }

    private func announce(_ message: String) {
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}

private final class SuitePersistenceStore {
    private let defaults = UserDefaults.standard
    private let markerKey = "soundscape.suite.markers.v1"
    private let routeKey = "soundscape.suite.routes.v1"
    private let recentSearchesKey = "soundscape.suite.searches.v1"

    func loadMarkers() -> [SuiteMarker] {
        guard let data = defaults.data(forKey: markerKey),
              let decoded = try? JSONDecoder().decode([SuiteMarker].self, from: data) else {
            return []
        }
        return decoded
    }

    func saveMarkers(_ markers: [SuiteMarker]) {
        if let data = try? JSONEncoder().encode(markers) {
            defaults.set(data, forKey: markerKey)
        }
    }

    func loadRoutes() -> [SuiteRoute] {
        guard let data = defaults.data(forKey: routeKey),
              let decoded = try? JSONDecoder().decode([SuiteRoute].self, from: data) else {
            return []
        }
        return decoded
    }

    func saveRoutes(_ routes: [SuiteRoute]) {
        if let data = try? JSONEncoder().encode(routes) {
            defaults.set(data, forKey: routeKey)
        }
    }

    func loadRecentSearches() -> [String] {
        defaults.stringArray(forKey: recentSearchesKey) ?? []
    }

    func saveRecentSearches(_ searches: [String]) {
        defaults.set(searches, forKey: recentSearchesKey)
    }

    func resetAll() {
        defaults.removeObject(forKey: markerKey)
        defaults.removeObject(forKey: routeKey)
        defaults.removeObject(forKey: recentSearchesKey)
    }
}

private final class SuiteBackendClient {
    struct GeocodeResult {
        let displayName: String
        let lat: Double?
        let lon: Double?
        let kindLabel: String?
    }

    struct NearbyPlacePayload {
        let id: String
        let title: String
        let kindLabel: String?
        let addressLabel: String?
        let lat: Double
        let lon: Double
        let distanceMeters: Int
        let bearing: Double
    }

    func autobbox(query: String) async throws -> GeocodeResult {
        let json = try await post(path: "/api/geocode/autobbox", body: ["query": query])
        return GeocodeResult(
            displayName: json["displayName"] as? String ?? query,
            lat: json["lat"] as? Double,
            lon: json["lon"] as? Double,
            kindLabel: json["kindLabel"] as? String
        )
    }

    func fetchPlacesAround(lat: Double, lon: Double, radiusMeters: Int) async throws -> [NearbyPlacePayload] {
        let json = try await post(path: "/api/osm/places-around", body: [
            "lat": lat,
            "lon": lon,
            "radiusMeters": radiusMeters,
        ])
        let rows = json["places"] as? [[String: Any]] ?? []
        return rows.enumerated().map { index, row in
            NearbyPlacePayload(
                id: row["id"] as? String ?? "poi-\(index)",
                title: row["title"] as? String ?? row["name"] as? String ?? "Unnamed place",
                kindLabel: row["kindLabel"] as? String,
                addressLabel: row["addressLabel"] as? String,
                lat: row["lat"] as? Double ?? 0,
                lon: row["lon"] as? Double ?? 0,
                distanceMeters: row["distanceMeters"] as? Int ?? 0,
                bearing: row["bearing"] as? Double ?? 0
            )
        }
    }

    private func post(path: String, body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: suiteBaseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "SuiteBackendClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard (200...299).contains(http.statusCode) else {
            let message = json["error"] as? String ?? "Request failed with status \(http.statusCode)"
            throw NSError(domain: "SuiteBackendClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }

        if json.isEmpty {
            throw NSError(domain: "SuiteBackendClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "Unexpected empty response"])
        }

        return json
    }
}

private final class SuiteConnectivityMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "suite.connectivity.monitor")
    var onChange: ((Bool) -> Void)?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.onChange?(path.status != .satisfied)
        }
        monitor.start(queue: queue)
    }
}

@MainActor
private final class SuiteLiveLocationTracker: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    var onLocationUpdate: ((CLLocation) -> Void)?
    var onHeadingUpdate: ((Double) -> Void)?
    var onAuthorizationUpdate: ((String) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10
        manager.headingFilter = 5
    }

    func start() {
        updatePermissionLabel(status: manager.authorizationStatus)
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            manager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() {
                manager.startUpdatingHeading()
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.updatePermissionLabel(status: manager.authorizationStatus)
            if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
                manager.startUpdatingLocation()
                if CLLocationManager.headingAvailable() {
                    manager.startUpdatingHeading()
                }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.onLocationUpdate?(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in
            self.onHeadingUpdate?(heading)
        }
    }

    private func updatePermissionLabel(status: CLAuthorizationStatus) {
        let label: String
        switch status {
        case .authorizedAlways:
            label = "Always"
        case .authorizedWhenInUse:
            label = "When In Use"
        case .denied:
            label = "Denied"
        case .restricted:
            label = "Restricted"
        case .notDetermined:
            label = "Not Determined"
        @unknown default:
            label = "Unknown"
        }
        onAuthorizationUpdate?(label)
    }
}

private final class SuiteCurrentLocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestCurrentLocation() async throws -> CLLocation {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            throw NSError(domain: "SuiteCurrentLocationProvider", code: 1, userInfo: [NSLocalizedDescriptionKey: "Location permission unavailable"])
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.manager.requestLocation()
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
