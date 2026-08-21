import Foundation
import SwiftData

@Model
final class WeatherProfile {
    var createdAt: Date = Date.now
    var temperaturePreference: Double = 0
    var windSensitivity: Double = 0.5
    var humiditySensitivity: Double = 0.5
    var usesFeelsLikeTemperature: Bool = true
    var checkInFrequencyRaw: String = CheckInFrequency.recommended.rawValue

    init(createdAt: Date = .now, temperaturePreference: Double = 0, windSensitivity: Double = 0.5, humiditySensitivity: Double = 0.5, usesFeelsLikeTemperature: Bool = true, checkInFrequency: CheckInFrequency = .recommended) {
        self.createdAt = createdAt
        self.temperaturePreference = temperaturePreference
        self.windSensitivity = windSensitivity
        self.humiditySensitivity = humiditySensitivity
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
    var createdAt: Date = Date.now
    var temperature: Double = 0
    var apparentTemperature: Double = 0
    var humidity: Double = 0
    var windSpeed: Double = 0
    /// Stable storage code. Legacy builds stored display text; `feelResponse` migrates it safely.
    var response: String = ""
    var contextRaw: String = ""
    var dewPoint: Double?
    var windGust: Double?
    var uvIndex: Int?
    var cloudCover: Double?
    var isTravel: Bool = false
    var precipitationKindRaw: String = PrecipitationKind.none.rawValue
    var precipitationChance: Double = 0
    var timeZoneIdentifier: String?
    var locationName: String?

    init(createdAt: Date = .now, temperature: Double, apparentTemperature: Double, humidity: Double, windSpeed: Double, response: FeelResponse, context: Set<FeelContext> = [], dewPoint: Double? = nil, windGust: Double? = nil, uvIndex: Int? = nil, cloudCover: Double? = nil, pressure: Int? = nil, visibility: Int? = nil, isDaylight: Bool? = nil, isTravel: Bool = false, precipitationKind: PrecipitationKind = .none, precipitationChance: Double = 0, timeZoneIdentifier: String? = nil, locationName: String? = nil) {
        self.createdAt = createdAt
        self.temperature = temperature
        self.apparentTemperature = apparentTemperature
        self.humidity = humidity
        self.windSpeed = windSpeed
        self.response = response.rawValue
        var contextValues = context.map(\.rawValue)
        if let pressure { contextValues.append("wx_pressure_\(pressure)") }
        if let visibility { contextValues.append("wx_visibility_\(visibility)") }
        if let isDaylight { contextValues.append("wx_daylight_\(isDaylight ? 1 : 0)") }
        self.contextRaw = contextValues.sorted().joined(separator: ",")
        self.dewPoint = dewPoint
        self.windGust = windGust
        self.uvIndex = uvIndex
        self.cloudCover = cloudCover
        self.isTravel = isTravel
        self.precipitationKindRaw = precipitationKind.rawValue
        self.precipitationChance = precipitationChance
        self.timeZoneIdentifier = timeZoneIdentifier
        self.locationName = locationName
    }

    /// Unknown values are ignored instead of silently becoming comfortable evidence.
    var feelResponse: FeelResponse? { FeelResponse(storedValue: response) }
    var contexts: Set<FeelContext> { Set(contextRaw.split(separator: ",").compactMap { FeelContext(rawValue: String($0)) }) }
    var precipitationKind: PrecipitationKind { PrecipitationKind(rawValue: precipitationKindRaw) ?? .none }
    var conditionFingerprint: WeatherConditionFingerprint {
        let values = contextRaw.split(separator: ",").map(String.init)
        return WeatherConditionFingerprint(
            pressure: values.firstValue(after: "wx_pressure_").flatMap(Int.init),
            visibility: values.firstValue(after: "wx_visibility_").flatMap(Int.init),
            isDaylight: values.firstValue(after: "wx_daylight_").flatMap(Int.init).map { $0 == 1 }
        )
    }
}

struct WeatherConditionFingerprint: Sendable {
    let pressure: Int?
    let visibility: Int?
    let isDaylight: Bool?
}

private extension Array where Element == String {
    nonisolated func firstValue(after prefix: String) -> String? {
        first(where: { $0.hasPrefix(prefix) }).map { String($0.dropFirst(prefix.count)) }
    }
}

@Model
final class SavedPlace {
    var id: UUID = UUID()
    var name: String = ""
    var region: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    var createdAt: Date = Date.now
    var sortOrder: Int = 0
    var timeZoneIdentifier: String?
    var isHome: Bool = false

    init(id: UUID = UUID(), name: String, region: String, latitude: Double, longitude: Double, createdAt: Date = .now, sortOrder: Int = 0, timeZoneIdentifier: String? = nil, isHome: Bool = false) {
        self.id = id
        self.name = name
        self.region = region
        self.latitude = latitude
        self.longitude = longitude
        self.createdAt = createdAt
        self.sortOrder = sortOrder
        self.timeZoneIdentifier = timeZoneIdentifier
        self.isHome = isHome
    }
}

nonisolated enum FeelResponse: String, CaseIterable, Identifiable, Sendable {
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
        case .comfortable: "sparkles"
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

nonisolated enum FeelContext: String, CaseIterable, Identifiable, Sendable {
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

nonisolated enum CheckInFrequency: String, CaseIterable, Identifiable, Sendable {
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
    let timeZoneIdentifier: String
    let isTravelLocation: Bool
    let latitude: Double
    let longitude: Double
    let locationAccuracy: Double?

    init(locationName: String, sourceID: String = "current", isSample: Bool, isPlaceholder: Bool = false, updatedAt: Date, current: CurrentConditions, hourly: [HourlyConditions], daily: [DailyConditions], alerts: [WeatherAlertSnapshot] = [], timeZoneIdentifier: String = TimeZone.current.identifier, isTravelLocation: Bool = false, latitude: Double = 0, longitude: Double = 0, locationAccuracy: Double? = nil) {
        self.locationName = locationName
        self.sourceID = sourceID
        self.isSample = isSample
        self.isPlaceholder = isPlaceholder
        self.updatedAt = updatedAt
        self.current = current
        self.hourly = hourly
        self.daily = daily
        self.alerts = alerts
        self.timeZoneIdentifier = timeZoneIdentifier
        self.isTravelLocation = isTravelLocation
        self.latitude = latitude
        self.longitude = longitude
        self.locationAccuracy = locationAccuracy
    }

    static let empty = ForecastSnapshot(locationName: "Choose a location", sourceID: "none", isSample: false, isPlaceholder: true, updatedAt: .distantPast, current: CurrentConditions(temperature: 0, apparentTemperature: 0, condition: "", symbolName: "location.slash", precipitationChance: 0, humidity: 0, windSpeed: 0, windDirection: "", uvIndex: 0, visibility: 0, pressure: 0), hourly: [], daily: [])

    static let sample = ForecastSnapshot(
        locationName: "New York", sourceID: "sample", isSample: true, updatedAt: .now,
        current: CurrentConditions(temperature: 72, apparentTemperature: 73, condition: "Partly Cloudy", symbolName: "cloud.sun.fill", precipitationChance: 0.18, humidity: 0.54, windSpeed: 7, windDirection: "SW", windDirectionDegrees: 225, uvIndex: 5, visibility: 10, pressure: 1017, pressureTrend: "Steady", dewPoint: 55, windGust: 12, cloudCover: 0.45, isDaylight: true),
        hourly: (0..<24).map { offset in
            HourlyConditions(date: Calendar.current.date(byAdding: .hour, value: offset, to: .now) ?? .now, temperature: 72 + min(offset, 5), apparentTemperature: 73 + min(offset, 5), symbolName: offset < 8 ? "cloud.sun.fill" : "cloud.fill", condition: offset < 8 ? "Partly Cloudy" : "Cloudy", precipitationChance: offset == 6 ? 0.32 : 0.12, humidity: 0.54, windSpeed: 7, windGust: 12, dewPoint: 55, cloudCover: 0.45, isDaylight: offset < 10)
        },
        daily: (0..<10).map { offset in
            DailyConditions(date: Calendar.current.date(byAdding: .day, value: offset, to: .now) ?? .now, low: 64 + offset % 3, high: 76 + offset % 6, symbolName: offset == 1 ? "cloud.rain.fill" : "cloud.sun.fill", condition: offset == 1 ? "Rain" : "Partly Cloudy", precipitationChance: offset == 1 ? 0.62 : 0.18, sunrise: Calendar.current.date(bySettingHour: 6, minute: 12, second: 0, of: .now), sunset: Calendar.current.date(bySettingHour: 19, minute: 52, second: 0, of: .now), uvIndex: 5, windSpeed: 9, windGust: 15, precipitationAmount: offset == 1 ? 0.28 : 0, civilDawn: Calendar.current.date(bySettingHour: 5, minute: 42, second: 0, of: .now), solarNoon: Calendar.current.date(bySettingHour: 13, minute: 2, second: 0, of: .now), civilDusk: Calendar.current.date(bySettingHour: 20, minute: 22, second: 0, of: .now), moonPhase: "Waxing Crescent", moonrise: Calendar.current.date(bySettingHour: 10, minute: 4, second: 0, of: .now), moonset: Calendar.current.date(bySettingHour: 22, minute: 14, second: 0, of: .now))
        },
        latitude: 40.7128,
        longitude: -74.006
    )

    static var screenshotPreview: ForecastSnapshot { ForecastSnapshot(locationName: sample.locationName, sourceID: sample.sourceID, isSample: false, updatedAt: sample.updatedAt, current: sample.current, hourly: sample.hourly, daily: sample.daily, latitude: sample.latitude, longitude: sample.longitude) }

    static var alertScreenshotPreview: ForecastSnapshot {
        let now = Date()
        return ForecastSnapshot(
            locationName: "Philadelphia",
            sourceID: "current",
            isSample: false,
            updatedAt: now,
            current: sample.current,
            hourly: sample.hourly,
            daily: sample.daily,
            alerts: [
                WeatherAlertSnapshot(id: "preview-severe", summary: "Severe Thunderstorm Warning", severity: "Severe", region: "Philadelphia County", source: "National Weather Service", detailsURL: URL(string: "https://weather.gov")!, issuedAt: now.addingTimeInterval(-1_800), expiresAt: now.addingTimeInterval(5_400)),
                WeatherAlertSnapshot(id: "preview-moderate", summary: "Flood Watch", severity: "Moderate", region: "Southeastern Pennsylvania", source: "National Weather Service", detailsURL: URL(string: "https://weather.gov")!, issuedAt: now.addingTimeInterval(-3_600), expiresAt: now.addingTimeInterval(10_800))
            ],
            latitude: 39.9526,
            longitude: -75.1652
        )
    }

    static var nightScreenshotPreview: ForecastSnapshot {
        let night = CurrentConditions(
            temperature: 66,
            apparentTemperature: 66,
            condition: "Clear",
            symbolName: "moon.stars.fill",
            precipitationChance: 0.05,
            humidity: 0.58,
            windSpeed: 4,
            windDirection: "NW",
            windDirectionDegrees: 315,
            uvIndex: 0,
            visibility: 10,
            pressure: 1016,
            pressureTrend: "Steady",
            dewPoint: 52,
            windGust: 7,
            precipitationKind: .none,
            cloudCover: 0.08,
            isDaylight: false
        )
        return ForecastSnapshot(locationName: sample.locationName, sourceID: sample.sourceID, isSample: false, updatedAt: .now, current: night, hourly: sample.hourly, daily: sample.daily, latitude: sample.latitude, longitude: sample.longitude)
    }

    var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .current }

    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = timeZone
        return value
    }

}

nonisolated enum PrecipitationKind: String, Sendable {
    case none, rain, snow, mixed
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
    var windDirectionDegrees: Double = 0
    let uvIndex: Int
    let visibility: Int
    let pressure: Int
    var pressureTrend: String = "Steady"
    var dewPoint: Int = 0
    var windGust: Int = 0
    var precipitationKind: PrecipitationKind = .none
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
    let precipitationKind: PrecipitationKind
    var id: Date { date }

    init(date: Date, temperature: Int, apparentTemperature: Int? = nil, symbolName: String, condition: String = "", precipitationChance: Double, humidity: Double = 0.5, windSpeed: Int = 0, windGust: Int = 0, dewPoint: Int = 0, cloudCover: Double = 0, isDaylight: Bool = true, precipitationKind: PrecipitationKind? = nil) {
        self.date = date; self.temperature = temperature; self.apparentTemperature = apparentTemperature ?? temperature; self.symbolName = symbolName; self.condition = condition; self.precipitationChance = precipitationChance; self.humidity = humidity; self.windSpeed = windSpeed; self.windGust = windGust; self.dewPoint = dewPoint; self.cloudCover = cloudCover; self.isDaylight = isDaylight; self.precipitationKind = precipitationKind ?? Self.inferPrecipitationKind(symbolName: symbolName, condition: condition)
    }

    private static func inferPrecipitationKind(symbolName: String, condition: String) -> PrecipitationKind {
        let value = (symbolName + " " + condition).lowercased()
        if value.contains("sleet") || value.contains("mixed") || value.contains("wintry") { return .mixed }
        if value.contains("snow") || value.contains("flurr") { return .snow }
        if value.contains("rain") || value.contains("drizzle") || value.contains("shower") { return .rain }
        return .none
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
    var civilDawn: Date? = nil
    var solarNoon: Date? = nil
    var civilDusk: Date? = nil
    var moonPhase: String = ""
    var moonrise: Date? = nil
    var moonset: Date? = nil
    var id: Date { date }

    init(date: Date, low: Int, high: Int, symbolName: String, condition: String = "", precipitationChance: Double, sunrise: Date? = nil, sunset: Date? = nil, uvIndex: Int = 0, windSpeed: Int = 0, windGust: Int = 0, precipitationAmount: Double = 0, civilDawn: Date? = nil, solarNoon: Date? = nil, civilDusk: Date? = nil, moonPhase: String = "", moonrise: Date? = nil, moonset: Date? = nil) {
        self.date = date; self.low = low; self.high = high; self.symbolName = symbolName; self.condition = condition; self.precipitationChance = precipitationChance; self.sunrise = sunrise; self.sunset = sunset; self.uvIndex = uvIndex; self.windSpeed = windSpeed; self.windGust = windGust; self.precipitationAmount = precipitationAmount; self.civilDawn = civilDawn; self.solarNoon = solarNoon; self.civilDusk = civilDusk; self.moonPhase = moonPhase; self.moonrise = moonrise; self.moonset = moonset
    }
}

nonisolated enum WeatherAlertSeverity: String, Sendable, CaseIterable {
    case unknown, minor, moderate, severe, extreme

    init(providerValue: String) {
        self = Self(rawValue: providerValue.lowercased()) ?? .unknown
    }

    var title: String { self == .unknown ? "Official" : rawValue.capitalized }

    var priority: Int {
        switch self {
        case .unknown: 0
        case .minor: 1
        case .moderate: 2
        case .severe: 3
        case .extreme: 4
        }
    }
}

struct WeatherAlertSnapshot: Identifiable, Sendable {
    let id: String
    let summary: String
    let severity: String
    let region: String?
    let source: String
    let detailsURL: URL
    let issuedAt: Date?
    let expiresAt: Date?

    init(id: String, summary: String, severity: String, region: String?, source: String, detailsURL: URL, issuedAt: Date? = nil, expiresAt: Date? = nil) {
        self.id = id
        self.summary = summary
        self.severity = severity
        self.region = region
        self.source = source
        self.detailsURL = detailsURL
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
    }

    var severityLevel: WeatherAlertSeverity { WeatherAlertSeverity(providerValue: severity) }
    var isActive: Bool { expiresAt.map { $0 > .now } ?? true }

    static func priorityOrder(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.isActive != rhs.isActive { return lhs.isActive }
        if lhs.severityLevel.priority != rhs.severityLevel.priority { return lhs.severityLevel.priority > rhs.severityLevel.priority }
        return (lhs.expiresAt ?? .distantFuture) < (rhs.expiresAt ?? .distantFuture)
    }
}

struct WeatherAttributionInfo: Sendable {
    let serviceName: String
    let legalPageURL: URL
    let combinedMarkLightURL: URL
    let combinedMarkDarkURL: URL
}

nonisolated enum TemperatureUnitPreference: String, CaseIterable, Identifiable, Sendable {
    case fahrenheit, celsius
    var id: String { rawValue }
    var title: String { self == .fahrenheit ? "Fahrenheit" : "Celsius" }
    func value(_ fahrenheit: Int) -> Int { self == .fahrenheit ? fahrenheit : Int(((Double(fahrenheit) - 32) * 5 / 9).rounded()) }
    var symbol: String { self == .fahrenheit ? "°F" : "°C" }
    static var localizedDefault: Self { Locale.autoupdatingCurrent.measurementSystem == .us ? .fahrenheit : .celsius }
}

nonisolated enum WindUnitPreference: String, CaseIterable, Identifiable, Sendable {
    case milesPerHour, kilometersPerHour
    var id: String { rawValue }
    var title: String { self == .milesPerHour ? "mph" : "km/h" }
    func value(_ mph: Int) -> Int { self == .milesPerHour ? mph : Int((Double(mph) * 1.60934).rounded()) }
    static var localizedDefault: Self { Locale.autoupdatingCurrent.measurementSystem == .metric ? .kilometersPerHour : .milesPerHour }
}

nonisolated enum PressureUnitPreference: String, CaseIterable, Identifiable, Sendable {
    case hectopascals, inchesOfMercury
    var id: String { rawValue }
    var title: String { self == .hectopascals ? "hPa" : "inHg" }
    func formatted(_ hPa: Int) -> String { self == .hectopascals ? "\(hPa) hPa" : String(format: "%.2f inHg", Double(hPa) * 0.02953) }
    static var localizedDefault: Self { Locale.autoupdatingCurrent.measurementSystem == .us ? .inchesOfMercury : .hectopascals }
}

nonisolated enum PrecipitationUnitPreference: String, CaseIterable, Identifiable, Sendable {
    case inches, millimeters
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    func formatted(_ inches: Double) -> String { self == .inches ? String(format: "%.2f in", inches) : String(format: "%.1f mm", inches * 25.4) }
    static var localizedDefault: Self { Locale.autoupdatingCurrent.measurementSystem == .us ? .inches : .millimeters }
}
