import Foundation

struct GuidanceSample: Sendable {
    let date: Date
    let apparentTemperature: Double
    let humidity: Double
    let windSpeed: Double
    let response: FeelResponse
    var contexts: Set<FeelContext> = []
    var cloudCover: Double = 0.5
    var isTravel = false
}

enum CalibrationStatus: String, Sendable {
    case learning = "Learning"
    case needsExperience = "Needs experience"
    case wellCalibrated = "Well calibrated"
    case needsRefreshing = "Needs refreshing"
}

struct SenseProfileSummary: Sendable {
    let comfortCenter: Double
    let comfortLow: Double
    let comfortHigh: Double
    let evidence: Double
    let status: CalibrationStatus
    let statusDetail: String
    let temperatureSummary: String
    let windSummary: String
    let humiditySummary: String
    let sunSummary: String
    let relevantSampleCount: Int

    var canPersonalize: Bool { relevantSampleCount >= 3 && evidence >= 0.24 && status != .needsRefreshing }
}

struct PersonalGuidance {
    struct Action {
        let text: String
        let symbol: String
    }

    let headline: String
    let detail: String
    let action: Action?
    let humidityNote: String
    let calibrationLabel: String
    let isPersonalized: Bool

    init(snapshot: ForecastSnapshot, profile: WeatherProfile?, checkIns: [WeatherCheckIn], now: Date = .now) {
        self = GuidanceEngine.make(
            snapshot: snapshot,
            temperaturePreference: profile?.temperaturePreference ?? 0,
            windSensitivity: profile?.windSensitivity ?? 0.5,
            humiditySensitivity: profile?.humiditySensitivity ?? 0.5,
            usesFeelsLikeTemperature: profile?.usesFeelsLikeTemperature ?? true,
            samples: checkIns.compactMap { checkIn in
                guard let response = checkIn.feelResponse else { return nil }
                return GuidanceSample(date: checkIn.createdAt, apparentTemperature: profile?.usesFeelsLikeTemperature == false ? checkIn.temperature : checkIn.apparentTemperature, humidity: checkIn.humidity, windSpeed: checkIn.windSpeed, response: response, contexts: checkIn.contexts, cloudCover: checkIn.cloudCover ?? 0.5, isTravel: checkIn.isTravel)
            },
            now: now
        )
    }

    init(headline: String, detail: String, action: Action?, humidityNote: String, calibrationLabel: String, isPersonalized: Bool) {
        self.headline = headline
        self.detail = detail
        self.action = action
        self.humidityNote = humidityNote
        self.calibrationLabel = calibrationLabel
        self.isPersonalized = isPersonalized
    }
}

enum GuidanceEngine {
    static func profileSummary(temperaturePreference: Double, windSensitivity: Double, humiditySensitivity: Double, samples: [GuidanceSample], now: Date = .now) -> SenseProfileSummary {
        let baseline = 71 + temperaturePreference * 5
        let valid = samples.filter { $0.date <= now.addingTimeInterval(300) }
        let relevant = seasonallyRelevant(samples: valid, now: now)
        let weighted = relevant.map { sample -> (Double, Double) in
            let normalized = sample.apparentTemperature - personalContextAdjustment(apparentTemperature: sample.apparentTemperature, humidity: sample.humidity, windSpeed: sample.windSpeed, windSensitivity: windSensitivity, humiditySensitivity: humiditySensitivity)
            let travelWeight = sample.isTravel ? 0.45 : 1
            return (normalized + sample.response.comfortOffset, evidenceWeight(for: sample.date, now: now) * travelWeight)
        }
        let priorWeight = max(1.8, 4.2 - Double(weighted.count) * 0.22)
        let center = min(88, max(54, weighted.reduce(baseline * priorWeight) { $0 + $1.0 * $1.1 } / weighted.reduce(priorWeight) { $0 + $1.1 }))
        let variety = min(1, span(of: relevant.map(\.apparentTemperature)) / 30) * 0.28
            + min(1, span(of: relevant.map(\.windSpeed)) / 16) * 0.16
            + min(1, span(of: relevant.map(\.humidity)) / 0.35) * 0.16
        let volume = min(1, Double(relevant.count) / 10) * 0.4
        let evidence = min(1, variety + volume)
        let latest = valid.map(\.date).max()
        let isStale = latest.map { now.timeIntervalSince($0) > 150 * 86_400 } ?? false
        let status: CalibrationStatus
        let detail: String
        if valid.isEmpty {
            status = .needsExperience
            detail = "Your starting choices are a gentle first estimate. Check in across different kinds of days."
        } else if isStale {
            status = .needsRefreshing
            detail = "Your earlier moments still help, but a few current-season check-ins will make this feel current again."
        } else if relevant.count >= 8 && evidence >= 0.62 {
            status = .wellCalibrated
            detail = "Sense recognizes a useful variety of temperatures, wind and humidity."
        } else {
            status = .learning
            detail = "Different conditions teach Sense more than repeating nearly identical weather."
        }
        let halfRange = 6.2 - evidence * 1.6
        return SenseProfileSummary(
            comfortCenter: center,
            comfortLow: center - halfRange,
            comfortHigh: center + halfRange,
            evidence: evidence,
            status: status,
            statusDetail: detail,
            temperatureSummary: temperatureSummary(center: center, baseline: baseline, samples: relevant),
            windSummary: contextSummary(.wind, samples: relevant, coldText: "Wind often makes conditions land cooler", warmText: "Wind often changes how warmth lands"),
            humiditySummary: contextSummary(.humidity, samples: relevant, coldText: "Humidity sometimes makes cool weather feel raw", warmText: "Humidity often amplifies warmth"),
            sunSummary: contextSummary(.sun, samples: relevant, coldText: "Sun can soften cooler conditions", warmText: "Direct sun often adds noticeable warmth"),
            relevantSampleCount: relevant.count
        )
    }

    static func make(snapshot: ForecastSnapshot, temperaturePreference: Double, windSensitivity: Double, humiditySensitivity: Double = 0.5, usesFeelsLikeTemperature: Bool = true, samples: [GuidanceSample], now: Date = .now) -> PersonalGuidance {
        let summary = profileSummary(temperaturePreference: temperaturePreference, windSensitivity: windSensitivity, humiditySensitivity: humiditySensitivity, samples: samples, now: now)
        let current = snapshot.current
        let observed = Double(usesFeelsLikeTemperature ? current.apparentTemperature : current.temperature)
        let difference = observed + personalContextAdjustment(apparentTemperature: observed, humidity: current.humidity, windSpeed: Double(current.windSpeed), windSensitivity: windSensitivity, humiditySensitivity: humiditySensitivity) - summary.comfortCenter
        let rainSoon = snapshot.hourly.prefix(6).map(\.precipitationChance).max() ?? current.precipitationChance
        let safetyAction: PersonalGuidance.Action?
        if !snapshot.alerts.isEmpty {
            safetyAction = .init(text: "Review the official alert", symbol: "exclamationmark.triangle.fill")
        } else if current.uvIndex >= 8 {
            safetyAction = .init(text: "Use strong sun protection", symbol: "sun.max.trianglebadge.exclamationmark.fill")
        } else if current.apparentTemperature >= 103 {
            safetyAction = .init(text: "Limit heat exposure", symbol: "thermometer.sun.fill")
        } else if current.apparentTemperature <= 10 {
            safetyAction = .init(text: "Protect against dangerous cold", symbol: "thermometer.snowflake")
        } else if rainSoon >= 0.55 {
            safetyAction = .init(text: "Bring a rain layer", symbol: "umbrella.fill")
        } else { safetyAction = nil }

        guard summary.canPersonalize else {
            return PersonalGuidance(
                headline: "Sense is still learning your range",
                detail: "These conditions are close to your starting preference. Check in occasionally to make this personal.",
                action: safetyAction,
                humidityNote: humidityNote(current.humidity),
                calibrationLabel: summary.status.rawValue,
                isPersonalized: false
            )
        }

        let headline: String
        let detail: String
        switch difference {
        case ..<(-10): headline = "Freezing for your range"; detail = "These conditions are far below weather you usually find comfortable."
        case ..<(-6): headline = "Cold for you"; detail = current.windSpeed >= 12 ? "Cold and wind combine below your familiar range." : "This sits below your familiar comfort range."
        case ..<(-3): headline = "Chilly for you"; detail = "A light layer may bring this closer to your range."
        case 3..<6: headline = "Warm for you"; detail = current.humidity >= 0.65 ? "Warmth and humidity combine above your familiar range." : "This is just above your familiar range."
        case 6..<10: headline = "Hot for you"; detail = "These conditions are well above weather you usually find comfortable."
        case 10...: headline = "Very hot for you"; detail = "Plan for conditions far above your familiar range."
        default: headline = current.humidity >= 0.7 ? "Comfortable, but humid" : "Comfortable for you"; detail = "This resembles weather you have checked in as comfortable."
        }
        let personalAction: PersonalGuidance.Action?
        if difference <= -6 { personalAction = .init(text: "Wear a warm layer", symbol: "thermometer.snowflake") }
        else if difference <= -3 { personalAction = .init(text: "Bring a light layer", symbol: "jacket") }
        else { personalAction = nil }
        return PersonalGuidance(headline: headline, detail: detail, action: safetyAction ?? personalAction, humidityNote: humidityNote(current.humidity), calibrationLabel: summary.status.rawValue, isPersonalized: true)
    }

    static func shouldPrompt(snapshot: ForecastSnapshot, samples: [GuidanceSample], frequency: CheckInFrequency, now: Date = .now) -> Bool {
        guard !snapshot.isPlaceholder, !snapshot.isSample else { return false }
        guard let latest = samples.max(by: { $0.date < $1.date }) else { return true }
        let hours = now.timeIntervalSince(latest.date) / 3_600
        guard hours >= frequency.minimumHours else { return false }
        let current = snapshot.current
        let similar = samples.contains { sample in
            now.timeIntervalSince(sample.date) < 45 * 86_400
                && abs(sample.apparentTemperature - Double(current.apparentTemperature)) < 4
                && abs(sample.humidity - current.humidity) < 0.12
                && abs(sample.windSpeed - Double(current.windSpeed)) < 5
        }
        let summary = profileSummary(temperaturePreference: 0, windSensitivity: 0.5, humiditySensitivity: 0.5, samples: samples, now: now)
        return !similar || summary.status == .needsRefreshing
    }

    static func daytimeHours(in hours: [HourlyConditions], now: Date = .now, calendar: Calendar = .current) -> [HourlyConditions] {
        hours.filter { $0.date >= now.addingTimeInterval(-300) && $0.isDaylight && calendar.isDate($0.date, inSameDayAs: now) }
    }

    static func bestFitHour(in hours: [HourlyConditions], temperaturePreference: Double, windSensitivity: Double, humiditySensitivity: Double, usesFeelsLikeTemperature: Bool = true, samples: [GuidanceSample], now: Date = .now, calendar: Calendar = .current) -> HourlyConditions? {
        let summary = profileSummary(temperaturePreference: temperaturePreference, windSensitivity: windSensitivity, humiditySensitivity: humiditySensitivity, samples: samples, now: now)
        guard summary.canPersonalize else { return nil }
        return daytimeHours(in: hours, now: now, calendar: calendar).min { fitScore($0, center: summary.comfortCenter, windSensitivity: windSensitivity, humiditySensitivity: humiditySensitivity, usesFeelsLikeTemperature: usesFeelsLikeTemperature) < fitScore($1, center: summary.comfortCenter, windSensitivity: windSensitivity, humiditySensitivity: humiditySensitivity, usesFeelsLikeTemperature: usesFeelsLikeTemperature) }
    }

    static func fitFamiliarity(hour: HourlyConditions, summary: SenseProfileSummary, windSensitivity: Double, humiditySensitivity: Double, usesFeelsLikeTemperature: Bool) -> Double {
        let score = fitScore(hour, center: summary.comfortCenter, windSensitivity: windSensitivity, humiditySensitivity: humiditySensitivity, usesFeelsLikeTemperature: usesFeelsLikeTemperature)
        return max(0, min(1, 1 - score / 16))
    }

    static func familiarity(temperature: Double, secondary: Double, axis: FeelContext, samples: [GuidanceSample], now: Date = .now) -> Double {
        let density = samples.reduce(0.0) { total, sample in
            let tempDistance = (sample.apparentTemperature - temperature) / 12
            let observedSecondary: Double
            let scale: Double
            switch axis {
            case .humidity: observedSecondary = sample.humidity; scale = 0.18
            case .wind: observedSecondary = sample.windSpeed; scale = 7
            case .sun: observedSecondary = 1 - sample.cloudCover; scale = 0.3
            default: observedSecondary = 0; scale = 1
            }
            let secondaryDistance = (observedSecondary - secondary) / scale
            return total + exp(-(tempDistance * tempDistance + secondaryDistance * secondaryDistance)) * evidenceWeight(for: sample.date, now: now) * (sample.isTravel ? 0.45 : 1)
        }
        return min(1, density / 1.7)
    }

    static func seasonallyRelevant(samples: [GuidanceSample], now: Date) -> [GuidanceSample] {
        let calendar = Calendar.current
        let currentMonth = calendar.component(.month, from: now)
        let sameSeason = samples.filter {
            let month = calendar.component(.month, from: $0.date)
            return min(abs(month - currentMonth), 12 - abs(month - currentMonth)) <= 2
        }
        return sameSeason.isEmpty ? samples : sameSeason
    }

    private static func fitScore(_ hour: HourlyConditions, center: Double, windSensitivity: Double, humiditySensitivity: Double, usesFeelsLikeTemperature: Bool) -> Double {
        let observed = Double(usesFeelsLikeTemperature ? hour.apparentTemperature : hour.temperature)
        let adjusted = observed + personalContextAdjustment(apparentTemperature: observed, humidity: hour.humidity, windSpeed: Double(hour.windSpeed), windSensitivity: windSensitivity, humiditySensitivity: humiditySensitivity)
        return abs(adjusted - center) + hour.precipitationChance * 3.5
    }

    private static func personalContextAdjustment(apparentTemperature: Double, humidity: Double, windSpeed: Double, windSensitivity: Double, humiditySensitivity: Double) -> Double {
        let wind = windSpeed > 11 ? -min(2.8, (windSpeed - 11) * 0.12 * max(0.2, windSensitivity)) : 0
        let humidity = apparentTemperature > 72 && humidity > 0.62 ? min(2.5, (humidity - 0.62) * 9 * max(0.2, humiditySensitivity)) : 0
        return wind + humidity
    }

    private static func evidenceWeight(for date: Date, now: Date) -> Double {
        let days = max(0, now.timeIntervalSince(date) / 86_400)
        return max(0.12, exp(-days / 210))
    }

    private static func span(of values: [Double]) -> Double {
        guard let min = values.min(), let max = values.max() else { return 0 }
        return max - min
    }

    private static func temperatureSummary(center: Double, baseline: Double, samples: [GuidanceSample]) -> String {
        guard samples.count >= 3 else { return "Still learning" }
        let shift = center - baseline
        if shift >= 2.5 { return "Comfort tends toward warmer conditions" }
        if shift <= -2.5 { return "Comfort tends toward cooler conditions" }
        return "Comfort stays near mild conditions"
    }

    private static func contextSummary(_ context: FeelContext, samples: [GuidanceSample], coldText: String, warmText: String) -> String {
        let explicit = samples.filter { $0.contexts.contains(context) }
        guard explicit.count >= 2 else { return "Still learning" }
        if explicit.filter({ $0.response.isWarm }).count > explicit.filter({ $0.response.isCold }).count { return warmText }
        return coldText
    }

    private static func humidityNote(_ humidity: Double) -> String {
        humidity >= 0.7 ? "Likely to feel muggy" : humidity <= 0.3 ? "Noticeably dry" : "Moderate humidity"
    }
}
