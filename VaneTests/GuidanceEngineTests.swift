import XCTest
import SwiftData
import CoreLocation
import WeatherKit
@testable import Vane

@MainActor
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

    func testExplicitDampnessContextCanBeLearned() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = [
            GuidanceSample(date: now, apparentTemperature: 58, humidity: 0.82, windSpeed: 8, response: .cold, contexts: [.dampness], precipitationChance: 0.85),
            GuidanceSample(date: now, apparentTemperature: 61, humidity: 0.78, windSpeed: 7, response: .chilly, contexts: [.dampness], precipitationChance: 0.72)
        ]
        let summary = GuidanceEngine.profileSummary(temperaturePreference: 0, windSensitivity: 0.5, humiditySensitivity: 0.5, samples: samples, now: now)
        XCTAssertTrue(summary.dampnessSummary.contains("land cooler"))
    }

    func testSenseFamiliarityUsesSurroundingWeatherSignals() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = (0..<5).map { _ in
            GuidanceSample(
                date: now,
                apparentTemperature: 72,
                humidity: 0.72,
                windSpeed: 12,
                response: .comfortable,
                cloudCover: 0.9,
                dewPoint: 66,
                windGust: 24,
                pressure: 992,
                visibility: 3,
                precipitationChance: 0.82,
                isDaylight: false
            )
        }
        let matching = GuidanceEngine.predictionFamiliarity(temperature: 72, humidity: 0.72, windSpeed: 12, cloudCover: 0.9, dewPoint: 66, windGust: 24, pressure: 992, visibility: 3, precipitationChance: 0.82, isDaylight: false, samples: samples, now: now)
        let differentSystem = GuidanceEngine.predictionFamiliarity(temperature: 72, humidity: 0.72, windSpeed: 12, cloudCover: 0.9, dewPoint: 40, windGust: 4, pressure: 1032, visibility: 12, precipitationChance: 0.02, isDaylight: true, samples: samples, now: now)
        XCTAssertGreaterThan(matching, differentSystem)
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
        let alert = WeatherAlertSnapshot(id: "alert", summary: "Warning", severity: "Severe", region: nil, source: "Official", detailsURL: URL(string: "https://example.com")!, issuedAt: now, expiresAt: now.addingTimeInterval(3_600))
        let events = NotificationPlanner.plan(snapshot: forecast(apparent: 72, rain: 0.8, now: now, alerts: [alert]), now: now, rainEnabled: true, preparationEnabled: true, severeEnabled: true)
        XCTAssertTrue(events.first?.id.contains("severe") == true)
        XCTAssertEqual(events.first?.destinationURL?.absoluteString, "vane://weather/alerts")
        XCTAssertEqual(events.first?.expirationDate, alert.expiresAt)
        XCTAssertTrue(events.first?.isTimeSensitive == true)
    }

    func testOfficialAlertsSortByActiveStateThenSeverity() {
        let now = Date()
        let minor = WeatherAlertSnapshot(id: "minor", summary: "Minor", severity: "Minor", region: nil, source: "Official", detailsURL: URL(string: "https://example.com/minor")!, expiresAt: now.addingTimeInterval(3_600))
        let extreme = WeatherAlertSnapshot(id: "extreme", summary: "Extreme", severity: "Extreme", region: nil, source: "Official", detailsURL: URL(string: "https://example.com/extreme")!, expiresAt: now.addingTimeInterval(7_200))
        let expired = WeatherAlertSnapshot(id: "expired", summary: "Expired", severity: "Extreme", region: nil, source: "Official", detailsURL: URL(string: "https://example.com/expired")!, expiresAt: now.addingTimeInterval(-60))
        XCTAssertEqual([minor, expired, extreme].sorted(by: WeatherAlertSnapshot.priorityOrder).map(\.id), ["extreme", "minor", "expired"])
    }

    func testTemperaturePreferenceDirectionMatchesOnboardingLanguage() {
        let warmer = GuidanceEngine.profileSummary(temperaturePreference: 0.7, windSensitivity: 0.5, humiditySensitivity: 0.5, samples: [])
        let cooler = GuidanceEngine.profileSummary(temperaturePreference: -0.7, windSensitivity: 0.5, humiditySensitivity: 0.5, samples: [])
        XCTAssertGreaterThan(warmer.comfortCenter, cooler.comfortCenter)
    }

    func testMatchingContextRemainsLocallyFamiliar() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = variedComfortSamples(now: now) + [
            GuidanceSample(date: now, apparentTemperature: 76, humidity: 0.78, windSpeed: 17, response: .comfortable, contexts: [.humidity, .wind], cloudCover: 0.2),
            GuidanceSample(date: now, apparentTemperature: 78, humidity: 0.76, windSpeed: 16, response: .comfortable, contexts: [.humidity, .wind], cloudCover: 0.25)
        ]
        let familiarity = GuidanceEngine.predictionFamiliarity(temperature: 76, humidity: 0.78, windSpeed: 17, cloudCover: 0.2, samples: samples, now: now)
        XCTAssertGreaterThan(familiarity, GuidanceEngine.predictionFamiliarityThreshold)
        let guidance = GuidanceEngine.make(snapshot: forecast(apparent: 76, wind: 17, now: now), temperaturePreference: 0, windSensitivity: 0.5, samples: samples, now: now)
        XCTAssertTrue(guidance.isPersonalized)
    }

    func testUnfamiliarExtremeSuppressesPersonalLanguageAfterGlobalCalibration() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let guidance = GuidanceEngine.make(snapshot: forecast(apparent: 105, now: now), temperaturePreference: 0, windSensitivity: 0.5, samples: variedComfortSamples(now: now), now: now)
        XCTAssertFalse(guidance.isPersonalized)
        XCTAssertEqual(guidance.headline, "These conditions are less familiar")
        XCTAssertEqual(guidance.action?.text, "Limit heat exposure")
    }

    func testOppositeSeasonSamplesAreDiscountedAndNeedRefreshing() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 15))!
        let winter = calendar.date(from: DateComponents(year: 2026, month: 2, day: 15))!
        let summary = GuidanceEngine.profileSummary(temperaturePreference: 0, windSensitivity: 0.5, humiditySensitivity: 0.5, samples: variedComfortSamples(now: winter), now: now)
        XCTAssertEqual(summary.status, .needsRefreshing)
        XCTAssertEqual(summary.relevantSampleCount, 0)
        XCTAssertFalse(summary.canPersonalize)
    }

    func testTravelSamplesAreWeightedInCalibrationEvidence() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let home = variedComfortSamples(now: now)
        let travel = home.map { GuidanceSample(date: $0.date, apparentTemperature: $0.apparentTemperature, humidity: $0.humidity, windSpeed: $0.windSpeed, response: $0.response, isTravel: true) }
        let homeSummary = GuidanceEngine.profileSummary(temperaturePreference: 0, windSensitivity: 0.5, humiditySensitivity: 0.5, samples: home, now: now)
        let travelSummary = GuidanceEngine.profileSummary(temperaturePreference: 0, windSensitivity: 0.5, humiditySensitivity: 0.5, samples: travel, now: now)
        XCTAssertLessThan(travelSummary.effectiveSampleCount, homeSummary.effectiveSampleCount)
        XCTAssertLessThan(travelSummary.evidence, homeSummary.evidence)
    }

    func testManualPlaceIsNotAutomaticallyTravel() {
        let manual = ForecastSnapshot(locationName: "Home", sourceID: "coordinate:1,2", isSample: false, updatedAt: .now, current: forecast(apparent: 72).current, hourly: [], daily: [])
        XCTAssertFalse(manual.isTravelLocation)
        let savedHome = SavedPlace(name: "Home", region: "Test", latitude: 1, longitude: 2, isHome: true)
        XCTAssertTrue(savedHome.isHome)
    }

    func testSharedFormattingCoversAllUnitFamilies() {
        let metric = WeatherFormatting(temperature: .celsius, wind: .kilometersPerHour, pressure: .hectopascals, precipitation: .millimeters)
        XCTAssertEqual(metric.degrees(68, includeUnit: true), "20°C")
        XCTAssertEqual(metric.windSpeed(10), "16 km/h")
        XCTAssertEqual(metric.visibility(10), "16 km")
        XCTAssertEqual(metric.pressureValue(1015), "1015 hPa")
        XCTAssertEqual(metric.precipitationAmount(1), "25.4 mm")
        let imperial = WeatherFormatting(temperature: .fahrenheit, wind: .milesPerHour, pressure: .inchesOfMercury, precipitation: .inches)
        XCTAssertEqual(imperial.degrees(68, includeUnit: true), "68°F")
        XCTAssertEqual(imperial.visibility(10), "10 mi")
        XCTAssertTrue(imperial.pressureValue(1015).contains("inHg"))
    }

    func testMorningAndTomorrowUseScheduledCalendarDatesAfterCutoffs() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 15, hour: 20))!
        let days = (0...3).map { offset in
            DailyConditions(date: calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!, low: 60 + offset, high: 70 + offset, symbolName: "sun.max.fill", condition: "Day \(offset)", precipitationChance: 0)
        }
        let base = forecast(apparent: 72, now: now)
        let snapshot = ForecastSnapshot(locationName: "UTC", isSample: false, updatedAt: now, current: base.current, hourly: base.hourly, daily: days, timeZoneIdentifier: "GMT")
        let events = NotificationPlanner.plan(snapshot: snapshot, now: now, rainEnabled: false, preparationEnabled: false, snowEnabled: false, uvEnabled: false, morningEnabled: true, tomorrowEnabled: true, formatting: WeatherFormatting(timeZone: TimeZone(secondsFromGMT: 0)!))
        XCTAssertTrue(events.first(where: { $0.id.contains("morning") })?.body.contains("Day 1") == true)
        XCTAssertTrue(events.first(where: { $0.id.contains("tomorrow") })?.body.contains("Day 2") == true)
    }

    func testMorningAndTomorrowUseScheduledCalendarDatesBeforeCutoffs() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 15, hour: 6))!
        let days = (0...2).map { offset in DailyConditions(date: calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!, low: 60, high: 70, symbolName: "sun.max.fill", condition: "Day \(offset)", precipitationChance: 0) }
        let base = forecast(apparent: 72, now: now)
        let snapshot = ForecastSnapshot(locationName: "UTC", isSample: false, updatedAt: now, current: base.current, hourly: base.hourly, daily: days, timeZoneIdentifier: "GMT")
        let events = NotificationPlanner.plan(snapshot: snapshot, now: now, rainEnabled: false, preparationEnabled: false, snowEnabled: false, uvEnabled: false, morningEnabled: true, tomorrowEnabled: true, formatting: WeatherFormatting(timeZone: TimeZone(secondsFromGMT: 0)!))
        XCTAssertTrue(events.first(where: { $0.id.contains("morning") })?.body.contains("Day 0") == true)
        XCTAssertTrue(events.first(where: { $0.id.contains("tomorrow") })?.body.contains("Day 1") == true)
    }

    func testSmartCheckInNotificationRespectsToggleAndUsefulConditions() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = forecast(apparent: 90, now: now)
        let off = NotificationPlanner.plan(snapshot: snapshot, now: now, rainEnabled: false, preparationEnabled: false, snowEnabled: false, uvEnabled: false, smartCheckInEnabled: false)
        let on = NotificationPlanner.plan(snapshot: snapshot, now: now, rainEnabled: false, preparationEnabled: false, snowEnabled: false, uvEnabled: false, smartCheckInEnabled: true)
        XCTAssertFalse(off.contains { $0.id.contains("smart-check-in") })
        XCTAssertTrue(on.contains { $0.id.contains("smart-check-in") })
        let recent = [GuidanceSample(date: now.addingTimeInterval(-3_600), apparentTemperature: 90, humidity: 0.5, windSpeed: 5, response: .comfortable)]
        let tooSoon = NotificationPlanner.plan(snapshot: snapshot, now: now, rainEnabled: false, preparationEnabled: false, snowEnabled: false, uvEnabled: false, smartCheckInEnabled: true, samples: recent, checkInFrequency: .recommended)
        XCTAssertFalse(tooSoon.contains { $0.id.contains("smart-check-in") })
    }

    func testPrecipitationNotificationRequiresAStartTransition() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let rainyHours = (1...6).map { offset in HourlyConditions(date: now.addingTimeInterval(Double(offset) * 3_600), temperature: 60, symbolName: "cloud.rain.fill", condition: "Rain", precipitationChance: 0.8, precipitationKind: .rain) }
        var current = CurrentConditions(temperature: 60, apparentTemperature: 60, condition: "Rain", symbolName: "cloud.rain.fill", precipitationChance: 0.8, humidity: 0.7, windSpeed: 5, windDirection: "N", uvIndex: 1, visibility: 5, pressure: 1010, precipitationKind: .rain)
        let ongoing = ForecastSnapshot(locationName: "Test", isSample: false, updatedAt: now, current: current, hourly: rainyHours, daily: [])
        XCTAssertFalse(NotificationPlanner.plan(snapshot: ongoing, now: now, rainEnabled: true, preparationEnabled: false, snowEnabled: false, uvEnabled: false).contains { $0.id.contains("precipitation") })
        let startingHours = [HourlyConditions(date: now.addingTimeInterval(3_600), temperature: 60, symbolName: "cloud.fill", condition: "Cloudy", precipitationChance: 0.1), HourlyConditions(date: now.addingTimeInterval(7_200), temperature: 60, symbolName: "cloud.rain.fill", condition: "Rain", precipitationChance: 0.8, precipitationKind: .rain)]
        current = CurrentConditions(temperature: 60, apparentTemperature: 60, condition: "Cloudy", symbolName: "cloud.fill", precipitationChance: 0.1, humidity: 0.7, windSpeed: 5, windDirection: "N", uvIndex: 1, visibility: 5, pressure: 1010, precipitationKind: .none)
        let starting = ForecastSnapshot(locationName: "Test", isSample: false, updatedAt: now, current: current, hourly: startingHours, daily: [])
        XCTAssertTrue(NotificationPlanner.plan(snapshot: starting, now: now, rainEnabled: true, preparationEnabled: false, snowEnabled: false, uvEnabled: false).contains { $0.id.contains("precipitation") })
    }

    func testForecastTimeZoneControlsFormattingAndDayGrouping() {
        let instant = Date(timeIntervalSince1970: 1_775_901_600) // 2026-04-13 12:00 UTC
        let utc = WeatherFormatting(timeZone: TimeZone(secondsFromGMT: 0)!)
        let newYork = WeatherFormatting(timeZone: TimeZone(identifier: "America/New_York")!)
        XCTAssertNotEqual(utc.hour(instant), newYork.hour(instant))
        XCTAssertEqual(newYork.calendar.timeZone.identifier, "America/New_York")
    }

    func testStaleCopyInterpolatesInsteadOfLeakingCodeText() {
        let message = WeatherStore.staleRefreshMessage(snapshot: forecast(apparent: 72))
        XCTAssertFalse(message.contains("snapshot.updatedAt"))
        XCTAssertTrue(message.contains("Showing weather updated"))
    }

    func testOneCheckInShowsQualifiedEarlyEstimate() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let guidance = GuidanceEngine.make(
            snapshot: forecast(apparent: 84, now: now),
            temperaturePreference: 0,
            windSensitivity: 0.5,
            samples: [GuidanceSample(date: now, apparentTemperature: 72, humidity: 0.5, windSpeed: 5, response: .comfortable)],
            now: now
        )
        XCTAssertTrue(guidance.isEstimate)
        XCTAssertFalse(guidance.isPersonalized)
        XCTAssertEqual(guidance.calibrationLabel, "Low confidence")
        XCTAssertTrue(guidance.detail.contains("may be inaccurate"))
    }

    func testWeatherRequestGateRejectsOlderAndWrongSourceResults() {
        var gate = WeatherRequestGate()
        let first = gate.begin(sourceID: "place:a")
        let second = gate.begin(sourceID: "place:b")
        XCTAssertFalse(gate.accepts(token: first, sourceID: "place:a"))
        XCTAssertFalse(gate.accepts(token: second, sourceID: "place:a"))
        XCTAssertTrue(gate.accepts(token: second, sourceID: "place:b"))
    }

    func testDelayedProviderCannotOverwriteNewerSelectedPlaceFailure() async {
        let store = WeatherStore(weatherProvider: DelayedFailingWeatherProvider())
        store.snapshot = .sample
        let slow = SavedPlace(name: "Slow", region: "Test", latitude: 1, longitude: 1, timeZoneIdentifier: "GMT")
        let fast = SavedPlace(name: "Fast", region: "Test", latitude: 2, longitude: 2, timeZoneIdentifier: "GMT")
        let first = Task { await store.loadSavedPlace(slow) }
        try? await Task.sleep(for: .milliseconds(10))
        await store.loadSavedPlace(fast)
        await first.value
        XCTAssertEqual(store.selectedSourceID, "place:\(fast.id.uuidString)")
        guard case .stale(let message) = store.displayState else { return XCTFail("Expected the active place failure to remain visible") }
        XCTAssertTrue(message.hasPrefix("Refresh failed"))
        XCTAssertFalse(message.contains("offline"))
    }

    func testDataCoordinatorRecoversSingletonProfile() throws {
        let schema = Schema([WeatherProfile.self, WeatherCheckIn.self, SavedPlace.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        container.mainContext.insert(WeatherProfile())
        container.mainContext.insert(WeatherProfile())
        try container.mainContext.save()
        DataCoordinator.prepare(context: container.mainContext)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<WeatherProfile>()), 1)
    }

    func testPersistentStoreUsesTheSharedPrivateCloudKitContainer() {
        let schema = Schema(versionedSchema: VaneSchemaV1.self)
        let configuration = VaneCloudKit.cloudBackedConfiguration(schema: schema)

        XCTAssertEqual(configuration.cloudKitContainerIdentifier, "iCloud.com.codearc.vane")
        XCTAssertNil(configuration.groupAppContainerIdentifier)
        XCTAssertFalse(configuration.isStoredInMemoryOnly)
    }

    func testWidgetSnapshotRoundTripsWithoutLosingForecastData() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        let original = VaneWidgetSnapshot.sample
        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(VaneWidgetSnapshot.self, from: encoded)
        let originalJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? NSDictionary)
        let decodedJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(decoded)) as? NSDictionary)

        XCTAssertEqual(decodedJSON, originalJSON)
        XCTAssertEqual(decoded.hourly.count, 12)
        XCTAssertEqual(decoded.daily.count, 10)
        XCTAssertEqual(decoded.guidanceHeadline, "Comfortable for you")
        XCTAssertEqual(decoded.guidanceIsPersonalized, true)
        XCTAssertEqual(decoded.guidanceIsEstimate, false)
        XCTAssertEqual(decoded.guidanceCalibrationLabel, "Well calibrated")
        XCTAssertNil(decoded.guidanceActionText)
    }

    func testWidgetFormattingUsesSavedUnitsAndLocationTimeZone() {
        let snapshot = VaneWidgetSnapshot.sample
        XCTAssertEqual(snapshot.temperatureText(72), "72°")
        XCTAssertEqual(snapshot.windText(7), "7 mph")
        XCTAssertEqual(snapshot.timeZone.identifier, "America/New_York")
        XCTAssertEqual(snapshot.hours(after: snapshot.updatedAt, limit: 4).count, 4)
    }

    func testWidgetMetricIdentityIsArchivableByWidgetKit() throws {
        let encoded = try JSONEncoder().encode(VaneWidgetMetric.allCases)
        let decoded = try JSONDecoder().decode([VaneWidgetMetric].self, from: encoded)
        XCTAssertEqual(decoded, VaneWidgetMetric.allCases)
    }

    func testEveryWidgetDeepLinkRoutesToWeatherContent() throws {
        let router = VaneRouter()
        let routes: [(String, VaneDestination)] = [
            ("vane://weather", .weather),
            ("vane://weather/alerts", .alerts),
            ("vane://weather/week", .forecast),
            ("vane://weather/conditions", .conditions),
            ("vane://weather/sun", .sun),
            ("vane://sense", .sense)
        ]

        for (value, expected) in routes {
            router.open(try XCTUnwrap(URL(string: value)))
            XCTAssertEqual(router.destination, expected)
        }
        XCTAssertEqual(router.sequence, routes.count)
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

private actor DelayedFailingWeatherProvider: WeatherProviding {
    func weather(for location: CLLocation) async throws -> WeatherKit.Weather {
        if location.coordinate.latitude == 1 {
            try await Task.sleep(for: .milliseconds(220))
            throw URLError(.notConnectedToInternet)
        }
        try await Task.sleep(for: .milliseconds(30))
        throw URLError(.cannotConnectToHost)
    }
}
