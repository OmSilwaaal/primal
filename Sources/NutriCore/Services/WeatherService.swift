import Foundation
import CoreLocation

/// Current conditions for the Home header, from Open-Meteo (the same free service the Sun screen uses;
/// it receives coordinates only). Refreshes at most every 15 minutes unless the user has moved.
@MainActor
final class WeatherService: ObservableObject {
    static let shared = WeatherService()
    private init() {}

    struct Current: Equatable {
        let celsius: Double
        let code: Int
        let isDay: Bool

        /// Temperature in the user's preferred unit, e.g. "64°".
        var temperature: String {
            Measurement(value: celsius, unit: UnitTemperature.celsius)
                .formatted(.measurement(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))))
        }

        /// WMO weather code -> SF Symbol and a short description.
        var symbol: String {
            switch code {
            case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
            case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
            case 3: "cloud.fill"
            case 45, 48: "cloud.fog.fill"
            case 51...57: "cloud.drizzle.fill"
            case 61, 63, 66: "cloud.rain.fill"
            case 65, 67: "cloud.heavyrain.fill"
            case 71...77, 85, 86: "cloud.snow.fill"
            case 80...82: isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
            case 95...99: "cloud.bolt.rain.fill"
            default: "cloud.fill"
            }
        }
        var summary: String {
            switch code {
            case 0: "Clear"
            case 1, 2: "Partly cloudy"
            case 3: "Overcast"
            case 45, 48: "Fog"
            case 51...57: "Drizzle"
            case 61...67: "Rain"
            case 71...77: "Snow"
            case 80...82: "Showers"
            case 85, 86: "Snow showers"
            case 95...99: "Thunderstorm"
            default: "Cloudy"
            }
        }
    }

    @Published private(set) var current: Current?
    private var lastFetch: (date: Date, location: CLLocation)?

    func refresh(location: CLLocation) async {
        if let last = lastFetch,
           Date().timeIntervalSince(last.date) < 15 * 60,
           location.distance(from: last.location) < 5_000 { return }

        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(location.coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        guard let url = c.url else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let r = try JSONDecoder().decode(Response.self, from: data)
            current = Current(celsius: r.current.temperature_2m, code: r.current.weather_code, isDay: r.current.is_day == 1)
            lastFetch = (Date(), location)
        } catch {
            // Keep the last reading; the chip simply doesn't update.
            print("Weather refresh failed: \(error)")
        }
    }

    private struct Response: Decodable {
        struct Now: Decodable { let temperature_2m: Double; let weather_code: Int; let is_day: Int }
        let current: Now
    }
}
