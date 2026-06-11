import SwiftUI

/// Row of color dots previewing a look's palette.
struct PaletteSwatch: View {
    let hexColors: [String]
    var dotSize: CGFloat = 26

    var body: some View {
        HStack(spacing: -dotSize * 0.28) {
            ForEach(Array(hexColors.enumerated()), id: \.offset) { _, hex in
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: dotSize, height: dotSize)
                    .overlay(Circle().strokeBorder(MuseTheme.background.opacity(0.8), lineWidth: 2))
            }
        }
    }
}
