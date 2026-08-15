import XCTest
@testable import Vane

final class GuidanceEngineTests: XCTestCase {
    func testComfortableCheckInProducesComfortableGuidance() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sample = GuidanceSample(date: now, apparentTemperature: 72, humidity: 0.5, windSpeed: 4, response: .comfortable)

        let guidance = GuidanceEngine.make(snapshot: forecast(apparent: 73), temperaturePreference: 0, windSensitivity: 0.5, samples: [sample], now: now)

        XCTAssertEqual(guidance.headline, "This should feel comfortable.")
        XCTAssertEqual(guidance.confidenceLabel, "Early read")
    }

    func testColdWindProducesLayerGuidance() {
        let guidance = GuidanceEngine.make(snapshot: forecast(apparent: 55, wind: 18), temperaturePreference: 0, windSensitivity: 1, samples: [])

        XCTAssertEqual(guidance.headline, "This may feel cold to you.")
        XCTAssertTrue(guidance.detail.contains("Wind"))
        XCTAssertEqual(guidance.action?.text, "Wear a warm layer")
    }

    func testRainTakesPriorityOverClothingAction() {
        let guidance = GuidanceEngine.make(snapshot: forecast(apparent: 58, rain: 0.8), temperaturePreference: 0, windSensitivity: 0.5, samples: [])

        XCTAssertEqual(guidance.action?.text, "Bring a rain layer")
    }

    func testSeasonalSamplesPreferNearbyMonths() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 14))!
        let summer = GuidanceSample(date: calendar.date(from: DateComponents(year: 2025, month: 7, day: 2))!, apparentTemperature: 78, humidity: 0.7, windSpeed: 3, response: .comfortable)
        let winter = GuidanceSample(date: calendar.date(from: DateComponents(year: 2026, month: 1, day: 2))!, apparentTemperature: 62, humidity: 0.4, windSpeed: 3, response: .comfortable)

        XCTAssertEqual(GuidanceEngine.seasonallyRelevant(samples: [summer, winter], now: now).map(\.apparentTemperature), [78])
    }

    func testOneColdAnswerRefinesRatherThanReplacesStartingPoint() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let coldMoment = GuidanceSample(date: now, apparentTemperature: 55, humidity: 0.45, windSpeed: 5, response: .tooCold)

        let summary = GuidanceEngine.profileSummary(
            temperaturePreference: 0,
            windSensitivity: 0.5,
            humiditySensitivity: 0.5,
            samples: [coldMoment],
            now: now
        )

        XCTAssertGreaterThan(summary.comfortCenter, 68)
        XCTAssertLessThan(summary.comfortCenter, 71)
        XCTAssertEqual(summary.confidenceLabel, "Early read")
    }

    func testDaytimeHoursExcludeOvernightCandidates() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 15, hour: 1))!
        let hours = [2, 8, 14, 22].map { hour in
            HourlyConditions(
                date: calendar.date(from: DateComponents(year: 2026, month: 8, day: 15, hour: hour))!,
                temperature: 70,
                symbolName: "sun.max.fill",
                precipitationChance: 0
            )
        }

        XCTAssertEqual(
            GuidanceEngine.daytimeHours(in: hours, now: now, calendar: calendar).map { calendar.component(.hour, from: $0.date) },
            [8, 14]
        )
    }

    func testBestFitNeverChoosesMoreComfortableOvernightHour() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 15, hour: 1))!
        let overnight = HourlyConditions(date: calendar.date(from: DateComponents(year: 2026, month: 8, day: 15, hour: 2))!, temperature: 71, symbolName: "moon.fill", precipitationChance: 0)
        let daytime = HourlyConditions(date: calendar.date(from: DateComponents(year: 2026, month: 8, day: 15, hour: 10))!, temperature: 76, symbolName: "sun.max.fill", precipitationChance: 0)

        let best = GuidanceEngine.bestFitHour(
            in: [overnight, daytime],
            temperaturePreference: 0,
            windSensitivity: 0.5,
            humiditySensitivity: 0.5,
            samples: [],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(best?.date, daytime.date)
    }

    func testTemperatureBasisChangesPersonalGuidance() {
        let snapshot = forecast(apparent: 85, actual: 71)

        let feelsLikeGuidance = GuidanceEngine.make(
            snapshot: snapshot,
            temperaturePreference: 0,
            windSensitivity: 0.5,
            usesFeelsLikeTemperature: true,
            samples: []
        )
        let actualGuidance = GuidanceEngine.make(
            snapshot: snapshot,
            temperaturePreference: 0,
            windSensitivity: 0.5,
            usesFeelsLikeTemperature: false,
            samples: []
        )

        XCTAssertEqual(feelsLikeGuidance.headline, "This may feel hot to you.")
        XCTAssertEqual(actualGuidance.headline, "This should feel comfortable.")
    }

    func testNotificationsNeverUseSampleForecast() {
        XCTAssertTrue(NotificationPlanner.plan(snapshot: .sample, rainEnabled: true, preparationEnabled: true).isEmpty)
    }

    func testLikelyRainCreatesOneReminder() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let events = NotificationPlanner.plan(snapshot: forecast(apparent: 72, rain: 0.8, now: now), now: now, rainEnabled: true, preparationEnabled: false)

        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(events[0].title.contains("Rain"))
    }

    private func forecast(apparent: Int, actual: Int? = nil, wind: Int = 5, rain: Double = 0.1, now: Date = .now) -> ForecastSnapshot {
        let actualTemperature = actual ?? apparent
        let hourly = (0..<8).map { offset in
            HourlyConditions(date: now.addingTimeInterval(Double(offset + 1) * 3_600), temperature: actualTemperature, apparentTemperature: apparent, symbolName: rain >= 0.5 ? "cloud.rain.fill" : "cloud.sun.fill", precipitationChance: rain)
        }
        return ForecastSnapshot(
            locationName: "Test City",
            isSample: false,
            updatedAt: now,
            current: CurrentConditions(temperature: actualTemperature, apparentTemperature: apparent, condition: "Test", symbolName: "cloud.sun.fill", precipitationChance: rain, humidity: 0.5, windSpeed: wind, windDirection: "N", uvIndex: 3, visibility: 10, pressure: 1015),
            hourly: hourly,
            daily: [DailyConditions(date: now, low: apparent - 5, high: apparent + 5, symbolName: "cloud.sun.fill", precipitationChance: rain)]
        )
    }
}
