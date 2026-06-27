import SwiftUI
import UIKit

struct RootTabView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var openAIStore: OpenAISubscriptionStore
    @EnvironmentObject private var appActionCenter: EyePalAppActionCenter
    @StateObject private var floorStore = FloorRecordStore()
    @State private var selectedTabIdentifier = ""

    var body: some View {
        TabView(selection: $selectedTabIdentifier) {
            ForEach(settingsStore.tabFeatures) { feature in
                rootView(for: feature)
                    .tabItem {
                        Label(feature.tabTitle, systemImage: feature.systemImageName)
                    }
                    .tag(feature.rawValue)
            }

            MoreView()
                .environmentObject(floorStore)
                .tabItem {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .tag("more")
        }
        .onAppear {
            settingsStore.setupLogContext(UIApplication.shared)
            if selectedTabIdentifier.isEmpty {
                selectedTabIdentifier = settingsStore.tabFeatures.first?.rawValue ?? "more"
            }
        }
        .onReceive(appActionCenter.$pendingTabAction.compactMap { $0 }) { action in
            switch action {
            case .quickDescription:
                selectedTabIdentifier = AppFeature.quickRecognition.rawValue
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    NotificationCenter.default.post(name: .eyePalRequestQuickCapture, object: nil)
                }
            case .detailsDescription:
                selectedTabIdentifier = AppFeature.detailsRecognition.rawValue
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    NotificationCenter.default.post(name: .eyePalRequestDetailsCapture, object: nil)
                }
            }
            _ = appActionCenter.consumeTabAction()
        }
    }

    @ViewBuilder
    private func rootView(for feature: AppFeature) -> some View {
        switch feature {
        case .floorDetection:
            NavigationStack {
                FloorDetectionListView()
                    .environmentObject(floorStore)
            }
        case .chat:
            RealtimeChatView()
        case .quickRecognition:
            QuickRecognitionView()
        case .detailsRecognition:
            DetailsDescriptionView()
        case .readText:
            ReadTextView()
        case .faces:
            FaceRecognitionView()
        case .lyricPrompter:
            LyricPrompterView()
                .environmentObject(openAIStore)
        }
    }
}

#Preview {
    RootTabView()
        .environmentObject(SettingsStore())
        .environmentObject(OpenAISubscriptionStore())
    .environmentObject(EyePalAppActionCenter())
}
