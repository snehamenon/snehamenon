import SwiftUI
import ARKit
import AVFoundation

struct FaceScanView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var scanner = FaceScanService()

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                ScanPreview(scanner: scanner)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(MuseTheme.cream.opacity(0.1), lineWidth: 1)
                    )

                switch scanner.phase {
                case .idle, .scanning:
                    scanningOverlay
                case .unavailable:
                    unavailableOverlay
                case .done:
                    EmptyView()
                }
            }
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 12)

            if scanner.phase == .done, let profile = scanner.profile {
                ScanSummaryCard(
                    profile: Binding(
                        get: { scanner.profile ?? profile },
                        set: { scanner.profile = $0 }
                    ),
                    onContinue: { app.advanceToIntent(with: scanner.profile ?? profile) },
                    onRescan: { scanner.start() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom, 16)
        .animation(.spring(duration: 0.4), value: scanner.phase)
        .onAppear { scanner.start() }
        .onDisappear { scanner.stop() }
    }

    private var scanningOverlay: some View {
        VStack {
            Spacer()
            VStack(spacing: 10) {
                if case .scanning(let progress) = scanner.phase {
                    ProgressView(value: progress)
                        .tint(MuseTheme.accent)
                        .frame(width: 180)
                }
                Text("Hold still — reading your features")
                    .font(MuseTheme.bodyFont(14))
                    .foregroundStyle(MuseTheme.cream.opacity(0.9))
                Text(scanner.usesARKit ? "TrueDepth mesh · on-device" : "Vision landmarks · on-device")
                    .font(MuseTheme.bodyFont(11))
                    .foregroundStyle(MuseTheme.muted)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.black.opacity(0.55))
            )
            .padding(.bottom, 24)
        }
    }

    private var unavailableOverlay: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.on.rectangle")
                .font(.system(size: 36))
                .foregroundStyle(MuseTheme.muted)
            Text("Camera unavailable")
                .font(MuseTheme.displayFont(20))
                .foregroundStyle(MuseTheme.cream)
            Text("On the simulator, or if camera access was denied, continue with a sample face profile.")
                .font(MuseTheme.bodyFont(14))
                .foregroundStyle(MuseTheme.muted)
                .multilineTextAlignment(.center)
            Button("Use a sample profile") {
                scanner.useSampleProfile()
            }
            .buttonStyle(PrimaryButtonStyle(isProminent: false))
            .frame(width: 230)
        }
        .padding(24)
    }
}

/// Hosts the live camera view for whichever capture path is active.
private struct ScanPreview: UIViewRepresentable {
    let scanner: FaceScanService

    func makeUIView(context: Context) -> UIView {
        if let arController = scanner.arController {
            return arController.sceneView
        }
        let container = PreviewContainerView()
        container.backgroundColor = UIColor(MuseTheme.surface)
        if let visionController = scanner.visionController {
            let layer = AVCaptureVideoPreviewLayer(session: visionController.session)
            layer.videoGravity = .resizeAspectFill
            container.layer.addSublayer(layer)
            container.previewLayer = layer
        }
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    /// Keeps the preview layer sized with the SwiftUI frame.
    final class PreviewContainerView: UIView {
        var previewLayer: AVCaptureVideoPreviewLayer?

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer?.frame = bounds
        }
    }
}

/// Detected traits, each user-correctable — the scan heuristics are a starting
/// point, not a verdict. Undertone is always self-reported (vein check).
private struct ScanSummaryCard: View {
    @Binding var profile: FaceProfile
    let onContinue: () -> Void
    let onRescan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Here's what I see")
                    .font(MuseTheme.displayFont(20))
                    .foregroundStyle(MuseTheme.cream)
                Spacer()
                Button("Rescan", action: onRescan)
                    .font(MuseTheme.bodyFont(14, weight: .semibold))
                    .foregroundStyle(MuseTheme.accent)
            }
            Text("Tap any trait to correct it — you know your face best.")
                .font(MuseTheme.bodyFont(12))
                .foregroundStyle(MuseTheme.muted)

            traitRow(label: "Face shape", selection: $profile.faceShape)
            traitRow(label: "Eye shape", selection: $profile.eyeShape)
            traitRow(label: "Lips", selection: $profile.lipFullness)

            VStack(alignment: .leading, spacing: 4) {
                traitRow(label: "Undertone", selection: $profile.undertone)
                Text(profile.undertone.hint)
                    .font(MuseTheme.bodyFont(11).italic())
                    .foregroundStyle(MuseTheme.muted)
                    .padding(.leading, 2)
            }

            Button("Looks right — continue", action: onContinue)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 4)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(MuseTheme.surface)
        )
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private func traitRow<T: CaseIterable & Identifiable & RawRepresentable>(
        label: String,
        selection: Binding<T>
    ) -> some View where T.RawValue == String, T.AllCases: RandomAccessCollection {
        HStack {
            Text(label)
                .font(MuseTheme.bodyFont(15))
                .foregroundStyle(MuseTheme.cream.opacity(0.9))
            Spacer()
            Menu {
                ForEach(T.allCases) { option in
                    Button(option.rawValue.capitalized) {
                        selection.wrappedValue = option
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selection.wrappedValue.rawValue.capitalized)
                        .font(MuseTheme.bodyFont(15, weight: .semibold))
                        .foregroundStyle(MuseTheme.accent)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11))
                        .foregroundStyle(MuseTheme.muted)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
