import Foundation

enum LookDirectorError: LocalizedError {
    case missingAPIKey
    case badStatus(Int, String)
    case refused
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No API key configured. Add Secrets.plist or use mock mode."
        case .badStatus(let code, let message):
            return "The look service returned an error (\(code)): \(message)"
        case .refused:
            return "The look service declined this request. Try rephrasing your vibe."
        case .emptyResponse:
            return "The look service returned an empty response. Please try again."
        }
    }
}

/// The creative brain. `ClaudeLookDirector` is the real implementation; the
/// protocol keeps the door open for an on-device (Apple Foundation Models)
/// tier later without touching any UI.
protocol LookDirector {
    var isMock: Bool { get }
    func generateLooks(
        profile: FaceProfile,
        intent: LookIntent,
        weather: WeatherSnapshot?
    ) async throws -> [Look]
}

/// Canned looks so the entire flow demos with no API key (and on the simulator).
struct MockLookDirector: LookDirector {
    let isMock = true

    func generateLooks(
        profile: FaceProfile,
        intent: LookIntent,
        weather: WeatherSnapshot?
    ) async throws -> [Look] {
        try await Task.sleep(nanoseconds: 1_400_000_000)
        let eyes = profile.eyeShape.displayName.lowercased()
        let face = profile.faceShape.displayName.lowercased()
        let tone = profile.undertone.displayName.lowercased()
        let weatherNote = weather.map {
            "At \(Int($0.humidityPercent))% humidity, set cream products with a light dusting of powder so this lasts."
        } ?? "Indoor-friendly as written; add setting spray if you'll be out long."

        return [
            Look(
                name: "Golden Hour",
                tagline: "Soft glam that flatters without trying",
                paletteHex: ["#D98E5B", "#C96F4A", "#F2D8C2", "#8A5A44"],
                whySuited: "Warm terracotta tones lift a \(tone) undertone, and the placement is tuned for \(eyes) eyes — color sits where it shows, not where it hides.",
                weatherNotes: weatherNote,
                steps: [
                    TutorialStep(stepNumber: 1, title: "Even the canvas", zone: .fullFace, product: "Lightweight tinted moisturizer or skin tint", shadeGuidance: "Match your jawline in daylight; lean golden for a \(tone) undertone.", technique: "Press in with fingertips from the center of the face outward — warmth from your hands melts it into skin.", proTip: "Skip heavy coverage; this look reads best with real skin showing through.", colorHex: "#E8C5A0", finish: "dewy"),
                    TutorialStep(stepNumber: 2, title: "Lift the under-eye", zone: .underEye, product: "Hydrating concealer", shadeGuidance: "Half a shade lighter than your base, with a peach lean to cancel blue.", technique: "Draw a small inverted triangle under each eye and tap — never rub — with a ring finger.", proTip: "Only conceal where shadow actually sits; over-concealing creases by noon.", colorHex: "#F2D8C2", finish: "satin"),
                    TutorialStep(stepNumber: 3, title: "Sculpt softly", zone: .cheekbones, product: "Cream bronzer", shadeGuidance: "Two shades deeper than skin, warm-leaning.", technique: "Sweep from ear toward the apple of the cheek, stopping under the cheekbone — blend up, not down, on a \(face) face.", proTip: "Smile to find the cheekbone hollow, then relax before you blend.", colorHex: "#A86B47", finish: "satin"),
                    TutorialStep(stepNumber: 4, title: "Warm the lids", zone: .eyelids, product: "Cream or powder shadow in terracotta", shadeGuidance: "Burnt orange to copper; avoid anything ashy.", technique: "Pat across the mobile lid, then blend the edge up and out with a fluffy brush — for \(eyes) eyes keep the deepest color at the outer third.", proTip: "Blend with windshield-wiper motions only at the very edge; pat everywhere else.", colorHex: "#C96F4A", finish: "shimmer"),
                    TutorialStep(stepNumber: 5, title: "Define the lash line", zone: .lashLine, product: "Brown pencil liner + mascara", shadeGuidance: "Soft brown, not black, keeps it daytime.", technique: "Tightline the upper lashes, smudge slightly, then two coats of mascara wiggled from the root.", proTip: "Look down into a mirror while tightlining — it keeps the line invisible but the lashes dense.", colorHex: "#5A3D2E", finish: "matte"),
                    TutorialStep(stepNumber: 6, title: "Finish the lips", zone: .lips, product: "Tinted balm or satin lipstick", shadeGuidance: "A your-lips-but-warmer terracotta nude.", technique: "Apply from the center and press lips together; edge definition stays soft.", proTip: "Dab a fingertip of the cream bronzer onto the lips first for a perfectly tied-together look.", colorHex: "#C97A5C", finish: "satin")
                ]
            ),
            Look(
                name: "Clean Slate",
                tagline: "The five-minute 'I woke up like this'",
                paletteHex: ["#E8C5B5", "#D9A79A", "#F5EDE4", "#B98474"],
                whySuited: "Minimal product, maximum structure — brushed-up brows and a precise lash line do the work, which suits \(eyes) eyes where heavy shadow can disappear.",
                weatherNotes: weatherNote,
                steps: [
                    TutorialStep(stepNumber: 1, title: "Prep, don't paint", zone: .fullFace, product: "Moisturizer + SPF", shadeGuidance: "Invisible — this step is skin, not color.", technique: "Massage in upward strokes and give it two minutes to settle before anything else.", proTip: "If you're shiny-prone, keep SPF off the T-zone and use a mattifying one there instead.", colorHex: "#EAD3C2", finish: "dewy"),
                    TutorialStep(stepNumber: 2, title: "Spot-conceal only", zone: .underEye, product: "Skin-like concealer", shadeGuidance: "Exact skin match — lighter shades read obvious on bare skin.", technique: "Dot only on visible redness or darkness and tap out the edges.", proTip: "A tiny dab on the corners of the nose instantly makes the whole face look 'done'.", colorHex: "#F0DDD0", finish: "satin"),
                    TutorialStep(stepNumber: 3, title: "Brows up", zone: .brows, product: "Clear or tinted brow gel", shadeGuidance: "Match brow hair, not head hair.", technique: "Brush hairs up and slightly out, then set the tails downward in their growth direction.", proTip: "Wipe the spoolie on a tissue first; less gel means no crunch.", colorHex: "#7A5A48", finish: "matte"),
                    TutorialStep(stepNumber: 4, title: "Flush from within", zone: .cheeks, product: "Cream blush", shadeGuidance: "Rosy nude that flatters a \(tone) undertone.", technique: "Smile, dab two dots on each apple, and blend upward with fingers in light taps.", proTip: "Tap the leftover on your fingertips across the bridge of the nose for a sun-kissed tie-in.", colorHex: "#D98C84", finish: "dewy"),
                    TutorialStep(stepNumber: 5, title: "Curl and coat", zone: .lashLine, product: "Lash curler + brown mascara", shadeGuidance: "Brown keeps it soft; black if you want more definition.", technique: "Curl at the root for ten seconds, then one thin coat, top lashes only.", proTip: "Heat the curler with a hairdryer for two seconds (test on your hand!) for a curl that lasts all day.", colorHex: "#4E382C", finish: "matte")
                ]
            ),
            Look(
                name: "After Dark",
                tagline: "Smoked-out drama, engineered to last",
                paletteHex: ["#3B2B3F", "#6E4A6B", "#C9A0C4", "#1C1320"],
                whySuited: "A lifted, smoked outer corner adds the dimension that flatters \(eyes) eyes, and the vertical gradient elongates a \(face) face under evening light.",
                weatherNotes: weatherNote,
                steps: [
                    TutorialStep(stepNumber: 1, title: "Prime for longevity", zone: .eyelids, product: "Eyeshadow primer", shadeGuidance: "Skin-toned; avoid shimmer primers under smoke.", technique: "A rice-grain amount per lid, blended edge to edge with a fingertip.", proTip: "Set the primer with a neutral powder shadow first — smoky blends twice as easily over it.", colorHex: "#D8C3D0", finish: "satin"),
                    TutorialStep(stepNumber: 2, title: "Build the smoke", zone: .eyelids, product: "Plum-to-charcoal shadow quad", shadeGuidance: "Cool plums sing on a \(tone) undertone.", technique: "Mid-tone through the crease first, deepest shade at the outer corner in a sideways V, blend inward.", proTip: "Do the eyes before base makeup — fallout cleanup becomes a non-issue.", colorHex: "#5A3A57", finish: "shimmer"),
                    TutorialStep(stepNumber: 3, title: "Smoke the lower line", zone: .underEye, product: "The same deep shadow + small smudge brush", shadeGuidance: "Same family as the lid so it reads intentional.", technique: "Connect the outer-lower lash line to the outer V, fading toward the inner corner.", proTip: "Leave the inner third bare — fully ringed eyes shrink; open inner corners enlarge.", colorHex: "#3B2B3F", finish: "matte"),
                    TutorialStep(stepNumber: 4, title: "Lock the base", zone: .fullFace, product: "Long-wear foundation + setting powder", shadeGuidance: "Exact match; evening light is unforgiving of oxidized bases.", technique: "Thin layers with a damp sponge, pressed — not wiped — then powder where you crease.", proTip: "Powder first under the eyes, before concealer, to catch any late fallout.", colorHex: "#E3C3A8", finish: "satin"),
                    TutorialStep(stepNumber: 5, title: "Sculpt for low light", zone: .cheekbones, product: "Powder contour + liquid highlighter", shadeGuidance: "Cool-neutral contour; champagne highlight.", technique: "Contour just under the cheekbone, highlight only the very top — evening light exaggerates both, so use less than feels right.", proTip: "Blend contour with whatever's left on your foundation sponge for zero harsh lines.", colorHex: "#8A6A55", finish: "matte"),
                    TutorialStep(stepNumber: 6, title: "Velvet lip", zone: .lips, product: "Matte liquid lip or velvet lipstick", shadeGuidance: "Mauve-nude lets the eyes lead; deep berry if you want double drama.", technique: "Line and fill with pencil first, then one thin coat of the liquid, blotted.", proTip: "Conceal around the lip line afterward — the crisp edge is what makes it look professional.", colorHex: "#A86A7A", finish: "satin"),
                    TutorialStep(stepNumber: 7, title: "Make it survive the night", zone: .fullFace, product: "Setting spray", shadeGuidance: "Any fine-mist formula.", technique: "Three X-motion spritzes at arm's length with eyes closed; let it dry untouched.", proTip: "Spray once after base and once at the end — layered setting outlasts a single final mist.", colorHex: "#FFFFFF", finish: "dewy")
                ]
            )
        ]
    }
}
