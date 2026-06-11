import SwiftUI

/// The instructional card for one tutorial step.
struct StepCard: View {
    let step: TutorialStep

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(step.title)
                    .font(MuseTheme.displayFont(22))
                    .foregroundStyle(MuseTheme.cream)
                Spacer()
                Text(step.zone.displayName)
                    .font(MuseTheme.bodyFont(12, weight: .semibold))
                    .foregroundStyle(MuseTheme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(MuseTheme.accent.opacity(0.15)))
            }

            row(icon: "paintbrush.pointed", label: "Product", text: step.product)
            row(icon: "swatchpalette", label: "Shade", text: step.shadeGuidance)
            row(icon: "hand.draw", label: "Technique", text: step.technique)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(MuseTheme.accent)
                    .font(.system(size: 13))
                    .padding(.top, 2)
                Text(step.proTip)
                    .font(MuseTheme.bodyFont(14).italic())
                    .foregroundStyle(MuseTheme.cream.opacity(0.85))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(MuseTheme.accent.opacity(0.08))
            )
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(MuseTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(MuseTheme.cream.opacity(0.08), lineWidth: 1)
        )
    }

    private func row(icon: String, label: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(MuseTheme.muted)
                .frame(width: 20)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(MuseTheme.bodyFont(10, weight: .semibold))
                    .foregroundStyle(MuseTheme.muted)
                    .kerning(1.1)
                Text(text)
                    .font(MuseTheme.bodyFont(15))
                    .foregroundStyle(MuseTheme.cream)
            }
        }
    }
}
