import Foundation

/// Local conditions that change what survives on a face: humidity, rain, UV, heat.
struct WeatherSnapshot: Codable, Equatable {
    var temperatureC: Double
    var humidityPercent: Double
    var precipitationMM: Double
    var uvIndex: Double
    var summary: String

    var emoji: String {
        if precipitationMM > 0.2 { return "🌧️" }
        if uvIndex >= 6 { return "☀️" }
        if humidityPercent >= 75 { return "💦" }
        return "⛅️"
    }

    var shortDescription: String {
        "\(summary), \(Int(temperatureC.rounded()))°C · \(Int(humidityPercent.rounded()))% humidity"
    }

    var promptSummary: String {
        var parts = [
            "\(summary.lowercased()), \(Int(temperatureC.rounded()))°C",
            "humidity \(Int(humidityPercent.rounded()))%",
            "UV index \(String(format: "%.1f", uvIndex))",
        ]
        if precipitationMM > 0.05 {
            parts.append("currently precipitating (\(String(format: "%.1f", precipitationMM)) mm)")
        }
        return parts.joined(separator: ", ")
    }

    static let sample = WeatherSnapshot(
        temperatureC: 27,
        humidityPercent: 82,
        precipitationMM: 0,
        uvIndex: 7.5,
        summary: "Partly cloudy"
    )
}
