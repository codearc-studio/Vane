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
    var checkInFrequencyRaw: String = CheckInFrequency.recommended.rawValue

    init(createdAt: Date = .now, temperaturePreference: Double = 0, windSensitivity: Double = 0.5, humiditySensitivity: Double = 0.5, enjoysRain: Bool = false, usesFeelsLikeTemperature: Bool = true, checkInFrequency: CheckInFrequency = .recommended) {
        self.createdAt = createdAt
        self.temperaturePreference = temperaturePreference
        self.windSensitivity = windSensitivity
        self.humiditySensitivity = humiditySensitivity
        self.enjoysRain = enjoysRain
        self.usesFeelsLikeTemperature = usesFeelsLikeTemperature
        self.checkInFrequencyRaw = checkInFrequency.rawValue
    }

    var checkInFrequency: CheckInFrequency {
        get { CheckInFrequency(rawValue: checkInFrequencyRaw) ?? .recommended }
        set { checkInFrequencyRaw = newValue.rawValue }
    }
}

@Model
final class WeatherCheckIn {
    var createdAt: Date
    var temperature: Double
    var apparentTemperature: Double
    var humidity: Double
    var windSpeed: Double
    /// Stable storage code. Legacy builds stored display text; `feelResponse` migrates it safely.
    var response: String
    var contextRaw: String = ""
    var dewPoint: Double?
    var windGust: Double?
    var uvIndex: Int?
    var cloudCover: Double?
    var isTravel: Bool = false

    init(createdAt: Date = .now, temperature: Double, apparentTemperature: Double, humidity: Double, windSpeed: Double, response: FeelResponse, context: Set<FeelContext> = [], dewPoint: Double? = nil, windGust: Double? = nil, uvIndex: Int? = nil, cloudCover: Double? = nil, isTravel: Bool = false) {
        self.createdAt = createdAt
        self.temperature = temperature
        self.apparentTemperature = apparentTemperature
        self.humidity = humidity
        self.windSpeed = windSpeed
        self.response = response.rawValue
        self.contextRaw = context.map(\.rawValue).sorted().joined(separator: ",")
        self.dewPoint = dewPoint
        self.windGust = windGust
        self.uvIndex = uvIndex
        self.cloudCover = cloudCover
        self.isTravel = isTravel
    }

    /// Unknown values are ignored instead of silently becoming comfortable evidence.
    var feelResponse: FeelResponse? { FeelResponse(storedValue: response) }
    var contexts: Set<FeelContext> { Set(contextRaw.split(separator: ",").compactMap { FeelContext(rawValue: String($0)) }) }
}

@Model
final class SavedPlace {
    var id: UUID
    var name: String
    var region: String
    var latitude: Double
    var longitude: Double
    var createdAt: Date
    var sortOrder: Int = 0

    init(id: UUID = UUID(), name: String, region: String, latitude: Double, longitude: Double, createdAt: Date = .now, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.region = region
        self.latitude = latitude
        self.longitude = longitude
        self.createdAt = createdAt
        self.sortOrder = sortOrder
    }
}

enum FeelResponse: String, CaseIterable, Identifiable, Sendable {
    case freezing = "freezing"
    case cold = "cold"
    case chilly = "chilly"
    case comfortable = "comfortable"
    case warm = "warm"
    case hot = "hot"
    case veryHot = "very_hot"

    var id: String { rawValue }

    init?(storedValue: String) {
        if let current = Self(rawValue: storedValue) { self = current; return }
        switch storedValue.lowercased() {
        case "too cold": self = .cold
        case "just right", "comfortable": self = .comfortable
        case "too warm": self = .warm
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .freezing: "Freezing"
        case .cold: "Cold"
        case .chilly: "Chilly"
        case .comfortable: "Comfortable"
        case .warm: "Warm"
        case .hot: "Hot"
        case .veryHot: "Very Hot"
        }
    }

    var symbol: String {
        switch self {
        case .freezing: "thermometer.snowflake"
        case .cold: "snowflake"
        case .chilly: "wind"
        case .comfortable: "checkmark"
        case .warm: "sun.min.fill"
        case .hot: "sun.max.fill"
        case .veryHot: "thermometer.sun.fill"
        }
    }

    var comfortOffset: Double {
        switch self {
        case .freezing: 12
        case .cold: 8
        case .chilly: 4
        case .comfortable: 0
        case .warm: -4
        case .hot: -8
        case .veryHot: -12
        }
    }

    var isCold: Bool { [.freezing, .cold, .chilly].contains(self) }
    var isWarm: Bool { [.warm, .hot, .veryHot].contains(self) }
}

enum FeelContext: String, CaseIterable, Identifiable, Sendable {
    case humidity, wind, sun, dampness, nothing
    var id: String { rawValue }
    var title: String {
        switch self {
        case .humidity: "Humidity"
        case .wind: "Wind"
        case .sun: "Sun"
        case .dampness: "Rain / dampness"
        case .nothing: "Nothing noticeable"
        }
    }
    var symbol: String {
        switch self {
        case .humidity: "humidity.fill"
        case .wind: "wind"
        case .sun: "sun.max.fill"
        case .dampness: "cloud.rain.fill"
        case .nothing: "minus.circle"
        }
    }
}

enum CheckInFrequency: String, CaseIterable, Identifiable {
    case more, recommended, less, minimal
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var minimumHours: Double {
        switch self {
        case .more: 6
        case .recommended: 18
        case .less: 48
        case .minimal: 120
        }
    }
}

struct ForecastSnapshot: Sendable {
    let locationName: String
    let sourceID: String
    let isSample: Bool
    let isPlaceholder: Bool
    let updatedAt: Date
    let current: CurrentConditions
    let hourly: [HourlyConditions]
    let daily: [DailyConditions]
    let alerts: [WeatherAlertSnapshot]

    init(locationName: String, sourceID: String = "current", isSample: Bool, isPlaceholder: Bool = false, updatedAt: Date, current: CurrentConditions, hourly: [HourlyConditions], daily: [DailyConditions], alerts: [WeatherAlertSnapshot] = []) {
        self.locationName = locationName
        self.sourceID = sourceID
        self.isSample = isSample
        self.isPlaceholder = isPlaceholder
        self.updatedAt = updatedAt
        self.current = current
        self.hourly = hourly
        self.daily = daily
        self.alerts = alerts
    }

    static let empty = ForecastSnapshot(locationName: "Choose a location", sourceID: "none", isSample: false, isPlaceholder: true, updatedAt: .distantPast, current: CurrentConditions(temperature: 0, apparentTemperature: 0, condition: "", symbolName: "location.slash", precipitationChance: 0, humidity: 0, windSpeed: 0, windDirection: "", uvIndex: 0, visibility: 0, pressure: 0), hourly: [], daily: [])

    static let sample = ForecastSnapshot(
        locationName: "New York", sourceID: "sample", isSample: true, updatedAt: .now,
        current: CurrentConditions(temperature: 72, apparentTemperature: 73, condition: "Partly Cloudy", symbolName: "cloud.sun.fill", precipitationChance: 0.18, humidity: 0.54, windSpeed: 7, windDirection: "SW", uvIndex: 5, visibility: 10, pressure: 1017, dewPoint: 55, windGust: 12, cloudCover: 0.45, isDaylight: true),
        hourly: (0..<24).map { offset in
            HourlyConditions(date: Calendar.current.date(byAdding: .hour, value: offset, to: .now) ?? .now, temperature: 72 + min(offset, 5), apparentTemperature: 73 + min(offset, 5), symbolName: offset < 8 ? "cloud.sun.fill" : "cloud.fill", condition: offset < 8 ? "Partly Cloudy" : "Cloudy", precipitationChance: offset == 6 ? 0.32 : 0.12, humidity: 0.54, windSpeed: 7, windGust: 12, dewPoint: 55, cloudCover: 0.45, isDaylight: offset < 10)
        },
        daily: (0..<10).map { offset in
            DailyConditions(date: Calendar.current.date(byAdding: .day, value: offset, to: .now) ?? .now, low: 64 + offset % 3, high: 76 + offset % 6, symbolName: offset == 1 ? "cloud.rain.fill" : "cloud.sun.fill", condition: offset == 1 ? "Rain" : "Partly Cloudy", precipitationChance: offset == 1 ? 0.62 : 0.18, sunrise: Calendar.current.date(bySettingHour: 6, minute: 12, second: 0, of: .now), sunset: Calendar.current.date(bySettingHour: 19, minute: 52, second: 0, of: .now), uvIndex: 5, windSpeed: 9, windGust: 15, precipitationAmount: offset == 1 ? 0.28 : 0)
        }
    )

    static var screenshotPreview: ForecastSnapshot { ForecastSnapshot(locationName: sample.locationName, sourceID: sample.sourceID, isSample: false, updatedAt: sample.updatedAt, current: sample.current, hourly: sample.hourly, daily: sample.daily) }
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
    var dewPoint: Int = 0
    var windGust: Int = 0
    var precipitationType: String = "None"
    var precipitationIntensity: Double = 0
    var cloudCover: Double = 0
    var isDaylight: Bool = true
}

struct HourlyConditions: Identifiable, Sendable {
    let date: Date
    let temperature: Int
    let apparentTemperature: Int
    let symbolName: String
    let condition: String
    let precipitationChance: Double
    let humidity: Double
    let windSpeed: Int
    let windGust: Int
    let dewPoint: Int
    let cloudCover: Double
    let isDaylight: Bool
    var id: Date { date }

    init(date: Date, temperature: Int, apparentTemperature: Int? = nil, symbolName: String, condition: String = "", precipitationChance: Double, humidity: Double = 0.5, windSpeed: Int = 0, windGust: Int = 0, dewPoint: Int = 0, cloudCover: Double = 0, isDaylight: Bool = true) {
        self.date = date; self.temperature = temperature; self.apparentTemperature = apparentTemperature ?? temperature; self.symbolName = symbolName; self.condition = condition; self.precipitationChance = precipitationChance; self.humidity = humidity; self.windSpeed = windSpeed; self.windGust = windGust; self.dewPoint = dewPoint; self.cloudCover = cloudCover; self.isDaylight = isDaylight
    }
}

struct DailyConditions: Identifiable, Sendable, Hashable {
    let date: Date
    let low: Int
    let high: Int
    let symbolName: String
    let condition: String
    let precipitationChance: Double
    let sunrise: Date?
    let sunset: Date?
    let uvIndex: Int
    let windSpeed: Int
    let windGust: Int
    let precipitationAmount: Double
    var id: Date { date }

    init(date: Date, low: Int, high: Int, symbolName: String, condition: String = "", precipitationChance: Double, sunrise: Date? = nil, sunset: Date? = nil, uvIndex: Int = 0, windSpeed: Int = 0, windGust: Int = 0, precipitationAmount: Double = 0) {
        self.date = date; self.low = low; self.high = high; self.symbolName = symbolName; self.condition = condition; self.precipitationChance = precipitationChance; self.sunrise = sunrise; self.sunset = sunset; self.uvIndex = uvIndex; self.windSpeed = windSpeed; self.windGust = windGust; self.precipitationAmount = precipitationAmount
    }
}

struct WeatherAlertSnapshot: Identifiable, Sendable {
    let id: String
    let summary: String
    let severity: String
    let region: String?
    let source: String
    let detailsURL: URL
}

struct WeatherAttributionInfo: Sendable {
    let serviceName: String
    let legalPageURL: URL
    let combinedMarkLightURL: URL
    let combinedMarkDarkURL: URL
}

enum TemperatureUnitPreference: String, CaseIterable, Identifiable {
    case fahrenheit, celsius
    var id: String { rawValue }
    var title: String { self == .fahrenheit ? "Fahrenheit" : "Celsius" }
    func value(_ fahrenheit: Int) -> Int { self == .fahrenheit ? fahrenheit : Int(((Double(fahrenheit) - 32) * 5 / 9).rounded()) }
    var symbol: String { self == .fahrenheit ? "°F" : "°C" }
}

enum WindUnitPreference: String, CaseIterable, Identifiable {
    case milesPerHour, kilometersPerHour
    var id: String { rawValue }
    var title: String { self == .milesPerHour ? "mph" : "km/h" }
    func value(_ mph: Int) -> Int { self == .milesPerHour ? mph : Int((Double(mph) * 1.60934).rounded()) }
}

enum PressureUnitPreference: String, CaseIterable, Identifiable {
    case hectopascals, inchesOfMercury
    var id: String { rawValue }
    var title: String { self == .hectopascals ? "hPa" : "inHg" }
    func formatted(_ hPa: Int) -> String { self == .hectopascals ? "\(hPa) hPa" : String(format: "%.2f inHg", Double(hPa) * 0.02953) }
}

enum PrecipitationUnitPreference: String, CaseIterable, Identifiable {
    case inches, millimeters
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    func formatted(_ inches: Double) -> String { self == .inches ? String(format: "%.2f in", inches) : String(format: "%.1f mm", inches * 25.4) }
}
