import Foundation

/// Regions of the face a tutorial step applies to. Raw values are the wire
/// format used in the structured-output JSON schema sent to Claude.
enum FaceZone: String, Codable, CaseIterable {
    case fullFace = "full_face"
    case forehead
    case brows
    case eyelids
    case lashLine = "lash_line"
    case lashes
    case underEye = "under_eye"
    case cheeks
    case cheekbones
    case nose
    case lips
    case jawline

    var displayName: String {
        switch self {
        case .fullFace: return "Full face"
        case .forehead: return "Forehead"
        case .brows: return "Brows"
        case .eyelids: return "Eyelids"
        case .lashLine: return "Lash line"
        case .lashes: return "Lashes"
        case .underEye: return "Under eye"
        case .cheeks: return "Cheeks"
        case .cheekbones: return "Cheekbones"
        case .nose: return "Nose"
        case .lips: return "Lips"
        case .jawline: return "Jawline"
        }
    }
}

/// Texture of a product, used to tune how the preview blends it onto skin.
enum MakeupFinish: String, Codable, Equatable {
    case matte, satin, shimmer, dewy
}

struct TutorialStep: Codable, Identifiable, Equatable {
    let stepNumber: Int
    let title: String
    let zone: FaceZone
    let product: String
    let shadeGuidance: String
    let technique: String
    let proTip: String
    /// Representative product color for this step, as #RRGGBB. Drives both the
    /// coaching highlight tint and the look preview. Optional for resilience if
    /// a response omits it.
    var colorHex: String? = nil
    var finish: String? = nil

    var id: Int { stepNumber }

    var makeupFinish: MakeupFinish {
        finish.flatMap { MakeupFinish(rawValue: $0.lowercased()) } ?? .satin
    }
}

struct Look: Codable, Identifiable, Equatable {
    let name: String
    let tagline: String
    let paletteHex: [String]
    let whySuited: String
    let weatherNotes: String
    let steps: [TutorialStep]

    var id: String { name }
}

/// Top-level shape of the structured response from the look director.
struct LookSet: Codable, Equatable {
    let looks: [Look]
}
