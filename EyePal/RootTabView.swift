import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @StateObject private var floorStore = FloorRecordStore()

    var body: some View {
        TabView {
            ForEach(settingsStore.tabFeatures) { feature in
                rootView(for: feature)
                    .tabItem {
                        Label(feature.tabTitle, systemImage: feature.systemImageName)
                    }
            }

            MoreView()
                .environmentObject(floorStore)
                .tabItem {
                    Label("More", systemImage: "ellipsis.circle")
                }
        }
    }

    @ViewBuilder
    private func rootView(for feature: AppFeature) -> some View {
        switch feature {
        case .floorDetection:
            FloorDetectionListView()
                .environmentObject(floorStore)
        case .chat:
            RealtimeChatView()
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

#Preview {
    RootTabView()
        .environmentObject(SettingsStore())
        .environmentObject(OpenAISubscriptionStore())
    .environmentObject(EyePalAppActionCenter())
}
