import SwiftUI

/// Settings > Meta Glasses: developer credentials, pairing status and a live
/// preview of the glasses camera.
struct MetaGlassesSettingsView: View {
    @StateObject private var service = MetaGlassesService.shared
    @State private var appID = ""
    @State private var clientToken = ""
    @State private var teamID = ""
    @State private var credentialsSaved = false

    var body: some View {
        Form {
            credentialsSection
            statusSection
            devicesSection
            previewSection
            usageSection
        }
        .navigationTitle(NSLocalizedString("metaGlasses.title", comment: ""))
        .onAppear(perform: loadCredentials)
        .alert(
            NSLocalizedString("common.error", comment: ""),
            isPresented: Binding(get: { service.lastError != nil }, set: { if !$0 { service.clearError() } })
        ) {
            Button(NSLocalizedString("common.ok", comment: "")) { service.clearError() }
        } message: {
            Text(service.lastError ?? "")
        }
    }

    // MARK: - Sections

    private var credentialsSection: some View {
        Section(NSLocalizedString("metaGlasses.credentials", comment: "")) {
            TextField(NSLocalizedString("metaGlasses.appID", comment: ""), text: $appID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField(NSLocalizedString("metaGlasses.clientToken", comment: ""), text: $clientToken)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField(NSLocalizedString("metaGlasses.teamID", comment: ""), text: $teamID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button(NSLocalizedString("metaGlasses.saveCredentials", comment: "")) {
                saveCredentials()
            }
            if credentialsSaved {
                Text(NSLocalizedString("metaGlasses.credentialsSaved", comment: ""))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text(NSLocalizedString("metaGlasses.credentialsHelp", comment: ""))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var statusSection: some View {
        Section(NSLocalizedString("metaGlasses.status", comment: "")) {
            LabeledContent(NSLocalizedString("metaGlasses.sdk", comment: "")) {
                Text(statusText)
                    .foregroundStyle(.secondary)
            }
            LabeledContent(NSLocalizedString("metaGlasses.pairing", comment: "")) {
                Text(pairingText)
                    .foregroundStyle(.secondary)
            }

            if !service.hasCompatibleDevice {
                Text(NSLocalizedString("metaGlasses.needsUpdate", comment: ""))
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if MetaGlassesService.isLinked {
                if service.registrationState == .registered {
                    Button(service.isStreaming
                           ? NSLocalizedString("metaGlasses.stopStream", comment: "")
                           : NSLocalizedString("metaGlasses.startStream", comment: "")) {
                        service.isStreaming ? service.stopStreaming() : service.startStreaming()
                    }
                    Button(NSLocalizedString("metaGlasses.capturePhoto", comment: "")) {
                        service.capturePhoto()
                    }
                    .disabled(!service.isStreaming)
                } else {
                    Button(NSLocalizedString("metaGlasses.pair", comment: "")) {
                        service.startRegistration()
                    }
                    .disabled(!service.isConfigured)
                }
            }
        }
    }

    private var devicesSection: some View {
        Section(NSLocalizedString("metaGlasses.devices", comment: "")) {
            if service.devices.isEmpty {
                Text(NSLocalizedString("metaGlasses.noDevices", comment: ""))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(service.devices) { device in
                    Text(device.name)
                }
            }
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        if service.isStreaming {
            Section(NSLocalizedString("metaGlasses.preview", comment: "")) {
                if let frame = service.latestFrame {
                    Image(uiImage: frame)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(NSLocalizedString("metaGlasses.preview", comment: ""))
                } else {
                    Text(NSLocalizedString("metaGlasses.waitingForFrame", comment: ""))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let photo = service.capturedPhoto {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(NSLocalizedString("metaGlasses.capturedPhoto", comment: ""))
                }
            }
        }
    }

    private var usageSection: some View {
        Section(NSLocalizedString("metaGlasses.usage", comment: "")) {
            Text(NSLocalizedString("metaGlasses.usageDetail", comment: ""))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private var statusText: String {
        if !service.isLinked {
            return NSLocalizedString("metaGlasses.notLinked", comment: "")
        }
        if service.isConfigured {
            return NSLocalizedString("metaGlasses.sdkReady", comment: "")
        }
        return NSLocalizedString("metaGlasses.sdkUnavailable", comment: "")
    }

    private var pairingText: String {
        switch service.registrationState {
        case .notStarted:
            return NSLocalizedString("metaGlasses.notPaired", comment: "")
        case .registering:
            return NSLocalizedString("metaGlasses.pairingInProgress", comment: "")
        case .registered:
            return NSLocalizedString("metaGlasses.paired", comment: "")
        }
    }

    private func loadCredentials() {
        let credentials = MetaGlassesCredentials.current
        appID = credentials.appID
        clientToken = credentials.clientToken
        teamID = credentials.teamID
    }

    private func saveCredentials() {
        MetaGlassesCredentials(
            appID: appID.trimmingCharacters(in: .whitespacesAndNewlines),
            clientToken: clientToken.trimmingCharacters(in: .whitespacesAndNewlines),
            teamID: teamID.trimmingCharacters(in: .whitespacesAndNewlines)
        ).save()
        credentialsSaved = true
    }
}

#Preview {
    NavigationStack {
        MetaGlassesSettingsView()
    }
}
