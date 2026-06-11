import SwiftUI

/// Editorial-dark design language: near-black plum canvas, warm cream type,
/// terracotta accent, serif display faces.
enum MuseTheme {
    static let background = Color(hex: "#100B12")
    static let surface = Color(hex: "#1C1520")
    static let surfaceRaised = Color(hex: "#271E2C")
    static let cream = Color(hex: "#F4EFE6")
    static let muted = Color(hex: "#A196A8") // warm grey-mauve
    static let accent = Color(hex: "#D98E5B")
    static let accentDeep = Color(hex: "#B5683C")

    static func displayFont(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func bodyFont(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

extension Color {
    /// Parses "#RRGGBB" (leading # optional); falls back to mid-grey on bad input
    /// so a malformed palette hex from the model can never crash the UI.
    init(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        var value: UInt64 = 0
        guard cleaned.count == 6, Scanner(string: cleaned).scanHexInt64(&value) else {
            self.init(white: 0.5)
            return
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var isProminent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MuseTheme.bodyFont(17, weight: .semibold))
            .foregroundStyle(isProminent ? MuseTheme.background : MuseTheme.cream)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isProminent ? AnyShapeStyle(MuseTheme.accent) : AnyShapeStyle(MuseTheme.surfaceRaised))
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
