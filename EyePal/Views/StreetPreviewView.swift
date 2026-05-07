import SwiftUI
import CoreLocation
import MapKit

/// Street Preview: Audio-based virtual localization experience
struct StreetPreviewView: View {
    @State private var selectedLocation: CLLocation?
    @State private var searchText: String = ""
    @State private var deviceHeading: Double = 0.0
    @State private var isPlaying: Bool = false
    @StateObject private var deviceHeadingProvider = DeviceMotionProvider()
    @StateObject private var headingBridge = StreetPreviewHeadingBridge()
    @State private var headphoneHeadingProvider: HeadphoneMotionProvider?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Location Search
                HStack {
                    Image(systemName: "mappin.circle")
                        .foregroundStyle(.blue)
                    
                    TextField("Enter location address", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.search)
                        .onSubmit {
                            geocodeLocation(searchText)
                        }
                }
                .padding()
                
                if let location = selectedLocation {
                    VStack(spacing: 12) {
                        // Location Info
                        VStack(alignment: .leading, spacing: 4) {
                            Text("📍 Location")
                                .font(.headline)
                            Text(String(format: "%.4f°, %.4f°", location.coordinate.latitude, location.coordinate.longitude))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        
                        // Virtual Heading Compass
                        VStack(spacing: 12) {
                            Text("🧭 Your Heading: \(Int(deviceHeading))°")
                                .font(.headline)
                            
                            HStack(spacing: 12) {
                                Button {
                                    rotateHeading(by: -15)
                                } label: {
                                    Label("Left", systemImage: "arrow.left")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                
                                Button {
                                    resetHeading()
                                } label: {
                                    Image(systemName: "compass.drawing")
                                }
                                .buttonStyle(.bordered)
                                
                                Button {
                                    rotateHeading(by: 15)
                                } label: {
                                    Label("Right", systemImage: "arrow.right")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }
                            
                            // Audio Cue Status
                            if isPlaying {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Playing audio cue...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        
                        // Controls
                        Button(action: playAudioCue) {
                            Label("Play Audio Cue", systemImage: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isPlaying)
                        
                        Spacer()
                    }
                    .padding()
                }
                
                Spacer()
            }
            .navigationTitle("Street Preview")
            .accessibilityLabel("Street Preview")
            .accessibilityHint("Explore a location's soundscape using audio cues")
            .accessibilityAction(named: Text("Rotate Left")) {
                rotateHeading(by: -15)
                playAudioCue()
            }
            .accessibilityAction(named: Text("Rotate Right")) {
                rotateHeading(by: 15)
                playAudioCue()
            }
        }
        .onAppear {
            startHeadingUpdates()
        }
        .onDisappear {
            stopHeadingUpdates()
        }
        .onReceive(headingBridge.$heading.compactMap { $0 }) { heading in
            deviceHeading = heading.value
        }
    }
    
    // MARK: - Methods
    
    private func geocodeLocation(_ address: String) {
        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(address) { placemarks, error in
            if let placemark = placemarks?.first,
               let location = placemark.location {
                selectedLocation = location
                deviceHeading = 0.0
            }
        }
    }
    
    private func rotateHeading(by degrees: Double) {
        deviceHeading = (deviceHeading + degrees).truncatingRemainder(dividingBy: 360.0)
        if deviceHeading < 0 {
            deviceHeading += 360.0
        }
    }
    
    private func resetHeading() {
        deviceHeading = 0.0
    }
    
    private func playAudioCue() {
        guard selectedLocation != nil else { return }
        
        isPlaying = true
        
        // Determine spatial direction based on heading
        let spatialDir: SpatialDirection = {
            let heading = deviceHeading
            if heading >= 315 || heading < 45 {
                return .ahead
            } else if heading >= 45 && heading < 135 {
                return .right
            } else if heading >= 135 && heading < 225 {
                return .behind
            } else {
                return .left
            }
        }()
        
        // Play spatial audio cue
        HRTFAudioEngine.shared.playDirectionalCue(direction: spatialDir)
        HRTFAudioEngine.shared.updateListenerHeading(deviceHeading)
        
        // Simulate audio playback duration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isPlaying = false
        }
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
private final class StreetPreviewHeadingBridge: NSObject, ObservableObject, UserHeadingProviderDelegate {
    @Published var heading: HeadingValue?

    func userHeadingProvider(_ provider: UserHeadingProvider, didUpdateUserHeading heading: HeadingValue?) {
        self.heading = heading
    }
}

#Preview {
    StreetPreviewView()
}
