import Foundation
import CoreLocation

/// One-shot local weather via CoreLocation + Open-Meteo (free, no API key).
final class WeatherService: NSObject, ObservableObject {
    enum Status: Equatable {
        case idle
        case working
        case loaded
        case failed
    }

    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var status: Status = .idle

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func refresh() {
        guard status != .working else { return }
        status = .working
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            status = .failed
        }
    }

    private func fetch(coordinate: CLLocationCoordinate2D) {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,relative_humidity_2m,precipitation,weather_code,uv_index"),
        ]
        guard let url = components.url else {
            status = .failed
            return
        }
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
                let current = decoded.current
                let result = WeatherSnapshot(
                    temperatureC: current.temperature,
                    humidityPercent: current.humidity,
                    precipitationMM: current.precipitation,
                    uvIndex: current.uvIndex,
                    summary: Self.describe(weatherCode: current.weatherCode)
                )
                await MainActor.run {
                    self.snapshot = result
                    self.status = .loaded
                }
            } catch {
                await MainActor.run { self.status = .failed }
            }
        }
    }

    private static func describe(weatherCode: Int) -> String {
        switch weatherCode {
        case 0: return "Clear sky"
        case 1, 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Foggy"
        case 51...57: return "Drizzle"
        case 61...67: return "Rain"
        case 71...77: return "Snow"
        case 80...82: return "Rain showers"
        case 85, 86: return "Snow showers"
        case 95...99: return "Thunderstorm"
        default: return "Mixed conditions"
        }
    }

    private struct OpenMeteoResponse: Decodable {
        struct Current: Decodable {
            let temperature: Double
            let humidity: Double
            let precipitation: Double
            let weatherCode: Int
            let uvIndex: Double

            enum CodingKeys: String, CodingKey {
                case temperature = "temperature_2m"
                case humidity = "relative_humidity_2m"
                case precipitation
                case weatherCode = "weather_code"
                case uvIndex = "uv_index"
            }
        }
        let current: Current
    }
}

extension WeatherService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if status == .working { manager.requestLocation() }
        case .denied, .restricted:
            if status == .working { status = .failed }
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            status = .failed
            return
        }
        fetch(coordinate: location.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        status = .failed
    }
}
