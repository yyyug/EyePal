import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            QuickRecognitionView()
                .tabItem {
                    Label("Quick", systemImage: "camera.viewfinder")
                }

            MapsView()
                .tabItem {
                    Label("Maps", systemImage: "map")
                }

            DetailsDescriptionView()
                .tabItem {
                    Label("Details", systemImage: "sparkles.rectangle.stack")
                }

            ReadTextView()
                .tabItem {
                    Label("Read Text", systemImage: "text.viewfinder")
                }

            FaceRecognitionView()
                .tabItem {
                    Label("Faces", systemImage: "person.crop.rectangle")
                }

            MoreView()
                .tabItem {
                    Label("More", systemImage: "ellipsis.circle")
                }
        }
    }
}

#Preview {
    RootTabView()
        .environmentObject(SettingsStore())
        .environmentObject(OpenAISubscriptionStore())
}
