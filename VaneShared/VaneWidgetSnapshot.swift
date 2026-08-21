import Foundation

nonisolated enum VaneWidgetConstants {
    static let appGroup = "group.com.codearc.vane"
    static let snapshotFilename = "vane-widget-snapshot.json"
    static let watchSnapshotKey = "vane.snapshot"
    static let watchSnapshotRequestKey = "vane.requestSnapshot"
    static let nowKind = "VaneNowWidget"
    static let forecastKind = "VaneForecastWidget"
    static let detailsKind = "VaneDetailsWidget"
    static let sunKind = "VaneSunWidget"
    static let senseKind = "VaneSenseWidget"
    static let watchNowKind = "VaneWatchNowComplication"
    static let watchConditionsKind = "VaneWatchConditionsComplication"
    static let watchSunKind = "VaneWatchSunComplication"
    static let watchSenseKind = "VaneWatchSenseComplication"
}

nonisolated struct VaneWidgetSnapshot: Codable, Equatable, Sendable {
    nonisolated struct Hour: Codable, Equatable, Identifiable, Sendable {
        let date: Date
        let temperature: Int
        let apparentTemperature: Int
        let symbolName: String
        let condition: String
        let precipitationChance: Double
        let humidity: Double
        let windSpeed: Int
        let isDaylight: Bool

        var id: Date { date }
    }

    nonisolated struct Day: Codable, Equatable, Identifiable, Sendable {
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

        var id: Date { date }
    }

    let schemaVersion: Int
    let locationName: String
    let sourceID: String
    let updatedAt: Date
    let latitude: Double
    let longitude: Double
    let timeZoneIdentifier: String
    let temperature: Int
    let apparentTemperature: Int
    let condition: String
    let symbolName: String
    let precipitationChance: Double
    let humidity: Double
    let windSpeed: Int
    let windGust: Int
    let windDirection: String
    let uvIndex: Int
    let visibility: Int
    let pressure: Int
    let dewPoint: Int
    let isDaylight: Bool
    let hourly: [Hour]
    let daily: [Day]
    let alertSummary: String?
    let guidanceHeadline: String?
    let guidanceDetail: String?
    let guidanceSymbol: String?
    let guidanceIsPersonalized: Bool
    let guidanceIsEstimate: Bool?
    let guidanceCalibrationLabel: String?
    let guidanceActionText: String?
    let temperatureUnit: String
    let windUnit: String
    let pressureUnit: String
    let precipitationUnit: String

    init(
        schemaVersion: Int = 1,
        locationName: String,
        sourceID: String,
        updatedAt: Date,
        latitude: Double,
        longitude: Double,
        timeZoneIdentifier: String,
        temperature: Int,
        apparentTemperature: Int,
        condition: String,
        symbolName: String,
        precipitationChance: Double,
        humidity: Double,
        windSpeed: Int,
        windGust: Int,
        windDirection: String,
        uvIndex: Int,
        visibility: Int,
        pressure: Int,
        dewPoint: Int,
        isDaylight: Bool,
        hourly: [Hour],
        daily: [Day],
        alertSummary: String?,
        guidanceHeadline: String?,
        guidanceDetail: String?,
        guidanceSymbol: String?,
        guidanceIsPersonalized: Bool,
        guidanceIsEstimate: Bool? = nil,
        guidanceCalibrationLabel: String? = nil,
        guidanceActionText: String? = nil,
        temperatureUnit: String,
        windUnit: String,
        pressureUnit: String,
        precipitationUnit: String
    ) {
        self.schemaVersion = schemaVersion
        self.locationName = locationName
        self.sourceID = sourceID
        self.updatedAt = updatedAt
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneIdentifier = timeZoneIdentifier
        self.temperature = temperature
        self.apparentTemperature = apparentTemperature
        self.condition = condition
        self.symbolName = symbolName
        self.precipitationChance = precipitationChance
        self.humidity = humidity
        self.windSpeed = windSpeed
        self.windGust = windGust
        self.windDirection = windDirection
        self.uvIndex = uvIndex
        self.visibility = visibility
        self.pressure = pressure
        self.dewPoint = dewPoint
        self.isDaylight = isDaylight
        self.hourly = hourly
        self.daily = daily
        self.alertSummary = alertSummary
        self.guidanceHeadline = guidanceHeadline
        self.guidanceDetail = guidanceDetail
        self.guidanceSymbol = guidanceSymbol
        self.guidanceIsPersonalized = guidanceIsPersonalized
        self.guidanceIsEstimate = guidanceIsEstimate
        self.guidanceCalibrationLabel = guidanceCalibrationLabel
        self.guidanceActionText = guidanceActionText
        self.temperatureUnit = temperatureUnit
        self.windUnit = windUnit
        self.pressureUnit = pressureUnit
        self.precipitationUnit = precipitationUnit
    }

    var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .current }
    var isStale: Bool { Date().timeIntervalSince(updatedAt) > 90 * 60 }
    var today: Day? { daily.first }

    func encoded() throws -> Data {
        try Self.encoder.encode(self)
    }

    static func decoded(from data: Data) throws -> VaneWidgetSnapshot {
        try decoder.decode(VaneWidgetSnapshot.self, from: data)
    }

    func temperatureText(_ fahrenheit: Int) -> String {
        let value = temperatureUnit == "celsius"
            ? Int(((Double(fahrenheit) - 32) * 5 / 9).rounded())
            : fahrenheit
        return "\(value)°"
    }

    func windText(_ milesPerHour: Int) -> String {
        if windUnit == "kilometersPerHour" {
            return "\(Int((Double(milesPerHour) * 1.60934).rounded())) km/h"
        }
        return "\(milesPerHour) mph"
    }

    func pressureText(_ hectopascals: Int) -> String {
        if pressureUnit == "inchesOfMercury" {
            return String(format: "%.2f inHg", Double(hectopascals) * 0.02953)
        }
        return "\(hectopascals) hPa"
    }

    func percentText(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    func shortTime(_ date: Date) -> String {
        formatted(date, template: "jm")
    }

    func hourText(_ date: Date) -> String {
        formatted(date, template: "j")
    }

    func dayText(_ date: Date) -> String {
        formatted(date, template: "EEE")
    }

    func hours(after date: Date, limit: Int) -> [Hour] {
        Array(hourly.filter { $0.date >= date.addingTimeInterval(-5 * 60) }.prefix(limit))
    }

    private func formatted(_ date: Date, template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    private static var encoder: JSONEncoder {
        let value = JSONEncoder()
        value.dateEncodingStrategy = .millisecondsSince1970
        return value
    }

    private static var decoder: JSONDecoder {
        let value = JSONDecoder()
        value.dateDecodingStrategy = .millisecondsSince1970
        return value
    }

    static let sample: VaneWidgetSnapshot = {
        let calendar = Calendar(identifier: .gregorian)
        let start = Date.now
        return VaneWidgetSnapshot(
            locationName: "New York",
            sourceID: "sample",
            updatedAt: start,
            latitude: 40.7128,
            longitude: -74.006,
            timeZoneIdentifier: "America/New_York",
            temperature: 72,
            apparentTemperature: 73,
            condition: "Partly Cloudy",
            symbolName: "cloud.sun.fill",
            precipitationChance: 0.18,
            humidity: 0.54,
            windSpeed: 7,
            windGust: 12,
            windDirection: "SW",
            uvIndex: 5,
            visibility: 10,
            pressure: 1017,
            dewPoint: 55,
            isDaylight: true,
            hourly: (0..<12).map { offset in
                Hour(
                    date: calendar.date(byAdding: .hour, value: offset, to: start) ?? start,
                    temperature: 72 + min(offset, 5),
                    apparentTemperature: 73 + min(offset, 5),
                    symbolName: offset == 4 ? "cloud.rain.fill" : "cloud.sun.fill",
                    condition: offset == 4 ? "Rain" : "Partly Cloudy",
                    precipitationChance: offset == 4 ? 0.62 : 0.18,
                    humidity: 0.54,
                    windSpeed: 7,
                    isDaylight: offset < 9
                )
            },
            daily: (0..<10).map { offset in
                let date = calendar.date(byAdding: .day, value: offset, to: start) ?? start
                return Day(
                    date: date,
                    low: 64 + offset % 3,
                    high: 76 + offset % 6,
                    symbolName: offset == 1 ? "cloud.rain.fill" : "cloud.sun.fill",
                    condition: offset == 1 ? "Rain" : "Partly Cloudy",
                    precipitationChance: offset == 1 ? 0.62 : 0.18,
                    sunrise: calendar.date(bySettingHour: 6, minute: 12, second: 0, of: date),
                    sunset: calendar.date(bySettingHour: 19, minute: 52, second: 0, of: date),
                    uvIndex: 5,
                    windSpeed: 9
                )
            },
            alertSummary: nil,
            guidanceHeadline: "Comfortable for you",
            guidanceDetail: "This resembles weather you have checked in as comfortable.",
            guidanceSymbol: "sparkles",
            guidanceIsPersonalized: true,
            guidanceIsEstimate: false,
            guidanceCalibrationLabel: "Well calibrated",
            guidanceActionText: nil,
            temperatureUnit: "fahrenheit",
            windUnit: "milesPerHour",
            pressureUnit: "hectopascals",
            precipitationUnit: "inches"
        )
    }()
}

nonisolated enum VaneWidgetDataStore {
    static func load(fileManager: FileManager = .default) -> VaneWidgetSnapshot? {
        guard let url = snapshotURL(fileManager: fileManager),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? VaneWidgetSnapshot.decoded(from: data)
    }

    static func save(_ snapshot: VaneWidgetSnapshot, fileManager: FileManager = .default) throws {
        guard let url = snapshotURL(fileManager: fileManager) else { throw StorageError.appGroupUnavailable }
        let data = try snapshot.encoded()
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    static func snapshotURL(fileManager: FileManager = .default) -> URL? {
        fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: VaneWidgetConstants.appGroup)?
            .appendingPathComponent(VaneWidgetConstants.snapshotFilename, isDirectory: false)
    }

    enum StorageError: Error { case appGroupUnavailable }
}
