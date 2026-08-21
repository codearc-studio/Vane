import XCTest
@testable import Vane

@MainActor
final class WeatherLiveActivityPlannerTests: XCTestCase {
    func testSevereAlertTakesPriorityOverRainCountdown() {
        let now = fixedDate(hour: 12)
        let alert = WeatherAlertSnapshot(
            id: "severe",
            summary: "Severe Thunderstorm Warning",
            severity: "Severe",
            region: "Test County",
            source: "Official",
            detailsURL: URL(string: "https://example.com/alert")!,
            issuedAt: now.addingTimeInterval(-600),
            expiresAt: now.addingTimeInterval(3_600)
        )
        let snapshot = forecast(
            now: now,
            hours: [dryHour(now, offset: 0), rainHour(now, offset: 1)],
            alerts: [alert]
        )

        let plan = WeatherLiveActivityPlanner.plan(snapshot: snapshot, now: now)

        XCTAssertEqual(plan?.state.kind, .severeAlert)
        XCTAssertEqual(plan?.state.title, "Official weather alert")
        XCTAssertEqual(plan?.state.destinationURLString, "vane://weather/alerts")
        XCTAssertFalse(plan?.state.showsCountdown ?? true)
    }

    func testFutureRainOnsetCreatesCountdown() {
        let now = fixedDate(hour: 12)
        let rain = rainHour(now, offset: 1)
        let snapshot = forecast(now: now, hours: [dryHour(now, offset: 0), rain])

        let plan = WeatherLiveActivityPlanner.plan(snapshot: snapshot, now: now)

        XCTAssertEqual(plan?.state.kind, .precipitation)
        XCTAssertEqual(plan?.state.title, "Rain arriving")
        XCTAssertEqual(plan?.state.eventDate, rain.date)
        XCTAssertTrue(plan?.state.showsCountdown ?? false)
    }

    func testThunderForecastUsesStormLanguage() {
        let now = fixedDate(hour: 12)
        let storm = HourlyConditions(
            date: now.addingTimeInterval(90 * 60),
            temperature: 70,
            symbolName: "cloud.bolt.rain.fill",
            condition: "Thunderstorms",
            precipitationChance: 0.5,
            humidity: 0.76,
            windSpeed: 14,
            precipitationKind: .rain
        )
        let snapshot = forecast(now: now, hours: [dryHour(now, offset: 0), storm])

        let plan = WeatherLiveActivityPlanner.plan(snapshot: snapshot, now: now)

        XCTAssertEqual(plan?.state.kind, .storm)
        XCTAssertEqual(plan?.state.title, "Storm approaching")
    }

    func testStormCanSupersedeOngoingRain() {
        let now = fixedDate(hour: 12)
        let storm = HourlyConditions(
            date: now.addingTimeInterval(90 * 60),
            temperature: 68,
            symbolName: "cloud.bolt.rain.fill",
            condition: "Thunderstorms",
            precipitationChance: 0.7,
            humidity: 0.82,
            windSpeed: 16,
            precipitationKind: .rain
        )
        let snapshot = forecast(
            now: now,
            currentPrecipitationChance: 0.8,
            currentPrecipitationKind: .rain,
            hours: [rainHour(now, offset: 1), storm]
        )

        let plan = WeatherLiveActivityPlanner.plan(snapshot: snapshot, now: now)

        XCTAssertEqual(plan?.state.kind, .storm)
        XCTAssertEqual(plan?.state.title, "Storm approaching")
    }

    func testOngoingRainDoesNotClaimRainIsArriving() {
        let now = fixedDate(hour: 12)
        let snapshot = forecast(
            now: now,
            currentPrecipitationChance: 0.8,
            currentPrecipitationKind: .rain,
            hours: [rainHour(now, offset: 1), rainHour(now, offset: 2)]
        )

        XCTAssertNil(WeatherLiveActivityPlanner.plan(snapshot: snapshot, now: now))
    }

    func testStrongDryWeatherCreatesOutdoorWindowAndPreservesTravelContext() {
        let now = fixedDate(hour: 12)
        let best = HourlyConditions(
            date: now.addingTimeInterval(60 * 60),
            temperature: 72,
            apparentTemperature: 72,
            symbolName: "sun.max.fill",
            condition: "Sunny",
            precipitationChance: 0.05,
            humidity: 0.45,
            windSpeed: 5,
            isDaylight: true
        )
        let snapshot = forecast(now: now, hours: [best], isTravel: true)

        let plan = WeatherLiveActivityPlanner.plan(snapshot: snapshot, now: now)

        XCTAssertEqual(plan?.state.kind, .outdoorWindow)
        XCTAssertEqual(plan?.state.title, "Best outdoor window")
        XCTAssertEqual(plan?.state.eventDate, best.date)
        XCTAssertEqual(plan?.isTravelLocation, true)
    }

    func testPlaceholderAndStaleForecastsDoNotStartActivities() {
        let now = fixedDate(hour: 12)
        XCTAssertNil(WeatherLiveActivityPlanner.plan(snapshot: .empty, now: now))

        let stale = forecast(now: now.addingTimeInterval(-3 * 60 * 60), hours: [dryHour(now, offset: 1)])
        XCTAssertNil(WeatherLiveActivityPlanner.plan(snapshot: stale, now: now))
    }

    private func forecast(
        now: Date,
        currentPrecipitationChance: Double = 0.05,
        currentPrecipitationKind: PrecipitationKind = .none,
        hours: [HourlyConditions],
        alerts: [WeatherAlertSnapshot] = [],
        isTravel: Bool = false
    ) -> ForecastSnapshot {
        ForecastSnapshot(
            locationName: isTravel ? "Lisbon" : "Test City",
            sourceID: isTravel ? "place:lisbon" : "current",
            isSample: false,
            updatedAt: now,
            current: CurrentConditions(
                temperature: 72,
                apparentTemperature: 72,
                condition: currentPrecipitationKind == .none ? "Clear" : "Rain",
                symbolName: currentPrecipitationKind == .none ? "sun.max.fill" : "cloud.rain.fill",
                precipitationChance: currentPrecipitationChance,
                humidity: 0.5,
                windSpeed: 5,
                windDirection: "W",
                uvIndex: 4,
                visibility: 10,
                pressure: 1015,
                precipitationKind: currentPrecipitationKind,
                cloudCover: currentPrecipitationKind == .none ? 0.1 : 0.9,
                isDaylight: true
            ),
            hourly: hours,
            daily: [],
            alerts: alerts,
            timeZoneIdentifier: "UTC",
            isTravelLocation: isTravel
        )
    }

    private func dryHour(_ now: Date, offset: Int) -> HourlyConditions {
        HourlyConditions(
            date: now.addingTimeInterval(Double(offset) * 3_600),
            temperature: 72,
            symbolName: "sun.max.fill",
            condition: "Sunny",
            precipitationChance: 0.05,
            humidity: 0.5,
            windSpeed: 5,
            isDaylight: true
        )
    }

    private func rainHour(_ now: Date, offset: Int) -> HourlyConditions {
        HourlyConditions(
            date: now.addingTimeInterval(Double(offset) * 3_600),
            temperature: 68,
            symbolName: "cloud.rain.fill",
            condition: "Rain",
            precipitationChance: 0.78,
            humidity: 0.8,
            windSpeed: 9,
            isDaylight: true,
            precipitationKind: .rain
        )
    }

    private func fixedDate(hour: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: hour))!
    }
}
