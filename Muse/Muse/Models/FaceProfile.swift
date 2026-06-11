import Foundation

enum FaceShape: String, Codable, CaseIterable, Identifiable {
    case oval, round, square, heart, oblong, diamond

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum EyeShape: String, Codable, CaseIterable, Identifiable {
    case almond, round, hooded, monolid, downturned, upturned

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum LipFullness: String, Codable, CaseIterable, Identifiable {
    case thin, balanced, full

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum Undertone: String, Codable, CaseIterable, Identifiable {
    case cool, warm, neutral, olive

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }

    /// Shown next to the picker so users can self-identify with the classic wrist-vein check.
    var hint: String {
        switch self {
        case .cool: return "Veins look blue or purple"
        case .warm: return "Veins look green"
        case .neutral: return "A mix of both"
        case .olive: return "Greenish-grey cast to the skin"
        }
    }
}

/// Everything Muse knows about a face. Derived on-device; only these abstract
/// attributes (never the image) are sent to the look director.
struct FaceProfile: Codable, Equatable {
    var faceShape: FaceShape
    var eyeShape: EyeShape
    var lipFullness: LipFullness
    var undertone: Undertone
    /// 0 = soft/rounded cheeks … 1 = sculpted, prominent cheekbones
    var cheekboneProminence: Double
    /// 0 = straight brows … 1 = high arch
    var browArch: Double

    var promptSummary: String {
        let cheeks: String
        switch cheekboneProminence {
        case ..<0.35: cheeks = "soft, rounded cheeks"
        case ..<0.65: cheeks = "moderately defined cheekbones"
        default: cheeks = "prominent, sculpted cheekbones"
        }
        let brows: String
        switch browArch {
        case ..<0.35: brows = "fairly straight brows"
        case ..<0.65: brows = "softly arched brows"
        default: brows = "high-arched brows"
        }
        return "\(faceShape.rawValue) face shape, \(eyeShape.rawValue) eyes, \(lipFullness.rawValue) lips, \(undertone.rawValue) undertone, \(cheeks), \(brows)"
    }

    static let sample = FaceProfile(
        faceShape: .heart,
        eyeShape: .hooded,
        lipFullness: .balanced,
        undertone: .neutral,
        cheekboneProminence: 0.7,
        browArch: 0.5
    )
}
