import SwiftUI
import WebKit

struct DetailsDescriptionView: View {
    private enum ActionChoice: Hashable {
        case takePhoto
        case preset(RecognitionButtonSlot)
    }

    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var openAIStore: OpenAISubscriptionStore
    @StateObject private var viewModel = DetailsDescriptionViewModel()
    @State private var selectedActionIndex = 0
    @State private var showPromptComposer = false
    @State private var promptText = ""

    private var detailsPresetEntries: [(slot: RecognitionButtonSlot, preset: QuickQueryPreset)] {
        RecognitionButtonSlot.allCases
            .map { slot in (slot: slot, preset: settingsStore.detailsPreset(for: slot)) }
            .sorted { lhs, rhs in
                let lhsIsProduct = lhs.preset.title.caseInsensitiveCompare("Product") == .orderedSame
                let rhsIsProduct = rhs.preset.title.caseInsensitiveCompare("Product") == .orderedSame
                if lhsIsProduct != rhsIsProduct {
                    return lhsIsProduct
                }
                return lhs.slot.rawValue < rhs.slot.rawValue
            }
    }

    private var actionChoices: [ActionChoice] {
        [.takePhoto] + detailsPresetEntries.map { .preset($0.slot) }
    }

    private var selectedActionControlStyle: RecognitionActionControlStyle {
        RecognitionActionControlStyle(rawValue: settingsStore.detailsActionControlStyle) ?? .singleAdjustableControl
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                CameraPreviewView(session: viewModel.camera.session)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 12) {
                    if !openAIStore.isSignedIn {
                        Text(NSLocalizedString("details.signInPrompt", comment: ""))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Button(NSLocalizedString("details.signInChatGPT", comment: "")) {
                            openAIStore.beginSignIn()
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        controlPanel
                        descriptionPanel

                        if !viewModel.descriptionText.isEmpty {
                            HStack(spacing: 8) {
                                TextField(NSLocalizedString("details.followUpQuestion", comment: ""), text: $viewModel.followUpQuestion)
                                    .textFieldStyle(.roundedBorder)
                                    .submitLabel(.send)
                                    .onSubmit {
                                        viewModel.submitFollowUp()
                                    }
                                    .accessibilityLabel(NSLocalizedString("details.followUpQuestion", comment: ""))

                                Button(NSLocalizedString("common.send", comment: "")) {
                                    viewModel.submitFollowUp()
                                }
                                .buttonStyle(.bordered)
                .disabled(viewModel.isProcessing || viewModel.followUpQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding()
            }
            .navigationTitle(NSLocalizedString("feature.detailsRecognition", comment: ""))
            .sheet(item: $openAIStore.authRequest, onDismiss: {
                openAIStore.cancelSignIn()
            }) { authRequest in
                OpenAILoginSheet(
                    url: authRequest.url,
                    callbackPrefix: "http://localhost:1455/auth/callback"
                ) { callbackURL in
                    openAIStore.handleAuthorizationCallback(callbackURL)
                }
            }
            .alert(
                NSLocalizedString("details.openAISignInError", comment: ""),
                isPresented: Binding(
                    get: { openAIStore.authErrorMessage != nil },
                    set: { if !$0 { openAIStore.authErrorMessage = nil } }
                )
            ) {
                Button(NSLocalizedString("common.ok", comment: "")) {
                    openAIStore.authErrorMessage = nil
                }
            } message: {
                Text(openAIStore.authErrorMessage ?? "")
            }
            .alert(
                NSLocalizedString("details.descriptionError", comment: ""),
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                )
            ) {
                Button(NSLocalizedString("common.ok", comment: "")) {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .alert(NSLocalizedString("details.takePhotoWithPrompt", comment: ""), isPresented: $showPromptComposer) {
                TextField(NSLocalizedString("details.prompt", comment: ""), text: $promptText)
                Button(NSLocalizedString("common.send", comment: "")) {
                    viewModel.capturePhotoWithPrompt(promptText)
                    promptText = ""
                }
                Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {
                    promptText = ""
                }
            } message: {
                Text(NSLocalizedString("details.promptMessage", comment: ""))
            }
        }
        .onAppear {
            viewModel.bind(openAIStore: openAIStore)
            viewModel.start()
            selectedActionIndex = min(selectedActionIndex, max(actionChoices.count - 1, 0))
        }
        .onDisappear {
            viewModel.stop()
        }
        .onChange(of: openAIStore.isSignedIn) { isSignedIn in
            if !isSignedIn {
                viewModel.retake()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eyePalRequestDetailsCapture)) { _ in
            selectedActionIndex = 0
            performSelectedAction()
        }
        .onChange(of: detailsPresetEntries.map { $0.slot.rawValue }) { _ in
            selectedActionIndex = min(selectedActionIndex, max(actionChoices.count - 1, 0))
        }
    }

    @ViewBuilder
    private var controlPanel: some View {
        switch selectedActionControlStyle {
        case .onScreenButtons:
            buttonGrid
        case .singleAdjustableControl:
            actionSelectorButton
        }
    }

    @ViewBuilder
    private var descriptionPanel: some View {
        if viewModel.capturedPreview != nil || !viewModel.descriptionText.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let preview = viewModel.capturedPreview {
                        Button {
                            viewModel.resendCapturedPhotoInFullResolution()
                        } label: {
                            Image(uiImage: preview)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isProcessing)
                        .accessibilityLabel("Captured image, tap to resend in full resolution")
                    }

                    if !viewModel.descriptionText.isEmpty {
                        Text(viewModel.descriptionText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxHeight: 220)
            .padding(8)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var buttonGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    viewModel.capturePhoto()
                } label: {
                    Label(viewModel.isProcessing ? NSLocalizedString("common.working", comment: "") : NSLocalizedString("common.takePhoto", comment: ""), systemImage: "camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isProcessing)

                Button(NSLocalizedString("details.promptButton", comment: "")) {
                    showPromptComposer = true
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isProcessing)
            }

            HStack(spacing: 12) {
                ForEach(detailsPresetEntries, id: \.slot) { entry in
                    quickPresetButton(
                        title: entry.preset.localizedTitle,
                        systemImage: entry.preset.systemImageName
                    ) {
                        viewModel.capturePresetPhoto(entry.preset)
                    }
                }
            }
        }
    }

    private var actionSelectorButton: some View {
        Button {
            performSelectedAction()
        } label: {
            Label(
                viewModel.isProcessing ? NSLocalizedString("common.working", comment: "") : selectedActionTitle,
                systemImage: selectedActionSymbol
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.isProcessing)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                selectedActionIndex = min(selectedActionIndex + 1, actionChoices.count - 1)
            case .decrement:
                selectedActionIndex = max(selectedActionIndex - 1, 0)
            @unknown default:
                break
            }
        }
        .accessibilityAction(named: Text("Take Photo With Prompt")) {
            selectedActionIndex = 0
            showPromptComposer = true
        }
        .onLongPressGesture(minimumDuration: 0.8) {
            guard selectedAction == .takePhoto else { return }
            showPromptComposer = true
        }
    }

    @ViewBuilder
    private func quickPresetButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title3)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
        }
        .buttonStyle(.bordered)
        .disabled(viewModel.isProcessing)
    }

    private var selectedAction: ActionChoice {
        guard !actionChoices.isEmpty else { return .takePhoto }
        let clampedIndex = min(max(selectedActionIndex, 0), actionChoices.count - 1)
        return actionChoices[clampedIndex]
    }

    private var selectedActionTitle: String {
        switch selectedAction {
        case .takePhoto:
            return NSLocalizedString("common.takePhoto", comment: "")
        case .preset(let slot):
            return settingsStore.detailsPreset(for: slot).title
        }
    }

    private var selectedActionSymbol: String {
        switch selectedAction {
        case .takePhoto:
            return "camera"
        case .preset(let slot):
            return settingsStore.detailsPreset(for: slot).systemImageName
        }
    }

    private func performSelectedAction() {
        switch selectedAction {
        case .takePhoto:
            viewModel.capturePhoto()
        case .preset(let slot):
            viewModel.capturePresetPhoto(settingsStore.detailsPreset(for: slot))
        }
    }
}

private struct OpenAILoginSheet: View {
    let url: URL
    let callbackPrefix: String
    let onCallback: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            OpenAILoginWebView(url: url, callbackPrefix: callbackPrefix) { callbackURL in
                onCallback(callbackURL)
                dismiss()
            }
            .navigationTitle(NSLocalizedString("details.chatGPTSignIn", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("common.close", comment: "")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct OpenAILoginWebView: UIViewRepresentable {
    let url: URL
    let callbackPrefix: String
    let onCallback: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(callbackPrefix: callbackPrefix, onCallback: onCallback)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let callbackPrefix: String
        private let onCallback: (URL) -> Void

        init(callbackPrefix: String, onCallback: @escaping (URL) -> Void) {
            self.callbackPrefix = callbackPrefix
            self.onCallback = onCallback
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if let url = navigationAction.request.url,
               url.absoluteString.hasPrefix(callbackPrefix) {
                onCallback(url)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }
    }
}

#Preview {
    DetailsDescriptionView()
    .environmentObject(SettingsStore())
        .environmentObject(OpenAISubscriptionStore())
}
