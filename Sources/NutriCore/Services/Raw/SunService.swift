import Foundation
import CoreLocation

/// Local solar maths (no network) plus today's UV index from Open-Meteo.
@MainActor
final class SunService: ObservableObject {
    static let shared = SunService()
    private init() {}

    @Published var uvNow: Double?
    @Published var uvMax: Double?
    @Published var hourlyUV: [(hour: Date, uv: Double)] = []
    @Published var sunrise: Date?
    @Published var sunset: Date?
    @Published var elevationNow: Double?
    @Published var uvbWindow: ClosedRange<Date>?
    @Published var uvbAllDay = false
    @Published var isLoading = false
    @Published var failed = false

    func refresh(location: CLLocation) async {
        let lat = location.coordinate.latitude, lon = location.coordinate.longitude
        let now = Date()
        elevationNow = Self.elevation(at: now, lat: lat, lon: lon)
        let times = Self.dayTimes(for: now, lat: lat, lon: lon)
        sunrise = times.sunrise; sunset = times.sunset
        uvbWindow = times.uvbWindow; uvbAllDay = times.uvbAllDay

        isLoading = true; failed = false
        defer { isLoading = false }
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            URLQueryItem(name: "latitude", value: String(lat)), URLQueryItem(name: "longitude", value: String(lon)),
            URLQueryItem(name: "hourly", value: "uv_index"), URLQueryItem(name: "daily", value: "uv_index_max"),
            URLQueryItem(name: "timezone", value: "auto"), URLQueryItem(name: "forecast_days", value: "1"),
        ]
        guard let url = c.url else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let r = try JSONDecoder().decode(OpenMeteo.self, from: data)
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd'T'HH:mm"
            fmt.timeZone = TimeZone(secondsFromGMT: r.utc_offset_seconds)
            fmt.locale = Locale(identifier: "en_US_POSIX")
            hourlyUV = zip(r.hourly.time, r.hourly.uv_index).compactMap { t, uv in
                guard let d = fmt.date(from: t), let uv else { return nil }
                return (d, uv)
            }
            uvMax = r.daily.uv_index_max.first ?? nil
            let current = hourlyUV.last(where: { $0.hour <= now })
            uvNow = current?.uv
        } catch {
            failed = true
        }
    }

    private struct OpenMeteo: Decodable {
        struct Hourly: Decodable { let time: [String]; let uv_index: [Double?] }
        struct Daily: Decodable { let uv_index_max: [Double?] }
        let utc_offset_seconds: Int
        let hourly: Hourly
        let daily: Daily
    }

    // MARK: Solar position (low-precision NOAA-style approximation, good to a few minutes)
    private static func rad(_ d: Double) -> Double { d * .pi / 180 }
    private static func deg(_ r: Double) -> Double { r * 180 / .pi }

    private static func dayOfYear(_ date: Date) -> Double {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        return Double(cal.ordinality(of: .day, in: .year, for: date) ?? 1)
    }

    private static func declinationAndEoT(_ date: Date) -> (decl: Double, eot: Double) {
        let n = dayOfYear(date)
        let decl = 23.45 * sin(rad(360.0 / 365.0 * (284 + n)))
        let b = rad(360.0 / 365.0 * (n - 81))
        let eot = 9.87 * sin(2 * b) - 7.53 * cos(b) - 1.5 * sin(b)  // minutes
        return (decl, eot)
    }

    static func elevation(at date: Date, lat: Double, lon: Double) -> Double {
        let (decl, eot) = declinationAndEoT(date)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.hour, .minute, .second], from: date)
        let utcHours = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600
        let solarTime = utcHours + lon / 15 + eot / 60
        let h = rad(15 * (solarTime - 12))
        let s = sin(rad(lat)) * sin(rad(decl)) + cos(rad(lat)) * cos(rad(decl)) * cos(h)
        return deg(asin(max(-1, min(1, s))))
    }

    struct DayTimes { var sunrise: Date?; var sunset: Date?; var uvbWindow: ClosedRange<Date>?; var uvbAllDay: Bool }

    /// Sunrise/sunset and the window when the sun is above 45° — the rule of thumb for when
    /// sunlight carries enough UVB to matter for vitamin D (shadow shorter than you).
    static func dayTimes(for date: Date, lat: Double, lon: Double) -> DayTimes {
        let (decl, eot) = declinationAndEoT(date)
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        let local = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let midnightUTC = utc.date(from: local) else { return DayTimes(sunrise: nil, sunset: nil, uvbWindow: nil, uvbAllDay: false) }
        let noonUTCHours = 12 - lon / 15 - eot / 60
        let noon = midnightUTC.addingTimeInterval(noonUTCHours * 3600)

        func halfDay(elevationDeg: Double) -> Double? {  // hours either side of solar noon
            let x = (sin(rad(elevationDeg)) - sin(rad(lat)) * sin(rad(decl))) / (cos(rad(lat)) * cos(rad(decl)))
            if x <= -1 { return 12 }     // sun stays above
            if x >= 1 { return nil }      // never reaches
            return deg(acos(x)) / 15
        }
        let rise = halfDay(elevationDeg: -0.833)
        let uvb = halfDay(elevationDeg: 45)
        return DayTimes(
            sunrise: rise.map { noon.addingTimeInterval(-$0 * 3600) },
            sunset: rise.map { noon.addingTimeInterval($0 * 3600) },
            uvbWindow: uvb.flatMap { $0 >= 12 ? nil : noon.addingTimeInterval(-$0 * 3600)...noon.addingTimeInterval($0 * 3600) },
            uvbAllDay: (uvb ?? 0) >= 12)
    }
}
