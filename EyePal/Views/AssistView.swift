import SwiftUI

struct AssistView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var openAIStore: OpenAISubscriptionStore
    @EnvironmentObject private var floorStore: FloorRecordStore
    @State private var pushedFeature: AppFeature?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                assistButton(NSLocalizedString("feature.floorDetection", comment: ""), systemImage: "building.2") {
                    pushedFeature = .floorDetection
                }

                assistButton(NSLocalizedString("feature.lyricPrompter", comment: ""), systemImage: "music.note.list") {
                    pushedFeature = .lyricPrompter
                }

                assistButton(NSLocalizedString("feature.chat", comment: ""), systemImage: "bubble.left.and.bubble.right") {
                    pushedFeature = .chat
                }

                assistButton(NSLocalizedString("tab.settings", comment: ""), systemImage: "gearshape") {
                    pushedFeature = nil
                    showSettings = true
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(NSLocalizedString("tab.assist", comment: ""))
        .navigationDestination(item: $pushedFeature) { feature in
            switch feature {
            case .floorDetection:
                FloorDetectionListView()
                    .environmentObject(floorStore)
            case .lyricPrompter:
                LyricPrompterView()
                    .environmentObject(openAIStore)
            case .chat:
                RealtimeChatView()
            default:
                EmptyView()
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
                    .environmentObject(settingsStore)
                    .environmentObject(openAIStore)
            }
        }
    }

    @State private var showSettings = false

    private func assistButton(_ label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 44)

                Text(label)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 16)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint(NSLocalizedString("vision.showFeaturePage", comment: ""))
    }
}

#Preview {
    AssistView()
        .environmentObject(SettingsStore())
        .environmentObject(OpenAISubscriptionStore())
        .environmentObject(FloorRecordStore())
}