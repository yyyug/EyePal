import SwiftUI
import Intents

enum EyePalUserActivityType {
    static let myLocation = "com.eyepal.activity.my-location"
    static let aroundMe = "com.eyepal.activity.around-me"
    static let aheadOfMe = "com.eyepal.activity.ahead-of-me"
    static let nearbyMarkers = "com.eyepal.activity.nearby-markers"
    static let search = "com.eyepal.activity.search"
    static let streetPreview = "com.eyepal.activity.street-preview"
    static let saveMarker = "com.eyepal.activity.save-marker"
    static let quickDescription = "com.eyepal.activity.quick-description"
    static let detailsDescription = "com.eyepal.activity.details-description"

    static let all = [
        myLocation,
        aroundMe,
        aheadOfMe,
        nearbyMarkers,
        search,
        streetPreview,
        saveMarker,
        quickDescription,
        detailsDescription,
    ]
}

enum EyePalMapAction: Equatable {
    case myLocation
    case aroundMe
    case aheadOfMe
    case nearbyMarkers
    case streetPreview
    case search(String?)
    case saveMarker
    case importMarker(title: String, subtitle: String, lat: Double, lon: Double)
    case importRoute(name: String, notes: String, encodedWaypoints: String)
}

struct EyePalDeepLinkValidationResult: Identifiable, Hashable {
    let id = UUID()
    let sampleURL: String
    let isValid: Bool
    let detail: String
}

enum EyePalTabAction: Equatable {
    case quickDescription
    case detailsDescription
}

@MainActor
final class EyePalAppActionCenter: ObservableObject {
    @Published var pendingMapAction: EyePalMapAction?
    @Published var pendingTabAction: EyePalTabAction?

    func enqueue(_ action: EyePalMapAction) {
        pendingMapAction = action
    }

    func enqueue(_ action: EyePalTabAction) {
        pendingTabAction = action
    }

    func consumeMapAction() -> EyePalMapAction? {
        let action = pendingMapAction
        pendingMapAction = nil
        return action
    }

    func consumeTabAction() -> EyePalTabAction? {
        let action = pendingTabAction
        pendingTabAction = nil
        return action
    }

    func handleIncomingURL(_ url: URL) {
        if let action = mapAction(from: url) {
            enqueue(action)
        }
    }

    func handleContinuationActivity(_ userActivity: NSUserActivity) {
        switch userActivity.activityType {
        case EyePalUserActivityType.myLocation:
            enqueue(.myLocation)
        case EyePalUserActivityType.aroundMe:
            enqueue(.aroundMe)
        case EyePalUserActivityType.aheadOfMe:
            enqueue(.aheadOfMe)
        case EyePalUserActivityType.nearbyMarkers:
            enqueue(.nearbyMarkers)
        case EyePalUserActivityType.search:
            let query = userActivity.userInfo?["query"] as? String
            enqueue(.search(query))
        case EyePalUserActivityType.streetPreview:
            enqueue(.streetPreview)
        case EyePalUserActivityType.saveMarker:
            enqueue(.saveMarker)
        case EyePalUserActivityType.quickDescription:
            enqueue(.quickDescription)
        case EyePalUserActivityType.detailsDescription:
            enqueue(.detailsDescription)
        default:
            break
        }
    }

    func donateActivity(_ type: String, title: String, userInfo: [AnyHashable: Any]? = nil) {
        let activity = NSUserActivity(activityType: type)
        activity.title = title
        activity.isEligibleForSearch = true
        activity.isEligibleForPrediction = true
        activity.isEligibleForPublicIndexing = false
        activity.persistentIdentifier = NSUserActivityPersistentIdentifier(type)
        activity.suggestedInvocationPhrase = title
        activity.userInfo = userInfo
        activity.becomeCurrent()
    }

    func donateCoreShortcuts() {
        let definitions: [(type: String, title: String, phrase: String)] = [
            (EyePalUserActivityType.myLocation, "My Location", "EyePal my location"),
            (EyePalUserActivityType.aroundMe, "Around Me", "EyePal around me"),
            (EyePalUserActivityType.aheadOfMe, "Ahead of Me", "EyePal ahead of me"),
            (EyePalUserActivityType.nearbyMarkers, "Nearby Markers", "EyePal nearby markers"),
            (EyePalUserActivityType.search, "Search", "EyePal search"),
            (EyePalUserActivityType.streetPreview, "Street Preview", "EyePal street preview"),
            (EyePalUserActivityType.saveMarker, "Save Marker", "EyePal save marker"),
            (EyePalUserActivityType.quickDescription, "Quick Description", "EyePal quick description"),
            (EyePalUserActivityType.detailsDescription, "Detail Description", "EyePal detail description"),
        ]

        let shortcuts: [INShortcut] = definitions.compactMap { definition in
            let activity = NSUserActivity(activityType: definition.type)
            activity.title = definition.title
            activity.isEligibleForSearch = true
            activity.isEligibleForPrediction = true
            activity.isEligibleForPublicIndexing = false
            activity.suggestedInvocationPhrase = definition.phrase
            return INShortcut(userActivity: activity)
        }
        INVoiceShortcutCenter.shared.setShortcutSuggestions(shortcuts)
    }

    func deepLinkValidationChecklist() -> [EyePalDeepLinkValidationResult] {
        let samples = [
            "eyepal://marker?title=Pier%2039&subtitle=SF&lat=37.8086&lon=-122.4098",
            "eyepal://search?q=Market%20Street",
            "eyepal://action?type=street-preview",
            "https://via.inclu.si/v1/sharemarker?title=Home&subtitle=Favorite&lat=22.3027&lon=114.1772",
            "eyepal://route?name=Harbor%20Walk&notes=Shared&waypoints=W3sidGl0bGUiOiJTdGFydCIsImxhdCI6MzcuNzc0OSwibG9uIjotMTIyLjQxOTR9LHsidGl0bGUiOiJGaW5pc2giLCJsYXQiOjM3Ljc3NzcsImxvbiI6LTEyMi40MTQ0fV0=",
        ]

        return samples.map { raw in
            guard let url = URL(string: raw) else {
                return EyePalDeepLinkValidationResult(sampleURL: raw, isValid: false, detail: "Invalid URL string")
            }
            if let action = mapAction(from: url) {
                return EyePalDeepLinkValidationResult(sampleURL: raw, isValid: true, detail: String(describing: action))
            }
            return EyePalDeepLinkValidationResult(sampleURL: raw, isValid: false, detail: "No matching action")
        }
    }

    private func mapAction(from url: URL) -> EyePalMapAction? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let host = (components.host ?? "").lowercased()
        let path = components.path.lowercased()
        let items = components.queryItems ?? []

        let markerHostOrPath = host == "marker" || path.contains("sharemarker") || path.contains("marker")
        if markerHostOrPath {
            let title = items.first(where: { $0.name == "title" })?.value ?? "Shared marker"
            let subtitle = items.first(where: { $0.name == "subtitle" })?.value ?? ""
            let lat = Double(items.first(where: { $0.name == "lat" })?.value ?? "")
            let lon = Double(items.first(where: { $0.name == "lon" })?.value ?? "")
            if let lat, let lon {
                return .importMarker(title: title, subtitle: subtitle, lat: lat, lon: lon)
            }
        }

        let routeHostOrPath = host == "route" || path.contains("share-route") || path.contains("route")
        if routeHostOrPath {
            let name = items.first(where: { $0.name == "name" })?.value ?? "Shared Route"
            let notes = items.first(where: { $0.name == "notes" })?.value ?? ""
            let encodedWaypoints = items.first(where: { $0.name == "waypoints" })?.value ?? ""
            if !encodedWaypoints.isEmpty {
                return .importRoute(name: name, notes: notes, encodedWaypoints: encodedWaypoints)
            }
        }

        if host == "search" || path.contains("search") {
            let query = items.first(where: { $0.name == "q" })?.value
            return .search(query)
        }

        if host == "action" {
            let type = (items.first(where: { $0.name == "type" })?.value ?? "").lowercased()
            switch type {
            case "my-location": return .myLocation
            case "around-me": return .aroundMe
            case "ahead-of-me": return .aheadOfMe
            case "nearby-markers": return .nearbyMarkers
            case "street-preview": return .streetPreview
            case "save-marker": return .saveMarker
            default: return nil
            }
        }

        return nil
    }
}

@main
struct EyePalApp: App {
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var openAIStore = OpenAISubscriptionStore()
    @StateObject private var appActionCenter = EyePalAppActionCenter()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(settingsStore)
                .environmentObject(openAIStore)
                .environmentObject(appActionCenter)
                .onOpenURL { url in
                    appActionCenter.handleIncomingURL(url)
                }
                .onContinueUserActivity(EyePalUserActivityType.myLocation) { activity in
                    appActionCenter.handleContinuationActivity(activity)
                }
                .onContinueUserActivity(EyePalUserActivityType.aroundMe) { activity in
                    appActionCenter.handleContinuationActivity(activity)
                }
                .onContinueUserActivity(EyePalUserActivityType.aheadOfMe) { activity in
                    appActionCenter.handleContinuationActivity(activity)
                }
                .onContinueUserActivity(EyePalUserActivityType.nearbyMarkers) { activity in
                    appActionCenter.handleContinuationActivity(activity)
                }
                .onContinueUserActivity(EyePalUserActivityType.search) { activity in
                    appActionCenter.handleContinuationActivity(activity)
                }
                .onContinueUserActivity(EyePalUserActivityType.streetPreview) { activity in
                    appActionCenter.handleContinuationActivity(activity)
                }
                .onContinueUserActivity(EyePalUserActivityType.saveMarker) { activity in
                    appActionCenter.handleContinuationActivity(activity)
                }
                .onContinueUserActivity(EyePalUserActivityType.quickDescription) { activity in
                    appActionCenter.handleContinuationActivity(activity)
                }
                .onContinueUserActivity(EyePalUserActivityType.detailsDescription) { activity in
                    appActionCenter.handleContinuationActivity(activity)
                }
        }
    }
}

extension Notification.Name {
    static let eyePalRequestQuickCapture = Notification.Name("com.eyepal.notification.quick-capture")
    static let eyePalRequestDetailsCapture = Notification.Name("com.eyepal.notification.details-capture")
}
