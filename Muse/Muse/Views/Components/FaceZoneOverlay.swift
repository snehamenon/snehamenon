import SwiftUI

/// Stylized face diagram with the current tutorial step's zone glowing.
/// v0 uses a proportional diagram; Phase 2 projects zones onto the user's
/// live face mesh in AR.
struct FaceZoneOverlay: View {
    let zone: FaceZone

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            // Highlight first, so face linework draws on top of the glow.
            for rect in Self.highlightRects(for: zone) {
                let frame = CGRect(
                    x: rect.minX * w, y: rect.minY * h,
                    width: rect.width * w, height: rect.height * h
                )
                let shape = Path(ellipseIn: frame)
                context.fill(shape, with: .color(MuseTheme.accent.opacity(0.28)))
                context.stroke(shape, with: .color(MuseTheme.accent), lineWidth: 2)
            }

            let line = MuseTheme.cream.opacity(0.55)

            // Face outline — softly tapered oval.
            var face = Path()
            face.addEllipse(in: CGRect(x: 0.18 * w, y: 0.06 * h, width: 0.64 * w, height: 0.88 * h))
            context.stroke(face, with: .color(line), lineWidth: 1.6)

            // Brows
            for sign in [-1.0, 1.0] {
                var brow = Path()
                let cx = 0.5 + sign * 0.155
                brow.move(to: CGPoint(x: (cx - 0.085) * w, y: 0.345 * h))
                brow.addQuadCurve(
                    to: CGPoint(x: (cx + 0.085) * w, y: 0.345 * h),
                    control: CGPoint(x: cx * w, y: 0.305 * h)
                )
                context.stroke(brow, with: .color(line), lineWidth: 1.6)
            }

            // Eyes
            for sign in [-1.0, 1.0] {
                let cx = 0.5 + sign * 0.155
                let eye = Path(ellipseIn: CGRect(
                    x: (cx - 0.07) * w, y: 0.40 * h, width: 0.14 * w, height: 0.055 * h
                ))
                context.stroke(eye, with: .color(line), lineWidth: 1.4)
            }

            // Nose
            var nose = Path()
            nose.move(to: CGPoint(x: 0.5 * w, y: 0.44 * h))
            nose.addLine(to: CGPoint(x: 0.485 * w, y: 0.585 * h))
            nose.addQuadCurve(
                to: CGPoint(x: 0.53 * w, y: 0.60 * h),
                control: CGPoint(x: 0.5 * w, y: 0.615 * h)
            )
            context.stroke(nose, with: .color(line), lineWidth: 1.3)

            // Lips
            var lips = Path()
            lips.move(to: CGPoint(x: 0.40 * w, y: 0.715 * h))
            lips.addQuadCurve(
                to: CGPoint(x: 0.60 * w, y: 0.715 * h),
                control: CGPoint(x: 0.5 * w, y: 0.675 * h)
            )
            lips.addQuadCurve(
                to: CGPoint(x: 0.40 * w, y: 0.715 * h),
                control: CGPoint(x: 0.5 * w, y: 0.765 * h)
            )
            context.stroke(lips, with: .color(line), lineWidth: 1.4)
        }
        .aspectRatio(0.78, contentMode: .fit)
        .animation(.easeInOut(duration: 0.3), value: zone)
        .accessibilityLabel("Face diagram highlighting \(zone.displayName)")
    }

    /// Normalized (0–1) ellipse frames per zone within the diagram canvas.
    private static func highlightRects(for zone: FaceZone) -> [CGRect] {
        switch zone {
        case .fullFace:
            return [CGRect(x: 0.16, y: 0.04, width: 0.68, height: 0.92)]
        case .forehead:
            return [CGRect(x: 0.26, y: 0.10, width: 0.48, height: 0.16)]
        case .brows:
            return [
                CGRect(x: 0.245, y: 0.295, width: 0.20, height: 0.085),
                CGRect(x: 0.555, y: 0.295, width: 0.20, height: 0.085),
            ]
        case .eyelids:
            return [
                CGRect(x: 0.255, y: 0.365, width: 0.18, height: 0.075),
                CGRect(x: 0.565, y: 0.365, width: 0.18, height: 0.075),
            ]
        case .lashLine:
            return [
                CGRect(x: 0.26, y: 0.415, width: 0.17, height: 0.05),
                CGRect(x: 0.57, y: 0.415, width: 0.17, height: 0.05),
            ]
        case .lashes:
            return [
                CGRect(x: 0.255, y: 0.378, width: 0.18, height: 0.05),
                CGRect(x: 0.565, y: 0.378, width: 0.18, height: 0.05),
            ]
        case .underEye:
            return [
                CGRect(x: 0.26, y: 0.465, width: 0.17, height: 0.075),
                CGRect(x: 0.57, y: 0.465, width: 0.17, height: 0.075),
            ]
        case .cheeks:
            return [
                CGRect(x: 0.225, y: 0.535, width: 0.19, height: 0.13),
                CGRect(x: 0.585, y: 0.535, width: 0.19, height: 0.13),
            ]
        case .cheekbones:
            return [
                CGRect(x: 0.20, y: 0.49, width: 0.21, height: 0.085),
                CGRect(x: 0.59, y: 0.49, width: 0.21, height: 0.085),
            ]
        case .nose:
            return [CGRect(x: 0.435, y: 0.43, width: 0.13, height: 0.20)]
        case .lips:
            return [CGRect(x: 0.365, y: 0.655, width: 0.27, height: 0.125)]
        case .jawline:
            return [
                CGRect(x: 0.205, y: 0.70, width: 0.22, height: 0.14),
                CGRect(x: 0.575, y: 0.70, width: 0.22, height: 0.14),
            ]
        }
    }
}
