import SwiftUI

struct TutorialView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        if let look = app.selectedLook {
            TutorialSessionView(look: look)
        } else {
            // Shouldn't happen; recover gracefully.
            VStack(spacing: 12) {
                Text("No look selected")
                    .font(MuseTheme.displayFont(20))
                    .foregroundStyle(MuseTheme.cream)
                Button("Back to looks") { app.stage = .looks }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(width: 220)
            }
        }
    }
}

private struct TutorialSessionView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var viewModel: TutorialViewModel
    @State private var showCamera = false

    init(look: Look) {
        _viewModel = StateObject(wrappedValue: TutorialViewModel(look: look))
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if viewModel.isFinished {
                finishView
            } else if let step = viewModel.currentStep {
                stepView(step)
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraImagePicker(image: $viewModel.afterSelfie)
                .ignoresSafeArea()
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    app.stage = .looks
                } label: {
                    Label("Looks", systemImage: "chevron.left")
                        .font(MuseTheme.bodyFont(15, weight: .semibold))
                        .foregroundStyle(MuseTheme.accent)
                }
                Spacer()
                Text(viewModel.look.name)
                    .font(MuseTheme.displayFont(19))
                    .foregroundStyle(MuseTheme.cream)
                Spacer()
                Label("Looks", systemImage: "chevron.left")
                    .font(MuseTheme.bodyFont(15, weight: .semibold))
                    .hidden()
            }

            if !viewModel.isFinished {
                VStack(spacing: 4) {
                    ProgressView(value: viewModel.progress)
                        .tint(MuseTheme.accent)
                    Text("Step \(viewModel.stepIndex + 1) of \(viewModel.look.steps.count)")
                        .font(MuseTheme.bodyFont(12))
                        .foregroundStyle(MuseTheme.muted)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private func stepView(_ step: TutorialStep) -> some View {
        VStack(spacing: 12) {
            faceVisual(for: step)
                .padding(.top, 10)

            ScrollView {
                StepCard(step: step)
                    .padding(.horizontal, 20)
                    .id(step.id) // reset scroll per step
            }

            HStack(spacing: 12) {
                Button {
                    viewModel.previous()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 54, height: 54)
                        .background(Circle().fill(MuseTheme.surfaceRaised))
                        .foregroundStyle(viewModel.stepIndex == 0 ? MuseTheme.muted : MuseTheme.cream)
                }
                .disabled(viewModel.stepIndex == 0)

                Button(viewModel.isLastStep ? "Finish look" : "Next step") {
                    viewModel.next()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .animation(.spring(duration: 0.35), value: viewModel.stepIndex)
    }

    /// Live mirrored camera with the zone painted in the look's color, on a real
    /// device; the stylized diagram is the simulator / no-camera fallback.
    @ViewBuilder
    private func faceVisual(for step: TutorialStep) -> some View {
        if LiveTutorialFaceView.isSupported {
            LiveTutorialFaceView(zone: step.zone, tint: tintColor(for: viewModel.stepIndex))
                .frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(MuseTheme.cream.opacity(0.1), lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    Text(step.zone.displayName)
                        .font(MuseTheme.bodyFont(12, weight: .semibold))
                        .foregroundStyle(MuseTheme.background)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(tintColor(for: viewModel.stepIndex)))
                        .padding(12)
                }
                .padding(.horizontal, 20)
        } else {
            FaceZoneOverlay(zone: step.zone)
                .frame(maxHeight: 230)
        }
    }

    /// Tie the overlay color to the look's palette so it reads as the actual
    /// product (e.g. gold lids for a golden look), varying per step.
    private func tintColor(for index: Int) -> Color {
        let palette = viewModel.look.paletteHex
        guard !palette.isEmpty else { return MuseTheme.accent }
        return Color(hex: palette[index % palette.count])
    }

    private var finishView: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("✨")
                .font(.system(size: 56))
            Text("Look complete")
                .font(MuseTheme.displayFont(30))
                .foregroundStyle(MuseTheme.cream)
            Text("\(viewModel.look.name) — \(viewModel.look.steps.count) steps, done.")
                .font(MuseTheme.bodyFont(15))
                .foregroundStyle(MuseTheme.muted)

            if let selfie = viewModel.afterSelfie {
                Image(uiImage: selfie)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 180, height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(MuseTheme.accent.opacity(0.6), lineWidth: 2)
                    )
            } else if CameraImagePicker.isAvailable {
                Button {
                    showCamera = true
                } label: {
                    Label("Capture the after", systemImage: "camera")
                }
                .buttonStyle(PrimaryButtonStyle(isProminent: false))
                .frame(width: 240)
            }

            Spacer()

            VStack(spacing: 10) {
                Button("Back to my looks") { app.stage = .looks }
                    .buttonStyle(PrimaryButtonStyle())
                Button("Start over") { app.restart() }
                    .buttonStyle(PrimaryButtonStyle(isProminent: false))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }
}
