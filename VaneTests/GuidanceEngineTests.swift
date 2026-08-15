import XCTest
@testable import Vane

final class GuidanceEngineTests: XCTestCase {
    func testZeroEvidenceSuppressesPersonalCertainty() {
        let guidance = GuidanceEngine.make(snapshot: forecast(apparent: 72), temperaturePreference: 0, windSensitivity: 0.5, samples: [])
        XCTAssertFalse(guidance.isPersonalized)
        XCTAssertEqual(guidance.headline, "Sense is still learning your range")
        XCTAssertEqual(guidance.calibrationLabel, "Needs experience")
    }

    func testVariedComfortableCheckInsEarnPersonalGuidance() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let guidance = GuidanceEngine.make(snapshot: forecast(apparent: 73, now: now), temperaturePreference: 0, windSensitivity: 0.5, samples: variedComfortSamples(now: now), now: now)
        XCTAssertTrue(guidance.isPersonalized)
        XCTAssertTrue(guidance.headline.contains("Comfortable"))
    }

    func testOneColdAnswerRefinesRatherThanReplacesStartingPoint() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sample = GuidanceSample(date: now, apparentTemperature: 55, humidity: 0.45, windSpeed: 5, response: .cold)
        let summary = GuidanceEngine.profileSummary(temperaturePreference: 0, windSensitivity: 0.5, humiditySensitivity: 0.5, samples: [sample], now: now)
        XCTAssertGreaterThan(summary.comfortCenter, 66)
        XCTAssertLessThan(summary.comfortCenter, 71)
        XCTAssertEqual(summary.status, .learning)
    }

    func testAllSevenResponsesHaveIndependentStableCodes() {
        XCTAssertEqual(Set(FeelResponse.allCases.map(\.rawValue)).count, 7)
        XCTAssertEqual(FeelResponse(storedValue: "Too cold"), .cold)
        XCTAssertEqual(FeelResponse(storedValue: "Too warm"), .warm)
        XCTAssertNil(FeelResponse(storedValue: "corrupted-value"))
    }

    func testContradictoryCheckInsDoNotCreateBroadCalibration() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = [FeelResponse.freezing, .veryHot, .freezing, .veryHot].map { GuidanceSample(date: now, apparentTemperature: 70, humidity: 0.5, windSpeed: 5, response: $0) }
        let summary = GuidanceEngine.profileSummary(temperaturePreference: 0, windSensitivity: 0.5, humiditySensitivity: 0.5, samples: samples, now: now)
        XCTAssertFalse(summary.canPersonalize)
        XCTAssertLessThan(summary.evidence, 0.3)
    }

    func testRepeatedIdenticalConditionsDoNotCreateBroadCalibration() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = (0..<10).map { _ in GuidanceSample(date: now, apparentTemperature: 70, humidity: 0.5, windSpeed: 5, response: .comfortable) }
        let summary = GuidanceEngine.profileSummary(temperaturePreference: 0, windSensitivity: 0.5, humiditySensitivity: 0.5, samples: samples, now: now)
        XCTAssertNotEqual(summary.status, .wellCalibrated)
    }

    func testOldCalibrationNeedsRefreshing() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let old = now.addingTimeInterval(-200 * 86_400)
        let samples = variedComfortSamples(now: old)
        let summary = GuidanceEngine.profileSummary(temperaturePreference: 0, windSensitivity: 0.5, humiditySensitivity: 0.5, samples: samples, now: now)
        XCTAssertEqual(summary.status, .needsRefreshing)
        XCTAssertFalse(summary.canPersonalize)
    }

    func testTravelObservationsDoNotOverwhelmHomePattern() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let home = variedComfortSamples(now: now)
        let travel = (0..<8).map { _ in GuidanceSample(date: now, apparentTemperature: 95, humidity: 0.8, windSpeed: 3, response: .comfortable, isTravel: true) }
        let homeCenter = GuidanceEngine.profileSummary(temperaturePreference: 0, windSensitivity: 0.5, humiditySensitivity: 0.5, samples: home, now: now).comfortCenter
        let combined = GuidanceEngine.profileSummary(temperaturePreference: 0, windSensitivity: 0.5, humiditySensitivity: 0.5, samples: home + travel, now: now).comfortCenter
        XCTAssertLessThan(combined - homeCenter, 10)
    }

    func testWarmHumidContextCanBeLearnedOnlyFromExplicitContext() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = [
            GuidanceSample(date: now, apparentTemperature: 82, humidity: 0.8, windSpeed: 3, response: .hot, contexts: [.humidity]),
            GuidanceSample(date: now, apparentTemperature: 85, humidity: 0.76, windSpeed: 4, response: .warm, contexts: [.humidity])
        ]
        let summary = GuidanceEngine.profileSummary(temperaturePreference: 0, windSensitivity: 0.5, humiditySensitivity: 0.5, samples: samples, now: now)
        XCTAssertTrue(summary.humiditySummary.contains("amplifies warmth"))
        XCTAssertEqual(summary.windSummary, "Still learning")
    }

    func testOfficialAlertOverridesPersonalComfort() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let url = URL(string: "https://example.com/alert")!
        let alert = WeatherAlertSnapshot(id: "alert", summary: "Tornado Warning", severity: "Extreme", region: "Test", source: "Official", detailsURL: url)
        let snapshot = forecast(apparent: 72, now: now, alerts: [alert])
        let guidance = GuidanceEngine.make(snapshot: snapshot, temperaturePreference: 0, windSensitivity: 0.5, samples: variedComfortSamples(now: now), now: now)
        XCTAssertEqual(guidance.action?.text, "Review the official alert")
    }

    func testExtremeHeatSafetyDoesNotNeedCalibration() {
        let guidance = GuidanceEngine.make(snapshot: forecast(apparent: 106), temperaturePreference: 0, windSensitivity: 0.5, samples: [])
        XCTAssertEqual(guidance.action?.text, "Limit heat exposure")
    }

    func testSmartPromptSkipsNearlyIdenticalRecentWeather() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sample = GuidanceSample(date: now.addingTimeInterval(-24 * 3_600), apparentTemperature: 72, humidity: 0.5, windSpeed: 5, response: .comfortable)
        XCTAssertFalse(GuidanceEngine.shouldPrompt(snapshot: forecast(apparent: 72, now: now), samples: [sample], frequency: .recommended, now: now))
    }

    func testDaytimeHoursUseDaylightAndExcludePastHours() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 15, hour: 8))!
        let hours = [(7, true), (9, true), (14, true), (20, false)].map { hour, daylight in HourlyConditions(date: calendar.date(from: DateComponents(year: 2026, month: 8, day: 15, hour: hour))!, temperature: 70, symbolName: daylight ? "sun.max.fill" : "moon.fill", precipitationChance: 0, isDaylight: daylight) }
        XCTAssertEqual(GuidanceEngine.daytimeHours(in: hours, now: now, calendar: calendar).map { calendar.component(.hour, from: $0.date) }, [9, 14])
    }

    func testBestFitIsHiddenBeforeCalibration() {
        XCTAssertNil(GuidanceEngine.bestFitHour(in: forecast(apparent: 72).hourly, temperaturePreference: 0, windSensitivity: 0.5, humiditySensitivity: 0.5, samples: []))
    }

    func testNotificationsNeverUseSampleForecast() {
        XCTAssertTrue(NotificationPlanner.plan(snapshot: .sample, rainEnabled: true, preparationEnabled: true).isEmpty)
    }

    func testSnowIsDistinctFromRainAndNotificationsAreLimited() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var snapshot = forecast(apparent: 30, rain: 0.8, now: now)
        snapshot = ForecastSnapshot(locationName: snapshot.locationName, isSample: false, updatedAt: now, current: snapshot.current, hourly: snapshot.hourly.map { HourlyConditions(date: $0.date, temperature: $0.temperature, symbolName: "cloud.snow.fill", condition: "Snow", precipitationChance: 0.8) }, daily: snapshot.daily)
        let events = NotificationPlanner.plan(snapshot: snapshot, now: now, rainEnabled: true, preparationEnabled: true, snowEnabled: true, morningEnabled: true, tomorrowEnabled: true)
        XCTAssertTrue(events.contains { $0.title.contains("Snow") })
        XCTAssertFalse(events.contains { $0.title.contains("Rain") })
        XCTAssertLessThanOrEqual(events.count, 5)
        XCTAssertTrue(events.allSatisfy { $0.date > now })
    }

    func testSevereNotificationHasPriority() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let alert = WeatherAlertSnapshot(id: "alert", summary: "Warning", severity: "Severe", region: nil, source: "Official", detailsURL: URL(string: "https://example.com")!)
        let events = NotificationPlanner.plan(snapshot: forecast(apparent: 72, rain: 0.8, now: now, alerts: [alert]), now: now, rainEnabled: true, preparationEnabled: true)
        XCTAssertTrue(events.first?.id.contains("severe") == true)
    }

    private func variedComfortSamples(now: Date) -> [GuidanceSample] {
        [
            GuidanceSample(date: now, apparentTemperature: 63, humidity: 0.35, windSpeed: 2, response: .chilly),
            GuidanceSample(date: now, apparentTemperature: 68, humidity: 0.48, windSpeed: 7, response: .comfortable),
            GuidanceSample(date: now, apparentTemperature: 73, humidity: 0.58, windSpeed: 12, response: .comfortable),
            GuidanceSample(date: now, apparentTemperature: 79, humidity: 0.7, windSpeed: 18, response: .warm),
            GuidanceSample(date: now, apparentTemperature: 84, humidity: 0.76, windSpeed: 4, response: .hot)
        ]
    }

    private func forecast(apparent: Int, actual: Int? = nil, wind: Int = 5, rain: Double = 0.1, now: Date = .now, alerts: [WeatherAlertSnapshot] = []) -> ForecastSnapshot {
        let actualTemperature = actual ?? apparent
        let hourly = (0..<24).map { offset in HourlyConditions(date: now.addingTimeInterval(Double(offset + 1) * 3_600), temperature: actualTemperature, apparentTemperature: apparent, symbolName: rain >= 0.5 ? "cloud.rain.fill" : "cloud.sun.fill", condition: rain >= 0.5 ? "Rain" : "Partly Cloudy", precipitationChance: rain, humidity: 0.5, windSpeed: wind, isDaylight: offset < 10) }
        return ForecastSnapshot(locationName: "Test City", isSample: false, updatedAt: now, current: CurrentConditions(temperature: actualTemperature, apparentTemperature: apparent, condition: "Test", symbolName: "cloud.sun.fill", precipitationChance: rain, humidity: 0.5, windSpeed: wind, windDirection: "N", uvIndex: 3, visibility: 10, pressure: 1015), hourly: hourly, daily: [DailyConditions(date: now, low: apparent - 5, high: apparent + 5, symbolName: "cloud.sun.fill", condition: "Partly Cloudy", precipitationChance: rain), DailyConditions(date: now.addingTimeInterval(86_400), low: apparent - 4, high: apparent + 6, symbolName: "cloud.sun.fill", condition: "Partly Cloudy", precipitationChance: rain)], alerts: alerts)
    }
}
