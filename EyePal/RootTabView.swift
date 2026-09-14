import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var openAIStore: OpenAISubscriptionStore
    @EnvironmentObject private var appActionCenter: EyePalAppActionCenter
    @StateObject private var floorStore = FloorRecordStore()
    @State private var selectedTabIdentifier = ""

    private static let simpleVisionTab = "vision"
    private static let simpleAssistTab = "assist"

    var body: some View {
        if settingsStore.uiStyle == .simple {
            simpleTabView
        } else {
            traditionalTabView
        }
    }

    private var simpleTabView: some View {
        TabView(selection: $selectedTabIdentifier) {
            NavigationStack {
                VisionView()
            }
            .environmentObject(floorStore)
            .tabItem {
                Label(NSLocalizedString("tab.vision", comment: ""), systemImage: "eye")
            }
            .tag(Self.simpleVisionTab)

            NavigationStack {
                AssistView()
            }
            .environmentObject(floorStore)
            .tabItem {
                Label(NSLocalizedString("tab.assist", comment: ""), systemImage: "hand.raised.fill")
            }
            .tag(Self.simpleAssistTab)
        }
        .onAppear {
            settingsStore.setupFaceLog()
            if selectedTabIdentifier.isEmpty
                || ![Self.simpleVisionTab, Self.simpleAssistTab].contains(selectedTabIdentifier) {
                selectedTabIdentifier = Self.simpleVisionTab
            }
        }
        .onChange(of: settingsStore.uiStyle) { _, newStyle in
            if newStyle == .simple,
               ![Self.simpleVisionTab, Self.simpleAssistTab].contains(selectedTabIdentifier) {
                selectedTabIdentifier = Self.simpleVisionTab
            }
        }
        .onReceive(appActionCenter.$pendingTabAction.compactMap { $0 }) { action in
            switch action {
            case .quickDescription:
                selectedTabIdentifier = Self.simpleVisionTab
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    NotificationCenter.default.post(name: .eyePalRequestQuickCapture, object: nil)
                }
            case .detailsDescription:
                selectedTabIdentifier = Self.simpleVisionTab
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    NotificationCenter.default.post(name: .eyePalRequestDetailsCapture, object: nil)
                }
            }
            _ = appActionCenter.consumeTabAction()
        }
    }

    private var traditionalTabView: some View {
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
                    Label(NSLocalizedString("tab.more", comment: ""), systemImage: "ellipsis.circle")
                }
                .tag("more")
        }
        .onAppear {
            settingsStore.setupFaceLog()
            if selectedTabIdentifier.isEmpty {
                selectedTabIdentifier = settingsStore.tabFeatures.first?.rawValue ?? "more"
            }
        }
        .onChange(of: settingsStore.uiStyle) { _, newStyle in
            if newStyle != .simple,
               selectedTabIdentifier != Self.simpleVisionTab,
               selectedTabIdentifier != Self.simpleAssistTab,
               !((AppFeature.allCases.map(\.rawValue) + ["more"])).contains(selectedTabIdentifier) {
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