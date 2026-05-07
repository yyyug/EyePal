import SwiftUI
import CoreLocation

struct SoundscapeFeatureSuiteView: View {
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
                    SearchResultsEmbeddedView()
                }
                NavigationLink("Search Results (Modal)") {
                    SearchResultsModalLauncherView()
                }
                NavigationLink("Search Table") {
                    SearchTableView()
                }
                NavigationLink("Search Waypoint") {
                    SearchWaypointView()
                }
            }

            Section("Location") {
                NavigationLink("Location Detail") {
                    LocationDetailDemoView()
                }
                NavigationLink("Street Preview") {
                    StreetPreviewSearchEntryView()
                }
                NavigationLink("Street Preview Place Search") {
                    StreetPreviewPlaceSwitcherView()
                }
            }

            Section("Markers and Routes") {
                NavigationLink("Markers and Routes Home") {
                    MarkersRoutesHomeView()
                }
            }

            Section("System") {
                NavigationLink("Devices") {
                    DevicesManagementView()
                }
                NavigationLink("Settings") {
                    SettingsView()
                }
                NavigationLink("Help and Tutorials") {
                    HelpAndTutorialsView()
                }
                NavigationLink("Offline Banner Scenarios") {
                    OfflineBannerDemoView()
                }
                NavigationLink("System Dialogs") {
                    SystemDialogsDemoView()
                }
            }
        }
        .navigationTitle("Soundscape Features")
        .fullScreenCover(isPresented: $showStandby) {
            StandbyView()
        }
    }
}

private struct SearchResultsEmbeddedView: View {
    @State private var query = ""
    private let sample = ["Central Station", "City Park", "Bus Stop A", "Library Entrance", "Playground North"]

    var body: some View {
        VStack(spacing: 12) {
            TextField("Search", text: $query)
                .textFieldStyle(.roundedBorder)

            List(filtered, id: \.self) { row in
                NavigationLink(row) {
                    LocationDetailDemoView(name: row)
                }
            }
        }
        .padding()
        .navigationTitle("Embedded Results")
    }

    private var filtered: [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return sample }
        return sample.filter { $0.localizedCaseInsensitiveContains(q) }
    }
}

private struct SearchResultsModalLauncherView: View {
    @State private var showModal = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Open a full search page in modal style.")
                .foregroundStyle(.secondary)
            Button("Open Search") {
                showModal = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .sheet(isPresented: $showModal) {
            NavigationStack {
                SearchResultsEmbeddedView()
            }
        }
        .navigationTitle("Modal Results")
    }
}

private struct SearchTableView: View {
    var body: some View {
        List {
            NavigationLink("Markers") { MarkersListView() }
            NavigationLink("Current Location") { LocationDetailDemoView(name: "Current Location") }
            NavigationLink("Nearby") { SearchResultsEmbeddedView() }
        }
        .navigationTitle("Search Table")
    }
}

private struct SearchWaypointView: View {
    @State private var selected = Set<String>()
    private let waypoints = ["Museum", "Riverside", "Bus Interchange", "Mall Entrance"]

    var body: some View {
        List(waypoints, id: \.self, selection: $selected) { item in
            Text(item)
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save as Marker") {}
                    .disabled(selected.isEmpty)
            }
        }
        .navigationTitle("Search Waypoint")
    }
}

private struct LocationDetailDemoView: View {
    var name: String = "Sample Place"

    var body: some View {
        Form {
            Section("Identity") {
                Text(name)
                Text("Category: Place")
                Text("Address: 123 Example Street")
            }
            Section("Actions") {
                Button("Set Beacon") {}
                Button("Save Marker") {}
                Button("Share") {}
            }
        }
        .navigationTitle("Location Detail")
    }
}

private struct StreetPreviewSearchEntryView: View {
    @State private var place = ""

    var body: some View {
        VStack(spacing: 16) {
            TextField("Search place for preview", text: $place)
                .textFieldStyle(.roundedBorder)
            NavigationLink("Open Street Preview") {
                StreetPreviewView(initialLocation: CLLocation(latitude: 22.3193, longitude: 114.1694), initialHeading: 0)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .navigationTitle("Street Preview")
    }
}

private struct StreetPreviewPlaceSwitcherView: View {
    @State private var currentTarget = "Central Plaza"

    var body: some View {
        Form {
            Section("Current Target") {
                Text(currentTarget)
            }
            Section("Switch Target") {
                Button("Central Plaza") { currentTarget = "Central Plaza" }
                Button("City Garden") { currentTarget = "City Garden" }
                Button("Bus Terminal") { currentTarget = "Bus Terminal" }
            }
        }
        .navigationTitle("Preview Place Search")
    }
}

private struct MarkersRoutesHomeView: View {
    var body: some View {
        TabView {
            NavigationStack { MarkersListView() }
                .tabItem { Label("Markers", systemImage: "mappin") }
            NavigationStack { RoutesListView() }
                .tabItem { Label("Routes", systemImage: "point.topleft.down.curvedto.point.bottomright.up") }
        }
        .navigationTitle("Markers and Routes")
    }
}

private struct MarkerItem: Identifiable {
    let id = UUID()
    var name: String
    var note: String
}

private struct MarkersListView: View {
    @State private var markers = [
        MarkerItem(name: "Home", note: "Main entrance"),
        MarkerItem(name: "Office", note: "Tower B")
    ]

    var body: some View {
        List {
            ForEach(markers) { marker in
                NavigationLink(marker.name) {
                    MarkerEditorView(markerName: marker.name, note: marker.note)
                }
            }
            .onDelete { markers.remove(atOffsets: $0) }
        }
        .toolbar {
            NavigationLink("Add") {
                MarkerEditorView(markerName: "", note: "")
            }
        }
        .navigationTitle("Markers")
    }
}

private struct MarkerEditorView: View {
    @State var markerName: String
    @State var note: String

    var body: some View {
        Form {
            TextField("Name", text: $markerName)
            TextField("Note", text: $note)
            Button("Delete Marker", role: .destructive) {}
        }
        .navigationTitle("Marker Editor")
    }
}

private struct RouteItem: Identifiable {
    let id = UUID()
    var name: String
}

private struct RoutesListView: View {
    @State private var routes = [RouteItem(name: "Morning Route"), RouteItem(name: "Gym Route")]

    var body: some View {
        List {
            ForEach(routes) { route in
                NavigationLink(route.name) {
                    RouteDetailView(routeName: route.name)
                }
            }
            .onDelete { routes.remove(atOffsets: $0) }
        }
        .toolbar {
            NavigationLink("Add") {
                RouteEditorView(routeName: "", descriptionText: "")
            }
        }
        .navigationTitle("Routes")
    }
}

private struct RouteDetailView: View {
    let routeName: String

    var body: some View {
        Form {
            Section("Route") {
                Text(routeName)
            }
            Section("Actions") {
                Button("Start") {}
                Button("Stop") {}
                Button("Reset") {}
                Button("Share") {}
                NavigationLink("Edit") {
                    RouteEditorView(routeName: routeName, descriptionText: "")
                }
                NavigationLink("Waypoints") {
                    WaypointPickerView()
                }
            }
        }
        .navigationTitle("Route Detail")
    }
}

private struct RouteEditorView: View {
    @State var routeName: String
    @State var descriptionText: String

    var body: some View {
        Form {
            TextField("Route Name", text: $routeName)
            TextField("Description", text: $descriptionText)
            NavigationLink("Add Waypoint") {
                WaypointPickerView()
            }
        }
        .navigationTitle("Route Editor")
    }
}

private struct WaypointPickerView: View {
    @State private var selected = Set<String>()
    private let markerNames = ["Home", "Office", "Gym", "Station"]

    var body: some View {
        List(markerNames, id: \.self, selection: $selected) { name in
            NavigationLink(name) {
                WaypointDetailView(name: name)
            }
        }
        .navigationTitle("Add Waypoint")
    }
}

private struct WaypointDetailView: View {
    let name: String

    var body: some View {
        Form {
            Text("Waypoint: \(name)")
            Text("Media: none")
        }
        .navigationTitle("Waypoint Detail")
    }
}

private struct DevicesManagementView: View {
    var body: some View {
        Form {
            Text("Headphones")
            Text("Bluetooth devices")
            Text("Tracking status")
        }
        .navigationTitle("Devices")
    }
}

private struct HelpAndTutorialsView: View {
    var body: some View {
        List {
            Text("Getting started")
            Text("My Location")
            Text("Around Me and Ahead of Me")
            Text("Markers and Routes")
        }
        .navigationTitle("Help")
    }
}

private struct OfflineBannerDemoView: View {
    @State private var offline = true

    var body: some View {
        VStack(spacing: 12) {
            Toggle("Offline", isOn: $offline)
                .padding(.horizontal)
            if offline {
                Text("Offline: search and nearby data may be limited.")
                    .foregroundStyle(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.orange)
            }
            Spacer()
        }
        .padding(.top)
        .navigationTitle("Offline Banner")
    }
}

private struct SystemDialogsDemoView: View {
    @State private var showDelete = false
    @State private var showPermission = false

    var body: some View {
        Form {
            Button("Show Delete Confirmation") { showDelete = true }
            Button("Show Permission Dialog") { showPermission = true }
        }
        .alert("Delete item?", isPresented: $showDelete) {
            Button("Delete", role: .destructive) {}
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .alert("Enable Location", isPresented: $showPermission) {
            Button("Open Settings") {}
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Location permission is required for maps guidance.")
        }
        .navigationTitle("System Dialogs")
    }
}
