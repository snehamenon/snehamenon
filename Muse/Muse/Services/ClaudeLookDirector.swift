import Foundation

/// Reads the Anthropic API key from a gitignored Secrets.plist bundled with the app.
/// PROTOTYPE ONLY: a shipping app must route calls through a backend proxy instead
/// of embedding a key in the binary.
enum Secrets {
    static var anthropicAPIKey: String? {
        guard
            let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let dict = plist as? [String: Any],
            let key = dict["ANTHROPIC_API_KEY"] as? String,
            !key.isEmpty, !key.contains("REPLACE-ME")
        else { return nil }
        return key
    }
}

/// Calls the Claude Messages API directly (Swift has no official Anthropic SDK)
/// using structured outputs, so the response is schema-guaranteed JSON that
/// decodes straight into `LookSet`.
struct ClaudeLookDirector: LookDirector {
    let isMock = false

    private let apiKey: String
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let model = "claude-opus-4-8"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    /// Returns a configured director if a key is present, else nil (caller falls back to mock).
    static func ifConfigured() -> ClaudeLookDirector? {
        Secrets.anthropicAPIKey.map(ClaudeLookDirector.init(apiKey:))
    }

    func generateLooks(
        profile: FaceProfile,
        intent: LookIntent,
        weather: WeatherSnapshot?
    ) async throws -> [Look] {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": 16000,
            "system": Self.systemPrompt,
            "messages": [
                ["role": "user", "content": Self.userPrompt(profile: profile, intent: intent, weather: weather)]
            ],
            "output_config": [
                "format": [
                    "type": "json_schema",
                    "schema": Self.lookSetSchema,
                ]
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LookDirectorError.emptyResponse
        }
        guard http.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "unreadable error body"
            throw LookDirectorError.badStatus(http.statusCode, message)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let api = try decoder.decode(APIResponse.self, from: data)

        if api.stopReason == "refusal" {
            throw LookDirectorError.refused
        }
        guard let text = api.content.first(where: { $0.type == "text" })?.text,
              let payload = text.data(using: .utf8)
        else {
            throw LookDirectorError.emptyResponse
        }
        return try decoder.decode(LookSet.self, from: payload).looks
    }

    // MARK: - Wire types

    private struct APIResponse: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }
        let content: [Block]
        let stopReason: String?
    }

    // MARK: - Prompting

    private static let systemPrompt = """
    You are Muse, an elite editorial makeup director. You compose makeup looks \
    personalized to a specific person's facial features, the occasion, and today's weather, \
    then teach them with clear, encouraging step-by-step instructions.

    Principles:
    - Adapt techniques to the stated features (e.g. for hooded eyes, place crease work above \
    the natural fold and angle wings to lift; for a round face, blend contour vertically; \
    for full lips, skip overlining).
    - Adapt formulations to the weather (high humidity or rain: long-wear/waterproof formulas \
    and powder-set creams; high UV: SPF in the base; cold and dry: cream and balm textures).
    - Recommend product TYPES and shade directions (e.g. "peach-leaning concealer half a shade \
    lighter"), never specific brand names.
    - Shade guidance must respect the stated undertone.
    - Each look must feel distinct from the others in finish, palette, or energy.
    - Steps go in real application order. Keep every field tight and concrete; write like a \
    confident pro coaching a friend at the mirror.
    """

    private static func userPrompt(
        profile: FaceProfile,
        intent: LookIntent,
        weather: WeatherSnapshot?
    ) -> String {
        var lines = [
            "Compose exactly 3 distinct makeup looks for this person, each with 5 to 8 tutorial steps.",
            "",
            "Face (measured on-device): \(profile.promptSummary).",
            "Intent: \(intent.promptSummary).",
        ]
        if let weather {
            lines.append("Local weather right now: \(weather.promptSummary).")
        } else {
            lines.append("Weather unavailable — assume indoor, temperate conditions and note any outdoor caveats.")
        }
        lines.append("")
        lines.append(
            "For each look: a short evocative name, a one-line tagline, a palette of 3-5 hex colors that " +
            "previews the look's tones, why_suited tied to THIS person's specific features, and weather_notes " +
            "tied to the conditions above. palette_hex values must be #RRGGBB strings."
        )
        lines.append(
            "For every step, also set color_hex to the actual product color applied in that step as a " +
            "#RRGGBB string (the real color the user would see on that zone — e.g. the lipstick color on " +
            "lips, the eyeshadow color on eyelids, the blush on cheeks), and finish to one of matte, satin, " +
            "shimmer, or dewy. These power a live preview that paints the look on the user's face, so make " +
            "color_hex realistic for the zone."
        )
        lines.append(
            "Include a mascara step using the \"lashes\" zone (distinct from \"lash_line\" eyeliner) whenever " +
            "it suits the look — its color_hex should be the mascara color, brown to black."
        )
        return lines.joined(separator: "\n")
    }

    // MARK: - Structured output schema (mirrors LookSet/Look/TutorialStep)

    private static let lookSetSchema: [String: Any] = {
        let stepSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "step_number": ["type": "integer"],
                "title": ["type": "string"],
                "zone": [
                    "type": "string",
                    "enum": FaceZone.allCases.map(\.rawValue),
                ],
                "product": ["type": "string"],
                "shade_guidance": ["type": "string"],
                "technique": ["type": "string"],
                "pro_tip": ["type": "string"],
                "color_hex": ["type": "string"],
                "finish": [
                    "type": "string",
                    "enum": ["matte", "satin", "shimmer", "dewy"],
                ],
            ],
            "required": ["step_number", "title", "zone", "product", "shade_guidance", "technique", "pro_tip", "color_hex", "finish"],
            "additionalProperties": false,
        ]
        let lookSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "name": ["type": "string"],
                "tagline": ["type": "string"],
                "palette_hex": ["type": "array", "items": ["type": "string"]],
                "why_suited": ["type": "string"],
                "weather_notes": ["type": "string"],
                "steps": ["type": "array", "items": stepSchema],
            ],
            "required": ["name", "tagline", "palette_hex", "why_suited", "weather_notes", "steps"],
            "additionalProperties": false,
        ]
        return [
            "type": "object",
            "properties": [
                "looks": ["type": "array", "items": lookSchema]
            ],
            "required": ["looks"],
            "additionalProperties": false,
        ]
    }()
}
