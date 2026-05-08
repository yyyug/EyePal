import SwiftUI
import CoreLocation
import MapKit

/// Street Preview with search, heading-aware movement, and Soundscape-style around/ahead callouts.
struct StreetPreviewView: View {
    let initialLocation: CLLocation?
    let initialHeading: Double?

    @EnvironmentObject private var settingsStore: SettingsStore
    @StateObject private var viewModel = StreetPreviewViewModel()
    @StateObject private var deviceHeadingProvider = DeviceMotionProvider()
    @StateObject private var headingBridge = StreetPreviewHeadingBridge()
    @State private var headphoneHeadingProvider: HeadphoneMotionProvider?

    init(initialLocation: CLLocation? = nil, initialHeading: Double? = nil) {
        self.initialLocation = initialLocation
        self.initialHeading = initialHeading
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                searchCard
                headingCard
                movementCard
                calloutCard
                nearbyCard
            }
            .padding()
        }
        .navigationTitle("Street Preview")
        .onAppear {
            viewModel.configure(
                initialLocation: initialLocation,
                initialHeading: initialHeading,
                includeUnnamedRoads: settingsStore.mapsPreviewIncludeUnnamedRoads,
                metricUnits: settingsStore.mapsMetricUnits
            )
            startHeadingUpdates()
        }
        .onDisappear {
            stopHeadingUpdates()
        }
        .onReceive(headingBridge.$heading.compactMap { $0 }) { heading in
            viewModel.updateHeading(heading.value)
        }
    }

    private var searchCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Search address or place", text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .onSubmit { viewModel.searchLocation() }

                Button("Search") {
                    viewModel.searchLocation()
                }
                .buttonStyle(.borderedProminent)
            }

            Text(viewModel.statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var headingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Heading")
                .font(.headline)
            Text("Facing \(viewModel.facingDirectionLabel), \(Int(viewModel.heading.rounded()))°")
                .font(.subheadline)

            if let location = viewModel.location {
                Text(String(format: "Lat %.5f, Lon %.5f", location.coordinate.latitude, location.coordinate.longitude))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var movementCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Move")
                .font(.headline)

            HStack(spacing: 10) {
                Button("Back 30m") { viewModel.moveBackward() }
                    .buttonStyle(.bordered)
                Button("Forward 30m") { viewModel.moveForward() }
                    .buttonStyle(.borderedProminent)
            }

            HStack(spacing: 10) {
                Button("Turn Left") { viewModel.turnLeft() }
                    .buttonStyle(.bordered)
                Button("Turn Right") { viewModel.turnRight() }
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var calloutCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Callouts")
                .font(.headline)

            HStack(spacing: 10) {
                Button("My Location") { viewModel.calloutMyLocation() }
                    .buttonStyle(.bordered)
                Button("Around Me") { viewModel.calloutAroundMe() }
                    .buttonStyle(.bordered)
                Button("Ahead of Me") { viewModel.calloutAheadOfMe() }
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var nearbyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nearby Places")
                .font(.headline)

            if viewModel.nearby.isEmpty {
                Text("No nearby places yet. Search or move to refresh.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.nearby.prefix(8)) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                        Text(item.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func startHeadingUpdates() {
        if #available(iOS 14.4, *) {
            let headphoneProvider = HeadphoneMotionProvider()
            if headphoneProvider.isHeadphoneMotionAvailable {
                headphoneProvider.delegate = headingBridge
                headphoneProvider.startUserHeadingUpdates()
                headphoneHeadingProvider = headphoneProvider
                return
            }
        }
        deviceHeadingProvider.delegate = headingBridge
        deviceHeadingProvider.startUserHeadingUpdates()
    }

    private func stopHeadingUpdates() {
        headphoneHeadingProvider?.stopUserHeadingUpdates()
        headphoneHeadingProvider = nil
        deviceHeadingProvider.stopUserHeadingUpdates()
    }
}

@MainActor
private final class StreetPreviewViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var statusText = "Search a location to start Street Preview."
    @Published var location: CLLocation?
    @Published var heading: Double = 0
    @Published var nearby: [PreviewPOI] = []

    private let announcer = AccessibilityAnnouncementCenter()
    private var includeUnnamedRoads = false
    private var metricUnits = true

    var facingDirectionLabel: String {
        directionLabel(heading)
    }

    func configure(initialLocation: CLLocation?, initialHeading: Double?, includeUnnamedRoads: Bool, metricUnits: Bool) {
        self.includeUnnamedRoads = includeUnnamedRoads
        self.metricUnits = metricUnits
        if let initialLocation {
            location = initialLocation
            statusText = "Street Preview ready at selected location."
            loadNearbyPOIs()
        }
        if let initialHeading {
            heading = normalize(initialHeading)
            HRTFAudioEngine.shared.updateListenerHeading(heading)
        }
    }

    func updateHeading(_ newHeading: Double) {
        heading = normalize(newHeading)
        HRTFAudioEngine.shared.updateListenerHeading(heading)
    }

    func searchLocation() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        statusText = "Searching \(query)..."
        CLGeocoder().geocodeAddressString(query) { [weak self] placemarks, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let loc = placemarks?.first?.location {
                    self.location = loc
                    self.statusText = "Loaded \(query)."
                    self.announcer.announce("Street preview loaded for \(query)", minimumInterval: 0)
                    self.loadNearbyPOIs()
                } else {
                    self.statusText = "Search failed. \(error?.localizedDescription ?? "Try another place.")"
                }
            }
        }
    }

    func moveForward() {
        move(distanceMeters: 30)
    }

    func moveBackward() {
        move(distanceMeters: -30)
    }

    func turnLeft() {
        updateHeading(heading - 30)
        announcer.announce("Turned left. Facing \(facingDirectionLabel)", minimumInterval: 0)
    }

    func turnRight() {
        updateHeading(heading + 30)
        announcer.announce("Turned right. Facing \(facingDirectionLabel)", minimumInterval: 0)
    }

    func calloutMyLocation() {
        guard let location else {
            announcer.announce("Location unavailable.", minimumInterval: 0)
            return
        }
        let text = String(
            format: "My location %.5f, %.5f. Facing %@.",
            location.coordinate.latitude,
            location.coordinate.longitude,
            facingDirectionLabel
        )
        HRTFAudioEngine.shared.playSFX(.calloutStart)
        announcer.announce(text, minimumInterval: 0)
    }

    func calloutAroundMe() {
        guard let location else {
            announcer.announce("Around Me unavailable.", minimumInterval: 0)
            return
        }

        if nearby.isEmpty {
            loadNearbyPOIs {
                self.calloutAroundMe()
            }
            return
        }

        HRTFAudioEngine.shared.playSFX(.calloutStart)
        for poi in nearby.prefix(6) {
            let relative = normalizedRelativeAngle(targetBearing: poi.bearing, facing: heading)
            playSpatialCue(relative)
            announcer.announce("\(poi.title), \(poi.distanceLabel(metricUnits: metricUnits)), \(relativeDirectionLabel(relative)).", minimumInterval: 0)
        }
        HRTFAudioEngine.shared.playSFX(.calloutEnd)
        _ = location
    }

    func calloutAheadOfMe() {
        guard location != nil else {
            announcer.announce("Ahead of Me unavailable.", minimumInterval: 0)
            return
        }

        if nearby.isEmpty {
            loadNearbyPOIs {
                self.calloutAheadOfMe()
            }
            return
        }

        let frontal = nearby.filter { abs(normalizedRelativeAngle(targetBearing: $0.bearing, facing: heading)) <= 70 }
        let targets = frontal.isEmpty ? nearby : frontal

        HRTFAudioEngine.shared.playSFX(.calloutStart)
        for poi in targets.prefix(4) {
            let relative = normalizedRelativeAngle(targetBearing: poi.bearing, facing: heading)
            playSpatialCue(relative)
            announcer.announce("\(poi.title), \(poi.distanceLabel(metricUnits: metricUnits)), \(relativeDirectionLabel(relative)).", minimumInterval: 0)
        }
        HRTFAudioEngine.shared.playSFX(.calloutEnd)
    }

    private func move(distanceMeters: Double) {
        guard let location else {
            announcer.announce("Search a location first.", minimumInterval: 0)
            return
        }

        let shifted = destinationPoint(
            lat: location.coordinate.latitude,
            lon: location.coordinate.longitude,
            bearing: heading,
            distanceMeters: distanceMeters
        )
        self.location = CLLocation(latitude: shifted.lat, longitude: shifted.lon)
        statusText = "Moved \(Int(abs(distanceMeters))) meters."
        loadNearbyPOIs()
    }

    private func loadNearbyPOIs(onComplete: (() -> Void)? = nil) {
        guard let location else { return }
        let request = MKLocalPointsOfInterestRequest(center: location.coordinate, radius: 300)
        let search = MKLocalSearch(request: request)

        search.start { [weak self] response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let response {
                    let mapped = response.mapItems.compactMap { item -> PreviewPOI? in
                        let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        if !self.includeUnnamedRoads && name.isEmpty {
                            return nil
                        }
                        let itemLoc = item.placemark.location ?? CLLocation(latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude)
                        let distance = location.distance(from: itemLoc)
                        let bearing = self.bearingBetween(from: location, to: itemLoc)
                        let category = self.categoryText(from: item)
                        let title = name.isEmpty ? category : name
                        return PreviewPOI(
                            id: item.placemark.coordinate.latitude.description + item.placemark.coordinate.longitude.description + title,
                            title: title,
                            category: category,
                            distanceMeters: Int(distance.rounded()),
                            bearing: bearing
                        )
                    }

                    self.nearby = mapped.sorted { $0.distanceMeters < $1.distanceMeters }
                    self.statusText = self.nearby.isEmpty ? "No nearby places." : "Loaded \(self.nearby.count) nearby places."
                } else {
                    self.nearby = []
                    self.statusText = "Nearby lookup failed. \(error?.localizedDescription ?? "")"
                }
                onComplete?()
            }
        }
    }

    private func categoryText(from item: MKMapItem) -> String {
        if item.pointOfInterestCategory == .publicTransport { return "bus stop" }
        if item.pointOfInterestCategory == .airport { return "airport" }
        if item.pointOfInterestCategory == .parking { return "parking" }
        if item.pointOfInterestCategory == .hospital { return "hospital" }
        if item.pointOfInterestCategory == .school { return "school" }
        if item.pointOfInterestCategory == .atm { return "atm" }
        if item.pointOfInterestCategory == .fireStation { return "fire station" }
        if item.pointOfInterestCategory == .restaurant { return "restaurant" }
        if item.pointOfInterestCategory == .cafe { return "cafe" }
        if item.pointOfInterestCategory == .park { return "park" }
        if item.pointOfInterestCategory == .hotel { return "hotel" }

        // Handle category variants across SDK versions without referencing unavailable static symbols.
        let rawCategory = item.pointOfInterestCategory?.rawValue.lowercased() ?? ""
        let name = item.name?.lowercased() ?? ""
        let combined = "\(rawCategory) \(name)"

        if combined.contains("store") || combined.contains("shop") || combined.contains("mall") || combined.contains("market") {
            return "store"
        }
        if combined.contains("pharmacy") {
            return "pharmacy"
        }
        if combined.contains("bank") {
            return "bank"
        }
        if combined.contains("library") {
            return "library"
        }
        if combined.contains("station") {
            return "station"
        }
        if combined.contains("museum") {
            return "museum"
        }
        if combined.contains("theater") || combined.contains("cinema") {
            return "theater"
        }
        if combined.contains("building") || combined.contains("tower") {
            return "building"
        }
        return "place"
    }

    private func normalize(_ value: Double) -> Double {
        var result = value.truncatingRemainder(dividingBy: 360)
        if result < 0 { result += 360 }
        return result
    }

    private func directionLabel(_ bearing: Double) -> String {
        switch bearing {
        case 337.5...360, 0..<22.5: return "north"
        case 22.5..<67.5: return "north-east"
        case 67.5..<112.5: return "east"
        case 112.5..<157.5: return "south-east"
        case 157.5..<202.5: return "south"
        case 202.5..<247.5: return "south-west"
        case 247.5..<292.5: return "west"
        default: return "north-west"
        }
    }

    private func relativeDirectionLabel(_ relativeAngle: Double) -> String {
        let absAngle = abs(relativeAngle)
        if absAngle <= 18 { return "ahead" }
        if absAngle <= 65 { return relativeAngle < 0 ? "ahead to your left" : "ahead to your right" }
        if absAngle <= 120 { return relativeAngle < 0 ? "to your left" : "to your right" }
        return "behind"
    }

    private func playSpatialCue(_ relativeAngle: Double) {
        let absAngle = abs(relativeAngle)
        if absAngle <= 18 {
            HRTFAudioEngine.shared.playDirectionalCue(direction: .ahead)
        } else if absAngle <= 120 {
            HRTFAudioEngine.shared.playDirectionalCue(direction: relativeAngle < 0 ? .left : .right)
        } else {
            HRTFAudioEngine.shared.playDirectionalCue(direction: .behind)
        }
    }

    private func normalizedRelativeAngle(targetBearing: Double, facing: Double) -> Double {
        var relative = (targetBearing - facing).truncatingRemainder(dividingBy: 360)
        if relative > 180 { relative -= 360 }
        if relative < -180 { relative += 360 }
        return relative
    }

    private func bearingBetween(from: CLLocation, to: CLLocation) -> Double {
        let lat1 = from.coordinate.latitude * .pi / 180
        let lon1 = from.coordinate.longitude * .pi / 180
        let lat2 = to.coordinate.latitude * .pi / 180
        let lon2 = to.coordinate.longitude * .pi / 180
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let radians = atan2(y, x)
        let degrees = radians * 180 / .pi
        return normalize(degrees)
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
}

private struct PreviewPOI: Identifiable {
    let id: String
    let title: String
    let category: String
    let distanceMeters: Int
    let bearing: Double

    var subtitle: String {
        "\(category) • \(distanceMeters)m"
    }

    func distanceLabel(metricUnits: Bool) -> String {
        if metricUnits {
            return distanceMeters <= 15 ? "close by" : "about \(distanceMeters) meters"
        }
        let feet = max(1, Int((Double(distanceMeters) * 3.28084).rounded()))
        return feet <= 40 ? "close by" : "about \(feet) feet"
    }
}

@MainActor
private final class StreetPreviewHeadingBridge: NSObject, ObservableObject, @preconcurrency UserHeadingProviderDelegate {
    @Published var heading: HeadingValue?

    func userHeadingProvider(_ provider: UserHeadingProvider, didUpdateUserHeading heading: HeadingValue?) {
        self.heading = heading
    }
}

#Preview {
    StreetPreviewView()
        .environmentObject(SettingsStore())
}
