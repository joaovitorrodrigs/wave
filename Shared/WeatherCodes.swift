import Foundation

/// WMO weather codes from Open-Meteo, as a label and a Phosphor icon.
enum WeatherCodes {
    static func describe(_ code: Int, isDay: Bool) -> (label: String, icon: String) {
        switch code {
        case 0: (isDay ? "Clear" : "Clear night", isDay ? "sun" : "moon")
        case 1, 2: ("Partly cloudy", isDay ? "cloud-sun" : "cloud-moon")
        case 3: ("Overcast", "cloud")
        case 45, 48: ("Fog", "cloud-fog")
        case 51...57: ("Drizzle", "cloud-rain")
        case 61...67: ("Rain", "cloud-rain")
        case 71...77: ("Snow", "cloud-snow")
        case 80...82: ("Showers", "cloud-rain")
        case 85, 86: ("Snow showers", "cloud-snow")
        case 95...99: ("Storm", "cloud-lightning")
        default: ("Cloudy", "cloud")
        }
    }
}

struct LocationSnapshot: Codable {
    let latitude: Double
    let longitude: Double
    let place: String
}

struct EventSnapshot: Codable, Identifiable {
    var id: String { "\(start.timeIntervalSince1970)-\(title)" }
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let color: String   // hex rrggbb
}

/// Open-Meteo forecast, trimmed to what the cards show.
struct Forecast: Codable {
    let temperature: Double
    let code: Int
    let isDay: Bool
    let high: Double
    let low: Double
    let hours: [Hour]
    let fetched: Date

    struct Hour: Codable, Identifiable {
        let time: Date
        let temperature: Double
        let code: Int
        var id: Date { time }
    }

    static func url(latitude: Double, longitude: Double) -> URL {
        URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&current=temperature_2m,weather_code,is_day&hourly=temperature_2m,weather_code,is_day&daily=temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=2")!
    }

    static func fetch(latitude: Double, longitude: Double) async throws -> Forecast {
        let (data, _) = try await URLSession.shared.data(from: url(latitude: latitude, longitude: longitude))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = json["current"] as? [String: Any],
              let hourly = json["hourly"] as? [String: Any],
              let daily = json["daily"] as? [String: Any] else { throw URLError(.cannotParseResponse) }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = TimeZone(identifier: json["timezone"] as? String ?? "") ?? .current
        let times = (hourly["time"] as? [String] ?? []).compactMap { formatter.date(from: $0) }
        let temps = hourly["temperature_2m"] as? [Double] ?? []
        let codes = hourly["weather_code"] as? [Int] ?? []
        let hours = zip(times, zip(temps, codes)).map { Hour(time: $0.0, temperature: $0.1.0, code: $0.1.1) }
            .filter { $0.time > Date.now.addingTimeInterval(-1800) }.prefix(6)
        return Forecast(temperature: current["temperature_2m"] as? Double ?? 0,
                        code: current["weather_code"] as? Int ?? 0,
                        isDay: (current["is_day"] as? Int ?? 1) == 1,
                        high: (daily["temperature_2m_max"] as? [Double])?.first ?? 0,
                        low: (daily["temperature_2m_min"] as? [Double])?.first ?? 0,
                        hours: Array(hours), fetched: .now)
    }
}
