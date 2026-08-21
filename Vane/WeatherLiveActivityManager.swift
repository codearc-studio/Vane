import ActivityKit
import Foundation
import OSLog

struct PlannedWeatherLiveActivity: Equatable, Sendable {
    let locationName: String
    let sourceID: String
    let isTravelLocation: Bool
    let state: VaneWeatherActivityAttributes.ContentState
    let staleDate: Date
    let relevanceScore: Double

    nonisolated var attributes: VaneWeatherActivityAttributes {
        VaneWeatherActivityAttributes(
            locationName: locationName,
            sourceID: sourceID,
            isTravelLocation: isTravelLocation
        )
    }

    nonisolated var content: ActivityContent<VaneWeatherActivityAttributes.ContentState> {
        ActivityContent(state: state, staleDate: staleDate, relevanceScore: relevanceScore)
    }
}

enum WeatherLiveActivityPlanner {
    static func plan(
        snapshot: ForecastSnapshot,
        now: Date = .now,
        formatting: WeatherFormatting? = nil
    ) -> PlannedWeatherLiveActivity? {
        guard !snapshot.isSample,
              !snapshot.isPlaceholder,
              now.timeIntervalSince(snapshot.updatedAt) < 2 * 60 * 60 else { return nil }

        let formatting = formatting ?? WeatherFormatting(timeZone: snapshot.timeZone)

        if let alert = snapshot.alerts
            .filter({ ($0.expiresAt ?? .distantFuture) > now && $0.severityLevel.priority >= WeatherAlertSeverity.severe.priority })
            .sorted(by: WeatherAlertSnapshot.priorityOrder)
            .first {
            let expiration = max(alert.expiresAt ?? now.addingTimeInterval(2 * 60 * 60), now.addingTimeInterval(15 * 60))
            return makePlan(
                snapshot: snapshot,
                kind: .severeAlert,
                title: "Official weather alert",
                detail: "\(alert.severityLevel.title): \(alert.summary)",
                symbolName: alert.severityLevel.symbolName,
                eventDate: alert.expiresAt,
                showsCountdown: false,
                staleDate: expiration,
                relevanceScore: 100,
                destination: "vane://weather/alerts",
                formatting: formatting,
                now: now
            )
        }

        if isStorm(snapshot.current.symbolName, condition: snapshot.current.condition) {
            return makePlan(
                snapshot: snapshot,
                kind: .storm,
                title: "Storm nearby",
                detail: "Storm conditions are affecting the current forecast.",
                symbolName: "cloud.bolt.rain.fill",
                eventDate: nil,
                showsCountdown: false,
                staleDate: now.addingTimeInterval(60 * 60),
                relevanceScore: 90,
                destination: "vane://weather",
                formatting: formatting,
                now: now
            )
        }

        if let storm = stormOnset(snapshot: snapshot, now: now) {
            let chance = storm.precipitationChance.formatted(.percent.precision(.fractionLength(0)))
            return makePlan(
                snapshot: snapshot,
                kind: .storm,
                title: "Storm approaching",
                detail: "Forecast around \(formatting.hour(storm.date)) · \(chance) chance",
                symbolName: "cloud.bolt.rain.fill",
                eventDate: storm.date,
                showsCountdown: true,
                staleDate: storm.date.addingTimeInterval(60 * 60),
                relevanceScore: 90,
                destination: "vane://weather",
                formatting: formatting,
                now: now
            )
        }

        if let onset = precipitationOnset(snapshot: snapshot, now: now) {
            let title = switch onset.kind {
            case .snow: "Snow arriving"
            case .mixed: "Wintry mix arriving"
            default: "Rain arriving"
            }
            let symbolName = switch onset.kind {
            case .snow: "cloud.snow.fill"
            case .mixed: "cloud.sleet.fill"
            default: "cloud.rain.fill"
            }
            let chance = onset.hour.precipitationChance.formatted(.percent.precision(.fractionLength(0)))
            return makePlan(
                snapshot: snapshot,
                kind: .precipitation,
                title: title,
                detail: "Forecast around \(formatting.hour(onset.hour.date)) · \(chance) chance",
                symbolName: symbolName,
                eventDate: onset.hour.date,
                showsCountdown: true,
                staleDate: onset.hour.date.addingTimeInterval(60 * 60),
                relevanceScore: 80,
                destination: "vane://weather",
                formatting: formatting,
                now: now
            )
        }

        if let window = bestOutdoorWindow(snapshot: snapshot, now: now) {
            let startsSoon = window.hour.date <= now.addingTimeInterval(10 * 60)
            let chance = window.hour.precipitationChance.formatted(.percent.precision(.fractionLength(0)))
            return makePlan(
                snapshot: snapshot,
                kind: .outdoorWindow,
                title: startsSoon ? "Great outdoor weather" : "Best outdoor window",
                detail: "\(window.hour.condition) · \(formatting.degrees(window.hour.apparentTemperature)) · \(chance) rain",
                symbolName: window.hour.symbolName,
                eventDate: startsSoon ? nil : window.hour.date,
                showsCountdown: !startsSoon,
                staleDate: window.hour.date.addingTimeInterval(2 * 60 * 60),
                relevanceScore: 60,
                destination: "vane://weather",
                formatting: formatting,
                now: now
            )
        }

        return nil
    }

    private static func makePlan(
        snapshot: ForecastSnapshot,
        kind: VaneWeatherActivityKind,
        title: String,
        detail: String,
        symbolName: String,
        eventDate: Date?,
        showsCountdown: Bool,
        staleDate: Date,
        relevanceScore: Double,
        destination: String,
        formatting: WeatherFormatting,
        now: Date
    ) -> PlannedWeatherLiveActivity {
        PlannedWeatherLiveActivity(
            locationName: snapshot.locationName,
            sourceID: snapshot.sourceID,
            isTravelLocation: snapshot.isTravelLocation,
            state: VaneWeatherActivityAttributes.ContentState(
                kind: kind,
                title: title,
                detail: detail,
                symbolName: symbolName,
                temperatureText: formatting.degrees(snapshot.current.temperature),
                eventDate: eventDate,
                showsCountdown: showsCountdown,
                updatedAt: now,
                destinationURLString: destination
            ),
            staleDate: staleDate,
            relevanceScore: relevanceScore
        )
    }

    private static func stormOnset(snapshot: ForecastSnapshot, now: Date) -> HourlyConditions? {
        let latestStart = now.addingTimeInterval(6 * 60 * 60)
        return snapshot.hourly
            .sorted(by: { $0.date < $1.date })
            .first {
                $0.date > now.addingTimeInterval(10 * 60)
                    && $0.date <= latestStart
                    && $0.precipitationChance >= 0.4
                    && isStorm($0.symbolName, condition: $0.condition)
            }
    }

    private static func isStorm(_ symbolName: String, condition: String) -> Bool {
        symbolName.localizedCaseInsensitiveContains("thunder")
            || condition.localizedCaseInsensitiveContains("thunder")
            || condition.localizedCaseInsensitiveContains("storm")
    }

    private static func precipitationOnset(
        snapshot: ForecastSnapshot,
        now: Date
    ) -> (hour: HourlyConditions, kind: PrecipitationKind)? {
        var previousKind = snapshot.current.precipitationChance >= 0.55
            ? snapshot.current.precipitationKind
            : .none
        let latestStart = now.addingTimeInterval(6 * 60 * 60)

        for hour in snapshot.hourly.sorted(by: { $0.date < $1.date })
        where hour.date > now.addingTimeInterval(10 * 60) && hour.date <= latestStart {
            let kind: PrecipitationKind = hour.precipitationChance >= 0.55
                ? hour.precipitationKind
                : .none
            defer { previousKind = kind }
            guard previousKind == .none, kind != .none else { continue }
            return (hour, kind)
        }
        return nil
    }

    private static func bestOutdoorWindow(
        snapshot: ForecastSnapshot,
        now: Date
    ) -> (hour: HourlyConditions, score: Int)? {
        let latestStart = now.addingTimeInterval(4 * 60 * 60)
        return snapshot.hourly
            .filter { $0.date >= now.addingTimeInterval(-5 * 60) && $0.date <= latestStart && $0.isDaylight }
            .map { hour in (hour, outdoorScore(hour)) }
            .filter { $0.1 >= 80 }
            .sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                return $0.0.date < $1.0.date
            }
            .first
    }

    private static func outdoorScore(_ hour: HourlyConditions) -> Int {
        var score = 100.0
        score -= hour.precipitationChance * 92
        score -= max(0, Double(hour.windSpeed - 11)) * 2.2
        score -= max(0, Double(hour.apparentTemperature - 82)) * 3.0
        score -= max(0, Double(50 - hour.apparentTemperature)) * 2.6
        score -= max(0, hour.humidity - 0.75) * 40
        return Int(max(0, min(100, score)).rounded())
    }
}

@MainActor
final class WeatherLiveActivityManager {
    static let shared = WeatherLiveActivityManager()
    nonisolated static let enabledKey = "weather.liveActivitiesEnabled"
    nonisolated private static let logger = Logger(subsystem: "studio.codearc.Vane", category: "LiveActivity")

    var systemActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func synchronize(snapshot: ForecastSnapshot, now: Date = .now) async {
        guard UserDefaults.standard.bool(forKey: Self.enabledKey), systemActivitiesEnabled else {
            await endAll()
            return
        }
        guard let plan = WeatherLiveActivityPlanner.plan(snapshot: snapshot, now: now) else {
            await endAll()
            return
        }

        await Self.apply(plan)
    }

    func endAll() async {
        await Self.endAllActivities()
    }

    nonisolated private static func apply(_ plan: PlannedWeatherLiveActivity) async {
        let activities = Activity<VaneWeatherActivityAttributes>.activities
        let matching = activities.first {
            $0.attributes.sourceID == plan.sourceID
                && $0.attributes.locationName == plan.locationName
                && $0.attributes.isTravelLocation == plan.isTravelLocation
        }
        for activity in activities where activity.id != matching?.id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        if let matching {
            await matching.update(plan.content)
        } else {
            do {
                _ = try Activity.request(attributes: plan.attributes, content: plan.content, pushType: nil)
            } catch {
                logger.error("Could not start weather Live Activity: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    nonisolated private static func endAllActivities() async {
        for activity in Activity<VaneWeatherActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
