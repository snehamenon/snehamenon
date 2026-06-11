import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Text("MUSE")
                .font(MuseTheme.displayFont(52, weight: .bold))
                .foregroundStyle(MuseTheme.cream)
                .kerning(10)
            Text("Your AI makeup director")
                .font(MuseTheme.bodyFont(16))
                .foregroundStyle(MuseTheme.muted)
                .padding(.top, 6)

            VStack(spacing: 14) {
                pillar(
                    icon: "faceid",
                    title: "Made for your face",
                    text: "A 3-second on-device scan reads your features — the image never leaves your phone."
                )
                pillar(
                    icon: "cloud.sun",
                    title: "Made for today",
                    text: "Occasion and live weather shape every look, so it still works at hour eight."
                )
                pillar(
                    icon: "hand.draw",
                    title: "Coached, not filtered",
                    text: "No fake AR preview — step-by-step direction for applying real makeup, zone by zone."
                )
            }
            .padding(.top, 44)

            Spacer()

            if app.isMockMode {
                Text("Demo mode — add an API key for live AI looks (see README)")
                    .font(MuseTheme.bodyFont(12))
                    .foregroundStyle(MuseTheme.muted)
                    .padding(.bottom, 10)
            }

            Button("Scan my face") {
                app.stage = .scan
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private func pillar(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(MuseTheme.accent)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(MuseTheme.displayFont(17))
                    .foregroundStyle(MuseTheme.cream)
                Text(text)
                    .font(MuseTheme.bodyFont(14))
                    .foregroundStyle(MuseTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(MuseTheme.surface)
        )
    }
}
