import XCTest
import SwiftUI
@testable import Vane

@MainActor
final class WeatherFeatureEngineTests: XCTestCase {
    func testClearMildWeatherScoresHigherThanRainyWeather() {
        let now = fixedDate(hour: 10)
        let clear = experience(snapshot: forecast(now: now, temperature: 72, precipitation: 0.05, symbol: "sun.max.fill"), now: now)
        let rainy = experience(snapshot: forecast(now: now, temperature: 72, precipitation: 0.85, symbol: "cloud.rain.fill", kind: .rain), now: now)

        XCTAssertGreaterThan(clear.outdoorScore, rainy.outdoorScore)
        XCTAssertEqual(clear.mood.title, "Golden Day")
        XCTAssertEqual(rainy.mood.title, "Cozy Weather")
    }

    func testOfficialAlertCapsOutdoorAndActivityScores() {
        let now = fixedDate(hour: 10)
        let alert = WeatherAlertSnapshot(
            id: "warning",
            summary: "Severe Thunderstorm Warning",
            severity: "Severe",
            region: "Test County",
            source: "Official",
            detailsURL: URL(string: "https://example.com")!,
            expiresAt: .distantFuture
        )
        let result = experience(snapshot: forecast(now: now, temperature: 72, precipitation: 0.05, symbol: "sun.max.fill", alerts: [alert]), now: now)

        XCTAssertLessThanOrEqual(result.outdoorScore, 24)
        XCTAssertTrue(result.activities.allSatisfy { $0.score <= 24 })
        XCTAssertEqual(result.mood.title, "Stay-Aware Day")
        XCTAssertTrue(result.outdoorDetail.contains("official alert"))
    }

    func testActivityWindowsUseRemainingDaylightHours() {
        let now = fixedDate(hour: 10)
        let snapshot = forecast(now: now, temperature: 82, precipitation: 0.05, symbol: "sun.max.fill")
        let result = experience(snapshot: snapshot, now: now)

        XCTAssertEqual(result.activities.count, WeatherActivityKind.allCases.count)
        XCTAssertTrue(result.activities.allSatisfy { recommendation in
            guard let start = recommendation.bestStart else { return false }
            return start >= now.addingTimeInterval(-300)
                && snapshot.calendar.isDate(start, inSameDayAs: now)
        })
        XCTAssertEqual(result.activities.map(\.score), result.activities.map(\.score).sorted(by: >))
    }

    func testWeatherPersonalityWaitsForEnoughEvidence() {
        let learning = SenseProfileSummary(
            comfortCenter: 71,
            comfortLow: 65,
            comfortHigh: 77,
            evidence: 0.1,
            status: .learning,
            statusDetail: "Learning",
            temperatureSummary: "Still learning",
            windSummary: "Still learning",
            humiditySummary: "Still learning",
            sunSummary: "Still learning",
            dampnessSummary: "Still learning",
            relevantSampleCount: 2,
            effectiveSampleCount: 2
        )
        XCTAssertNil(WeatherFeatureEngine.personality(summary: learning, samples: []))

        let ready = SenseProfileSummary(
            comfortCenter: 71,
            comfortLow: 65,
            comfortHigh: 77,
            evidence: 0.5,
            status: .learning,
            statusDetail: "Learning",
            temperatureSummary: "Mild",
            windSummary: "Still learning",
            humiditySummary: "Still learning",
            sunSummary: "Still learning",
            dampnessSummary: "Still learning",
            relevantSampleCount: 4,
            effectiveSampleCount: 4
        )
        let sunny = (0..<3).map { offset in
            GuidanceSample(
                date: fixedDate(hour: 10 + offset),
                apparentTemperature: 71,
                humidity: 0.45,
                windSpeed: 5,
                response: .comfortable,
                cloudCover: 0.1,
                isDaylight: true
            )
        }
        XCTAssertEqual(WeatherFeatureEngine.personality(summary: ready, samples: sunny)?.title, "Sun Seeker")
    }

    func testShareCardRendersAtSocialCardSize() {
        let now = fixedDate(hour: 10)
        let snapshot = forecast(now: now, temperature: 72, precipitation: 0.05, symbol: "sun.max.fill")
        let result = experience(snapshot: snapshot, now: now)
        let renderer = ImageRenderer(
            content: WeatherShareCard(
                snapshot: snapshot,
                experience: result,
                formatting: WeatherFormatting(temperature: .fahrenheit, timeZone: snapshot.timeZone)
            )
        )
        renderer.scale = 1

        guard let image = renderer.uiImage else {
            XCTFail("Expected the weather share card to render an image")
            return
        }
        XCTAssertEqual(image.size.width, 360, accuracy: 0.5)
        XCTAssertEqual(image.size.height, 450, accuracy: 0.5)
    }

    func testAutomaticSunAppearanceUsesForecastSunriseAndSunset() {
        let sunrise = fixedDate(hour: 6)
        let sunset = fixedDate(hour: 20)
        let snapshot = solarForecast(sunrise: sunrise, sunset: sunset)

        XCTAssertEqual(AutomaticSunAppearance.appearance(for: snapshot, at: fixedDate(hour: 5)), .dark)
        XCTAssertEqual(AutomaticSunAppearance.appearance(for: snapshot, at: fixedDate(hour: 12)), .light)
        XCTAssertEqual(AutomaticSunAppearance.appearance(for: snapshot, at: fixedDate(hour: 21)), .dark)
    }

    func testAutomaticSunAppearanceReturnsNextSolarTransition() {
        let sunrise = fixedDate(hour: 6)
        let sunset = fixedDate(hour: 20)
        let snapshot = solarForecast(sunrise: sunrise, sunset: sunset)

        XCTAssertEqual(AutomaticSunAppearance.nextTransition(for: snapshot, after: fixedDate(hour: 5)), sunrise)
        XCTAssertEqual(AutomaticSunAppearance.nextTransition(for: snapshot, after: fixedDate(hour: 12)), sunset)
    }

    private func experience(snapshot: ForecastSnapshot, now: Date) -> DayWeatherExperience {
        WeatherFeatureEngine.makeExperience(
            snapshot: snapshot,
            temperaturePreference: 0,
            windSensitivity: 0.5,
            humiditySensitivity: 0.5,
            usesFeelsLikeTemperature: true,
            samples: [],
            now: now
        )
    }

    private func forecast(
        now: Date,
        temperature: Int,
        precipitation: Double,
        symbol: String,
        kind: PrecipitationKind = .none,
        alerts: [WeatherAlertSnapshot] = []
    ) -> ForecastSnapshot {
        let current = CurrentConditions(
            temperature: temperature,
            apparentTemperature: temperature,
            condition: kind == .rain ? "Rain" : "Clear",
            symbolName: symbol,
            precipitationChance: precipitation,
            humidity: 0.5,
            windSpeed: 6,
            windDirection: "W",
            uvIndex: 4,
            visibility: 10,
            pressure: 1015,
            precipitationKind: kind,
            cloudCover: kind == .rain ? 0.9 : 0.1,
            isDaylight: true
        )
        let hourly = (0..<8).map { offset in
            HourlyConditions(
                date: now.addingTimeInterval(Double(offset) * 3_600),
                temperature: temperature - max(0, offset - 3) * 2,
                symbolName: symbol,
                condition: kind == .rain ? "Rain" : "Clear",
                precipitationChance: precipitation,
                humidity: 0.5,
                windSpeed: 6,
                cloudCover: kind == .rain ? 0.9 : 0.1,
                isDaylight: true,
                precipitationKind: kind
            )
        }
        return ForecastSnapshot(
            locationName: "Test City",
            sourceID: "test",
            isSample: false,
            updatedAt: now,
            current: current,
            hourly: hourly,
            daily: [],
            alerts: alerts,
            timeZoneIdentifier: "UTC"
        )
    }

    private func solarForecast(sunrise: Date, sunset: Date) -> ForecastSnapshot {
        let base = forecast(now: fixedDate(hour: 12), temperature: 72, precipitation: 0.05, symbol: "sun.max.fill")
        let day = DailyConditions(
            date: fixedDate(hour: 12),
            low: 64,
            high: 76,
            symbolName: "sun.max.fill",
            condition: "Clear",
            precipitationChance: 0.05,
            sunrise: sunrise,
            sunset: sunset
        )
        return ForecastSnapshot(
            locationName: base.locationName,
            sourceID: base.sourceID,
            isSample: false,
            updatedAt: base.updatedAt,
            current: base.current,
            hourly: base.hourly,
            daily: [day],
            timeZoneIdentifier: "UTC"
        )
    }

    private func fixedDate(hour: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: hour))!
    }
}
