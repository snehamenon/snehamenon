import Foundation

enum Occasion: String, Codable, CaseIterable, Identifiable {
    case everyday
    case office
    case brunch
    case dateNight
    case weddingGuest
    case party
    case festival
    case interview

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .everyday: return "Everyday"
        case .office: return "Office"
        case .brunch: return "Brunch"
        case .dateNight: return "Date night"
        case .weddingGuest: return "Wedding guest"
        case .party: return "Party"
        case .festival: return "Festival"
        case .interview: return "Interview"
        }
    }

    var emoji: String {
        switch self {
        case .everyday: return "☀️"
        case .office: return "💼"
        case .brunch: return "🥂"
        case .dateNight: return "🌹"
        case .weddingGuest: return "💍"
        case .party: return "🪩"
        case .festival: return "🎡"
        case .interview: return "🤝"
        }
    }
}

/// What the user is going for, in their own words plus a couple of structured dials.
struct LookIntent: Equatable {
    var occasion: Occasion = .everyday
    var vibe: String = ""
    /// 0 = barely-there … 1 = maximum drama
    var boldness: Double = 0.5

    var boldnessLabel: String {
        switch boldness {
        case ..<0.25: return "barely there"
        case ..<0.5: return "subtle"
        case ..<0.75: return "noticeable"
        default: return "bold"
        }
    }

    var promptSummary: String {
        var parts = ["occasion: \(occasion.displayName.lowercased())", "intensity: \(boldnessLabel)"]
        let trimmed = vibe.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            parts.append("the user describes the vibe as: \"\(trimmed)\"")
        }
        return parts.joined(separator: "; ")
    }
}
