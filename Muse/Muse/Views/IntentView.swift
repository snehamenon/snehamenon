import SwiftUI

struct IntentView: View {
    @EnvironmentObject private var app: AppState
    @FocusState private var vibeFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What's the brief?")
                        .font(MuseTheme.displayFont(30))
                        .foregroundStyle(MuseTheme.cream)
                    Text("Where you're going and the vibe you want — Muse handles the rest.")
                        .font(MuseTheme.bodyFont(15))
                        .foregroundStyle(MuseTheme.muted)
                }

                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("Occasion")
                    FlowLayout(spacing: 8) {
                        ForEach(Occasion.allCases) { occasion in
                            Chip(
                                label: occasion.displayName,
                                emoji: occasion.emoji,
                                isSelected: app.intent.occasion == occasion
                            ) {
                                app.intent.occasion = occasion
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("The vibe, in your words")
                    TextField(
                        "",
                        text: $app.intent.vibe,
                        prompt: Text("e.g. soft glam, but I only have 20 minutes…")
                            .foregroundStyle(MuseTheme.muted),
                        axis: .vertical
                    )
                    .lineLimit(2...4)
                    .focused($vibeFocused)
                    .font(MuseTheme.bodyFont(16))
                    .foregroundStyle(MuseTheme.cream)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(MuseTheme.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                vibeFocused ? MuseTheme.accent.opacity(0.6) : MuseTheme.cream.opacity(0.1),
                                lineWidth: 1
                            )
                    )
                }

                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("Intensity")
                    VStack(spacing: 6) {
                        Slider(value: $app.intent.boldness)
                            .tint(MuseTheme.accent)
                        HStack {
                            Text("Barely there")
                            Spacer()
                            Text(app.intent.boldnessLabel.capitalized)
                                .foregroundStyle(MuseTheme.accent)
                                .fontWeight(.semibold)
                            Spacer()
                            Text("Bold")
                        }
                        .font(MuseTheme.bodyFont(12))
                        .foregroundStyle(MuseTheme.muted)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("Today's conditions")
                    WeatherChipView(service: app.weatherService)
                }

                Button("Direct my looks") {
                    vibeFocused = false
                    app.stage = .looks
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 6)
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(MuseTheme.bodyFont(11, weight: .semibold))
            .foregroundStyle(MuseTheme.muted)
            .kerning(1.4)
    }
}

/// Observes the weather service directly so status changes re-render.
private struct WeatherChipView: View {
    @ObservedObject var service: WeatherService

    var body: some View {
        switch service.status {
        case .idle, .working:
            InfoChip(emoji: "🛰️", text: "Checking local weather…")
        case .loaded:
            if let snapshot = service.snapshot {
                InfoChip(emoji: snapshot.emoji, text: snapshot.shortDescription)
            }
        case .failed:
            HStack(spacing: 8) {
                InfoChip(emoji: "🌫️", text: "Weather unavailable — looks won't be weather-tuned")
                Button("Retry") { service.refresh() }
                    .font(MuseTheme.bodyFont(13, weight: .semibold))
                    .foregroundStyle(MuseTheme.accent)
            }
        }
    }
}

/// Minimal wrapping layout for the occasion chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
