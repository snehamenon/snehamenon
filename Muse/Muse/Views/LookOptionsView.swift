import SwiftUI

struct LookOptionsView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var viewModel = LooksViewModel()
    @State private var selectedIndex = 0
    @State private var showDetail = false

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                loadingView
            case .failed(let message):
                failureView(message)
            case .loaded:
                if MakeupPreviewView.isSupported {
                    liveSelector
                } else {
                    cardsView
                }
            }
        }
        .task {
            if app.looks.isEmpty {
                await viewModel.generate(into: app)
            } else {
                viewModel.adoptExistingLooks()
            }
        }
    }

    private var safeIndex: Int {
        min(selectedIndex, max(app.looks.count - 1, 0))
    }

    // MARK: - Live try-on selector (real device)

    private var liveSelector: some View {
        let look = app.looks[safeIndex]
        return ZStack {
            MakeupPreviewView(zones: Self.previewZones(for: look))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                selectorTopBar(look)
                Spacer()
                selectorBottomControls(look)
            }
        }
        .sheet(isPresented: $showDetail) {
            LookDetailSheet(look: look)
                .presentationDetents([.medium, .large])
        }
    }

    private func selectorTopBar(_ look: Look) -> some View {
        HStack {
            Button {
                app.looks = []
                app.stage = .intent
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(MuseTheme.cream)
                    .padding(10)
                    .background(Circle().fill(.black.opacity(0.4)))
            }
            Spacer()
            Text("Try a look on")
                .font(MuseTheme.bodyFont(13, weight: .semibold))
                .foregroundStyle(MuseTheme.cream)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(.black.opacity(0.4)))
            Spacer()
            Button {
                showDetail = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(MuseTheme.cream)
                    .padding(8)
                    .background(Circle().fill(.black.opacity(0.4)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func selectorBottomControls(_ look: Look) -> some View {
        VStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(look.name)
                    .font(MuseTheme.displayFont(26))
                    .foregroundStyle(MuseTheme.cream)
                Text(look.tagline)
                    .font(MuseTheme.bodyFont(13).italic())
                    .foregroundStyle(MuseTheme.cream.opacity(0.85))
            }
            .shadow(color: .black.opacity(0.6), radius: 6)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(app.looks.enumerated()), id: \.offset) { index, option in
                        Button {
                            withAnimation(.spring(duration: 0.3)) { selectedIndex = index }
                        } label: {
                            HStack(spacing: 8) {
                                PaletteSwatch(hexColors: option.paletteHex, dotSize: 14)
                                Text(option.name)
                                    .font(MuseTheme.bodyFont(14, weight: index == safeIndex ? .semibold : .regular))
                            }
                            .foregroundStyle(index == safeIndex ? MuseTheme.background : MuseTheme.cream)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(
                                Capsule().fill(index == safeIndex ? AnyShapeStyle(MuseTheme.cream) : AnyShapeStyle(.black.opacity(0.45)))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }

            Button("Start this look · \(look.steps.count) steps") {
                app.startTutorial(with: look)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 18)
        .padding(.top, 12)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    /// One painted zone per face region for the preview — last step per zone
    /// wins (so the dramatic lid color beats the primer), and we skip full-face
    /// base since foundation has little visible signal in a stylized preview.
    static func previewZones(for look: Look) -> [MakeupZone] {
        var byZone: [FaceZone: MakeupZone] = [:]
        for step in look.steps where step.zone != .fullFace {
            let color = step.colorHex ?? look.paletteHex.first ?? "#C9A0C4"
            byZone[step.zone] = MakeupZone(zone: step.zone, colorHex: color, finish: step.makeupFinish)
        }
        return Array(byZone.values)
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "wand.and.stars")
                .font(.system(size: 40))
                .foregroundStyle(MuseTheme.accent)
                .symbolEffect(.pulse, options: .repeating)
            if case .loading(let message) = viewModel.state {
                Text(message)
                    .font(MuseTheme.displayFont(19))
                    .foregroundStyle(MuseTheme.cream)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                    .animation(.easeInOut, value: message)
            } else {
                Text("Warming up…")
                    .font(MuseTheme.displayFont(19))
                    .foregroundStyle(MuseTheme.cream)
            }
            Text(app.isMockMode ? "Demo mode" : "Directed by Claude")
                .font(MuseTheme.bodyFont(12))
                .foregroundStyle(MuseTheme.muted)
            Spacer()
        }
        .padding(32)
    }

    private func failureView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34))
                .foregroundStyle(MuseTheme.accent)
            Text("That didn't land")
                .font(MuseTheme.displayFont(22))
                .foregroundStyle(MuseTheme.cream)
            Text(message)
                .font(MuseTheme.bodyFont(14))
                .foregroundStyle(MuseTheme.muted)
                .multilineTextAlignment(.center)
            Button("Try again") {
                Task { await viewModel.generate(into: app) }
            }
            .buttonStyle(PrimaryButtonStyle())
            Button("Continue with sample looks") {
                Task { await viewModel.fallBackToMock(into: app) }
            }
            .buttonStyle(PrimaryButtonStyle(isProminent: false))
            Spacer()
        }
        .padding(28)
    }

    // MARK: - Card fallback (simulator / no camera)

    private var cardsView: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    app.looks = []
                    app.stage = .intent
                } label: {
                    Label("Brief", systemImage: "chevron.left")
                        .font(MuseTheme.bodyFont(15, weight: .semibold))
                        .foregroundStyle(MuseTheme.accent)
                }
                Spacer()
                Text("Your looks")
                    .font(MuseTheme.displayFont(20))
                    .foregroundStyle(MuseTheme.cream)
                Spacer()
                Label("Brief", systemImage: "chevron.left")
                    .font(MuseTheme.bodyFont(15, weight: .semibold))
                    .hidden()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            TabView {
                ForEach(app.looks) { look in
                    LookCard(look: look) {
                        app.startTutorial(with: look)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
    }
}

/// Tap-through detail: the "why it suits you" rationale and weather notes that
/// used to live on the card, surfaced on demand from the live selector.
private struct LookDetailSheet: View {
    let look: Look

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(look.name)
                        .font(MuseTheme.displayFont(28))
                        .foregroundStyle(MuseTheme.cream)
                    Text(look.tagline)
                        .font(MuseTheme.bodyFont(14).italic())
                        .foregroundStyle(MuseTheme.muted)
                }
                PaletteSwatch(hexColors: look.paletteHex, dotSize: 30)
                detailBlock(icon: "person.crop.circle.badge.checkmark", title: "Why it suits you", text: look.whySuited)
                detailBlock(icon: "cloud.sun", title: "For today's weather", text: look.weatherNotes)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(MuseTheme.background.ignoresSafeArea())
    }

    private func detailBlock(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(MuseTheme.accent)
                .frame(width: 20)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(MuseTheme.bodyFont(10, weight: .semibold))
                    .foregroundStyle(MuseTheme.muted)
                    .kerning(1.1)
                Text(text)
                    .font(MuseTheme.bodyFont(15))
                    .foregroundStyle(MuseTheme.cream.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct LookCard: View {
    let look: Look
    let onStart: () -> Void

    private var gradientColors: [Color] {
        let colors = look.paletteHex.map(Color.init(hex:))
        return colors.isEmpty ? [MuseTheme.surfaceRaised] : colors
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(height: 130)
                .overlay(alignment: .bottomLeading) {
                    PaletteSwatch(hexColors: look.paletteHex)
                        .padding(14)
                }

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(look.name)
                        .font(MuseTheme.displayFont(26))
                        .foregroundStyle(MuseTheme.cream)
                    Text(look.tagline)
                        .font(MuseTheme.bodyFont(14).italic())
                        .foregroundStyle(MuseTheme.muted)
                }

                infoBlock(icon: "person.crop.circle.badge.checkmark", title: "Why it suits you", text: look.whySuited)
                infoBlock(icon: "cloud.sun", title: "For today's weather", text: look.weatherNotes)

                Spacer(minLength: 0)

                Button("Start tutorial · \(look.steps.count) steps", action: onStart)
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(18)
        }
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(MuseTheme.surface)
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(MuseTheme.cream.opacity(0.08), lineWidth: 1)
        )
    }

    private func infoBlock(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(MuseTheme.accent)
                .frame(width: 20)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(MuseTheme.bodyFont(10, weight: .semibold))
                    .foregroundStyle(MuseTheme.muted)
                    .kerning(1.1)
                Text(text)
                    .font(MuseTheme.bodyFont(14))
                    .foregroundStyle(MuseTheme.cream.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
