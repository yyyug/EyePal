import SwiftUI

/// Camera preview for any recognition feature.
///
/// Shows the live phone preview layer, or the latest glasses frame when the
/// glasses are the selected source, so every feature that calls this looks the
/// same regardless of where its frames come from.
struct CameraSourcePreviewView: View {
    let pipeline: CameraPipeline
    var ignoreSafeArea = true

    /// The source lives in `UserDefaults`, which SwiftUI does not observe, so the
    /// change notification is what swaps the preview.
    @State private var source = CameraSource.current

    var body: some View {
        Group {
            if source == .glasses {
                GlassesFramePreview()
            } else {
                CameraPreviewView(session: pipeline.session)
            }
        }
        .modifier(PreviewInsets(ignoreSafeArea: ignoreSafeArea))
        .onReceive(NotificationCenter.default.publisher(for: .eyePalCameraSourceDidChange)) { _ in
            source = CameraSource.current
        }
        .onAppear {
            source = CameraSource.current
        }
    }
}

private struct PreviewInsets: ViewModifier {
    let ignoreSafeArea: Bool

    func body(content: Content) -> some View {
        if ignoreSafeArea {
            content.ignoresSafeArea()
        } else {
            content
        }
    }
}

/// Renders frames from the Wearables SDK. A plain `UIImage` rather than a
/// preview layer, because the glasses stream is already decoded.
private struct GlassesFramePreview: View {
    @StateObject private var glasses = MetaGlassesService.shared

    var body: some View {
        ZStack {
            Color.black
            if let frame = glasses.latestFrame {
                Image(uiImage: frame)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel(NSLocalizedString("metaGlasses.preview", comment: ""))
            } else {
                Text(NSLocalizedString("metaGlasses.previewUnavailable", comment: ""))
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
    }
}
