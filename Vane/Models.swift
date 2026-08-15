import Foundation
import SwiftData

@Model
final class WeatherProfile {
    var createdAt: Date
    var temperaturePreference: Double
    var windSensitivity: Double
    var humiditySensitivity: Double
    var enjoysRain: Bool
    var usesFeelsLikeTemperature: Bool = true

    init(createdAt: Date = .now, temperaturePreference: Double = 0, windSensitivity: Double = 0.5, humiditySensitivity: Double = 0.5, enjoysRain: Bool = false, usesFeelsLikeTemperature: Bool = true) {
        self.createdAt = createdAt
        self.temperaturePreference = temperaturePreference
        self.windSensitivity = windSensitivity
        self.humiditySensitivity = humiditySensitivity
        self.enjoysRain = enjoysRain
        self.usesFeelsLikeTemperature = usesFeelsLikeTemperature
    }
}

@Model
final class WeatherCheckIn {
    var createdAt: Date
    var temperature: Double
    var apparentTemperature: Double
    var humidity: Double
    var windSpeed: Double
    var response: String

    init(createdAt: Date = .now, temperature: Double, apparentTemperature: Double, humidity: Double, windSpeed: Double, response: FeelResponse) {
        self.createdAt = createdAt
        self.temperature = temperature
        self.apparentTemperature = apparentTemperature
        self.humidity = humidity
        self.windSpeed = windSpeed
        self.response = response.rawValue
    }

    var feelResponse: FeelResponse { FeelResponse(rawValue: response) ?? .comfortable }
}

@Model
final class SavedPlace {
    var id: UUID
    var name: String
    var region: String
    var latitude: Double
    var longitude: Double
    var createdAt: Date

    init(id: UUID = UUID(), name: String, region: String, latitude: Double, longitude: Double, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.region = region
        self.latitude = latitude
        self.longitude = longitude
        self.createdAt = createdAt
    }
}

enum FeelResponse: String, CaseIterable, Identifiable {
    case tooCold = "Too cold"
    case comfortable = "Comfortable"
    case tooWarm = "Too warm"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .tooCold: "snowflake"
        case .comfortable: "checkmark"
        case .tooWarm: "sun.max.fill"
        }
    }
}

struct ForecastSnapshot: Sendable {
    let locationName: String
    let isSample: Bool
    let updatedAt: Date
    let current: CurrentConditions
    let hourly: [HourlyConditions]
    let daily: [DailyConditions]

    static let sample = ForecastSnapshot(
        locationName: "New York",
        isSample: true,
        updatedAt: .now,
        current: CurrentConditions(temperature: 72, apparentTemperature: 73, condition: "Partly Cloudy", symbolName: "cloud.sun.fill", precipitationChance: 0.18, humidity: 0.54, windSpeed: 7, windDirection: "SW", uvIndex: 5, visibility: 10, pressure: 1017),
        hourly: (0..<12).map { offset in
            HourlyConditions(
                date: Calendar.current.date(byAdding: .hour, value: offset, to: .now) ?? .now,
                temperature: [72, 74, 76, 77, 78, 77, 75, 72, 70, 69, 68, 67][offset],
                apparentTemperature: [73, 75, 77, 79, 80, 79, 76, 72, 70, 69, 68, 67][offset],
                symbolName: offset < 5 ? "cloud.sun.fill" : (offset < 8 ? "cloud.fill" : "moon.stars.fill"),
                precipitationChance: offset == 6 ? 0.32 : 0.12,
                humidity: [0.54, 0.52, 0.51, 0.50, 0.50, 0.53, 0.57, 0.60, 0.62, 0.64, 0.65, 0.66][offset],
                windSpeed: [7, 7, 8, 9, 10, 9, 8, 7, 6, 6, 5, 5][offset]
            )
        },
        daily: (0..<7).map { offset in
            let highs = [78, 75, 81, 83, 79, 76, 80]
            let lows = [66, 64, 67, 69, 65, 63, 66]
            return DailyConditions(
                date: Calendar.current.date(byAdding: .day, value: offset, to: .now) ?? .now,
                low: lows[offset], high: highs[offset],
                symbolName: ["cloud.sun.fill", "cloud.rain.fill", "sun.max.fill", "sun.max.fill", "cloud.sun.fill", "cloud.fill", "sun.max.fill"][offset],
                precipitationChance: [0.18, 0.62, 0.08, 0.05, 0.20, 0.25, 0.10][offset]
            )
        }
    )

    static var screenshotPreview: ForecastSnapshot {
        ForecastSnapshot(
            locationName: sample.locationName,
            isSample: false,
            updatedAt: sample.updatedAt,
            current: sample.current,
            hourly: sample.hourly,
            daily: sample.daily
        )
    }
}

struct CurrentConditions: Sendable {
    let temperature: Int
    let apparentTemperature: Int
    let condition: String
    let symbolName: String
    let precipitationChance: Double
    let humidity: Double
    let windSpeed: Int
    let windDirection: String
    let uvIndex: Int
    let visibility: Int
    let pressure: Int
}

struct HourlyConditions: Identifiable, Sendable {
    let date: Date
    let temperature: Int
    let apparentTemperature: Int
    let symbolName: String
    let precipitationChance: Double
    let humidity: Double
    let windSpeed: Int
    var id: Date { date }

    init(
        date: Date,
        temperature: Int,
        apparentTemperature: Int? = nil,
        symbolName: String,
        precipitationChance: Double,
        humidity: Double = 0.5,
        windSpeed: Int = 0
    ) {
        self.date = date
        self.temperature = temperature
        self.apparentTemperature = apparentTemperature ?? temperature
        self.symbolName = symbolName
        self.precipitationChance = precipitationChance
        self.humidity = humidity
        self.windSpeed = windSpeed
    }
}

struct DailyConditions: Identifiable, Sendable {
    let date: Date
    let low: Int
    let high: Int
    let symbolName: String
    let precipitationChance: Double
    var id: Date { date }
}
