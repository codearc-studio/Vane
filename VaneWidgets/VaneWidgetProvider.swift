import CoreLocation
import Foundation
import WeatherKit
import WidgetKit

struct VaneWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: VaneWidgetSnapshot?
    let configuration: VaneWidgetConfiguration
}

nonisolated struct VaneSenseWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: VaneWidgetSnapshot?
}

nonisolated struct VaneSenseWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> VaneSenseWidgetEntry {
        VaneSenseWidgetEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (VaneSenseWidgetEntry) -> Void) {
        completion(VaneSenseWidgetEntry(date: .now, snapshot: context.isPreview ? .sample : VaneWidgetDataStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<VaneSenseWidgetEntry>) -> Void) {
        let now = Date.now
        let snapshot = VaneWidgetDataStore.load()
        let entries = (0..<6).compactMap { offset -> VaneSenseWidgetEntry? in
            guard let date = Calendar.current.date(byAdding: .hour, value: offset, to: now) else { return nil }
            return VaneSenseWidgetEntry(date: date, snapshot: snapshot)
        }
        completion(Timeline(entries: entries.isEmpty ? [VaneSenseWidgetEntry(date: now, snapshot: snapshot)] : entries,
                            policy: .after(now.addingTimeInterval(30 * 60))))
    }
}

struct VaneWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> VaneWidgetEntry {
        VaneWidgetEntry(date: .now, snapshot: .sample, configuration: .automatic)
    }

    func snapshot(for configuration: VaneWidgetConfiguration, in context: Context) async -> VaneWidgetEntry {
        VaneWidgetEntry(
            date: .now,
            snapshot: context.isPreview ? .sample : VaneWidgetDataStore.load(),
            configuration: configuration
        )
    }

    func timeline(for configuration: VaneWidgetConfiguration, in context: Context) async -> Timeline<VaneWidgetEntry> {
        let now = Date.now
        let cached = VaneWidgetDataStore.load()
        let snapshot: VaneWidgetSnapshot?

        if let cached, now.timeIntervalSince(cached.updatedAt) >= 12 * 60,
           let refreshed = try? await WidgetWeatherRefresher.refresh(cached) {
            snapshot = refreshed
            try? VaneWidgetDataStore.save(refreshed)
        } else {
            snapshot = cached
        }

        let entries = (0..<6).compactMap { offset -> VaneWidgetEntry? in
            guard let date = Calendar.current.date(byAdding: .hour, value: offset, to: now) else { return nil }
            return VaneWidgetEntry(date: date, snapshot: snapshot, configuration: configuration)
        }
        return Timeline(entries: entries.isEmpty ? [VaneWidgetEntry(date: now, snapshot: snapshot, configuration: configuration)] : entries,
                        policy: .after(now.addingTimeInterval(30 * 60)))
    }
}

private enum WidgetWeatherRefresher {
    static func refresh(_ cached: VaneWidgetSnapshot) async throws -> VaneWidgetSnapshot {
        let location = CLLocation(latitude: cached.latitude, longitude: cached.longitude)
        let weather = try await WeatherService.shared.weather(for: location)
        let current = weather.currentWeather
        let hourly = Array(weather.hourlyForecast.forecast.prefix(48)).map {
            VaneWidgetSnapshot.Hour(
                date: $0.date,
                temperature: fahrenheit($0.temperature),
                apparentTemperature: fahrenheit($0.apparentTemperature),
                symbolName: $0.symbolName,
                condition: $0.condition.description,
                precipitationChance: $0.precipitationChance,
                humidity: $0.humidity,
                windSpeed: mph($0.wind.speed),
                isDaylight: $0.isDaylight
            )
        }
        let daily = Array(weather.dailyForecast.forecast.prefix(10)).map {
            VaneWidgetSnapshot.Day(
                date: $0.date,
                low: fahrenheit($0.lowTemperature),
                high: fahrenheit($0.highTemperature),
                symbolName: $0.symbolName,
                condition: $0.condition.description,
                precipitationChance: $0.precipitationChance,
                sunrise: $0.sun.sunrise,
                sunset: $0.sun.sunset,
                uvIndex: $0.uvIndex.value,
                windSpeed: mph($0.wind.speed)
            )
        }

        return VaneWidgetSnapshot(
            locationName: cached.locationName,
            sourceID: cached.sourceID,
            updatedAt: current.date,
            latitude: cached.latitude,
            longitude: cached.longitude,
            timeZoneIdentifier: cached.timeZoneIdentifier,
            temperature: fahrenheit(current.temperature),
            apparentTemperature: fahrenheit(current.apparentTemperature),
            condition: current.condition.description,
            symbolName: current.symbolName,
            precipitationChance: hourly.first?.precipitationChance ?? cached.precipitationChance,
            humidity: current.humidity,
            windSpeed: mph(current.wind.speed),
            windGust: current.wind.gust.map(mph) ?? mph(current.wind.speed),
            windDirection: cardinalDirection(current.wind.direction.converted(to: .degrees).value),
            uvIndex: current.uvIndex.value,
            visibility: Int(current.visibility.converted(to: .miles).value.rounded()),
            pressure: Int(current.pressure.converted(to: .hectopascals).value.rounded()),
            dewPoint: fahrenheit(current.dewPoint),
            isDaylight: current.isDaylight,
            hourly: hourly,
            daily: daily,
            alertSummary: weather.weatherAlerts?.max { severityPriority($0.severity) < severityPriority($1.severity) }?.summary,
            guidanceHeadline: cached.guidanceHeadline,
            guidanceDetail: cached.guidanceDetail,
            guidanceSymbol: cached.guidanceSymbol,
            guidanceIsPersonalized: cached.guidanceIsPersonalized,
            guidanceIsEstimate: cached.guidanceIsEstimate,
            guidanceCalibrationLabel: cached.guidanceCalibrationLabel,
            guidanceActionText: cached.guidanceActionText,
            temperatureUnit: cached.temperatureUnit,
            windUnit: cached.windUnit,
            pressureUnit: cached.pressureUnit,
            precipitationUnit: cached.precipitationUnit
        )
    }

    private static func fahrenheit(_ measurement: Measurement<UnitTemperature>) -> Int {
        Int(measurement.converted(to: .fahrenheit).value.rounded())
    }

    private static func severityPriority(_ severity: WeatherSeverity) -> Int {
        switch severity {
        case .extreme: 4
        case .severe: 3
        case .moderate: 2
        case .minor: 1
        case .unknown: 0
        @unknown default: 0
        }
    }

    private static func mph(_ measurement: Measurement<UnitSpeed>) -> Int {
        Int(measurement.converted(to: .milesPerHour).value.rounded())
    }

    private static func cardinalDirection(_ degrees: Double) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let normalized = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return directions[Int((normalized + 22.5) / 45) % 8]
    }
}
