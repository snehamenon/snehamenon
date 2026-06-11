import SwiftUI

struct LookOptionsView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var viewModel = LooksViewModel()

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                loadingView
            case .failed(let message):
                failureView(message)
            case .loaded:
                cardsView
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

    // MARK: - Cards

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
                // Balances the leading button so the title centers.
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

private struct LookCard: View {
    let look: Look
    let onStart: () -> Void

    private var gradientColors: [Color] {
        let colors = look.paletteHex.map(Color.init(hex:))
        return colors.isEmpty ? [MuseTheme.surfaceRaised] : colors
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Palette banner
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
