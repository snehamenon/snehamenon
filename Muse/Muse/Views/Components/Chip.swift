import SwiftUI

/// Selectable pill used for occasion picking.
struct Chip: View {
    let label: String
    let emoji: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(emoji)
                Text(label)
                    .font(MuseTheme.bodyFont(15, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? MuseTheme.background : MuseTheme.cream)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(isSelected ? AnyShapeStyle(MuseTheme.accent) : AnyShapeStyle(MuseTheme.surfaceRaised))
            )
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? Color.clear : MuseTheme.cream.opacity(0.12),
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
    }
}

/// Small informational pill (e.g. the weather readout).
struct InfoChip: View {
    let emoji: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Text(emoji)
            Text(text)
                .font(MuseTheme.bodyFont(13))
                .foregroundStyle(MuseTheme.cream.opacity(0.85))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(MuseTheme.surface))
        .overlay(Capsule().strokeBorder(MuseTheme.cream.opacity(0.1), lineWidth: 1))
    }
}
