import SwiftUI

enum EyePalUserActivityType {
    static let myLocation = "com.eyepal.activity.my-location"
    static let aroundMe = "com.eyepal.activity.around-me"
    static let aheadOfMe = "com.eyepal.activity.ahead-of-me"
    static let nearbyMarkers = "com.eyepal.activity.nearby-markers"
    static let search = "com.eyepal.activity.search"
    static let streetPreview = "com.eyepal.activity.street-preview"

    static let all = [
        myLocation,
        aroundMe,
        aheadOfMe,
        nearbyMarkers,
        search,
        streetPreview,
    ]
}

enum EyePalMapAction: Equatable {
    case myLocation
    case aroundMe
    case aheadOfMe
    case nearbyMarkers
    case streetPreview
    case search(String?)
    case importMarker(title: String, subtitle: String, lat: Double, lon: Double)
}

@MainActor
final class EyePalAppActionCenter: ObservableObject {
    @Published var pendingMapAction: EyePalMapAction?

    func enqueue(_ action: EyePalMapAction) {
        pendingMapAction = action
    }

    func consumeMapAction() -> EyePalMapAction? {
        let action = pendingMapAction
        pendingMapAction = nil
        return action
    }

    func handleIncomingURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return
        }
        let host = (components.host ?? "").lowercased()
        let items = components.queryItems ?? []

        if host == "marker" {
            let title = items.first(where: { $0.name == "title" })?.value ?? "Shared marker"
            let subtitle = items.first(where: { $0.name == "subtitle" })?.value ?? ""
            let lat = Double(items.first(where: { $0.name == "lat" })?.value ?? "")
            let lon = Double(items.first(where: { $0.name == "lon" })?.value ?? "")
            if let lat, let lon {
                enqueue(.importMarker(title: title, subtitle: subtitle, lat: lat, lon: lon))
            }
            return
        }

        if host == "search" {
            let query = items.first(where: { $0.name == "q" })?.value
            enqueue(.search(query))
            return
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
        default:
            break
        }
    }

    func donateActivity(_ type: String, title: String, userInfo: [AnyHashable: Any]? = nil) {
        let activity = NSUserActivity(activityType: type)
        activity.title = title
        activity.isEligibleForSearch = true
        activity.isEligibleForPrediction = true
        activity.persistentIdentifier = NSUserActivityPersistentIdentifier(type)
        activity.userInfo = userInfo
        activity.becomeCurrent()
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
        }
    }
}
