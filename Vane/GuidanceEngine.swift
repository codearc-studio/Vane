import Foundation

struct GuidanceSample: Sendable {
    let date: Date
    let apparentTemperature: Double
    let humidity: Double
    let windSpeed: Double
    let response: FeelResponse
    var contexts: Set<FeelContext> = []
    var cloudCover: Double = 0.5
    var dewPoint: Double?
    var windGust: Double?
    var pressure: Double?
    var visibility: Double?
    var precipitationChance: Double?
    var isDaylight: Bool?
    var isTravel = false
}

extension WeatherCheckIn {
    func guidanceSample(usesFeelsLikeTemperature: Bool = true) -> GuidanceSample? {
        guard let response = feelResponse else { return nil }
        let fingerprint = conditionFingerprint
        return GuidanceSample(
            date: createdAt,
            apparentTemperature: usesFeelsLikeTemperature ? apparentTemperature : temperature,
            humidity: humidity,
            windSpeed: windSpeed,
            response: response,
            contexts: contexts,
            cloudCover: cloudCover ?? 0.5,
            dewPoint: dewPoint,
            windGust: windGust,
            pressure: fingerprint.pressure.map(Double.init),
            visibility: fingerprint.visibility.map(Double.init),
            precipitationChance: precipitationChance,
            isDaylight: fingerprint.isDaylight,
            isTravel: isTravel
        )
    }
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
    let dampnessSummary: String
    let relevantSampleCount: Int
    let effectiveSampleCount: Double

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
    let calibrationLabel: String
    let isPersonalized: Bool
    let isEstimate: Bool
    let localFamiliarity: Double

    init(snapshot: ForecastSnapshot, profile: WeatherProfile?, checkIns: [WeatherCheckIn], now: Date = .now) {
        self = GuidanceEngine.make(
            snapshot: snapshot,
            temperaturePreference: profile?.temperaturePreference ?? 0,
            windSensitivity: profile?.windSensitivity ?? 0.5,
            humiditySensitivity: profile?.humiditySensitivity ?? 0.5,
            usesFeelsLikeTemperature: profile?.usesFeelsLikeTemperature ?? true,
            samples: checkIns.compactMap { $0.guidanceSample(usesFeelsLikeTemperature: profile?.usesFeelsLikeTemperature ?? true) },
            now: now
        )
    }

    init(headline: String, detail: String, action: Action?, calibrationLabel: String, isPersonalized: Bool, isEstimate: Bool = false, localFamiliarity: Double = 0) {
        self.headline = headline
        self.detail = detail
        self.action = action
        self.calibrationLabel = calibrationLabel
        self.isPersonalized = isPersonalized
        self.isEstimate = isEstimate
        self.localFamiliarity = localFamiliarity
    }
}

enum GuidanceEngine {
    static let predictionFamiliarityThreshold = 0.12
    static func profileSummary(temperaturePreference: Double, windSensitivity: Double, humiditySensitivity: Double, samples: [GuidanceSample], now: Date = .now) -> SenseProfileSummary {
        let baseline = 71 + temperaturePreference * 5
        let valid = samples.filter { $0.date <= now.addingTimeInterval(300) }
        let relevant = seasonallyRelevant(samples: valid, now: now)
        let context = learnedContextResiduals(samples: valid, windSensitivity: windSensitivity, humiditySensitivity: humiditySensitivity)
        let weighted = valid.map { sample -> (Double, Double) in
            let normalized = transformedTemperature(sample, context: context)
            let travelWeight = sample.isTravel ? 0.45 : 1
            let seasonWeight = isSeasonallyRelevant(sample.date, now: now) ? 1.0 : 0.18
            return (normalized + sample.response.comfortOffset, evidenceWeight(for: sample.date, now: now) * travelWeight * seasonWeight)
        }
        let priorWeight = max(1.8, 4.2 - Double(weighted.count) * 0.22)
        let center = min(88, max(54, weighted.reduce(baseline * priorWeight) { $0 + $1.0 * $1.1 } / weighted.reduce(priorWeight) { $0 + $1.1 }))
        let evidenceSamples = relevant.map { sample in (sample, evidenceWeight(for: sample.date, now: now) * (sample.isTravel ? 0.45 : 1)) }
        let effectiveCount = evidenceSamples.reduce(0) { $0 + $1.1 }
        let homeRelevant = relevant.filter { !$0.isTravel }
        let variety = min(1, span(of: homeRelevant.map(\.apparentTemperature)) / 30) * 0.28
            + min(1, span(of: homeRelevant.map(\.windSpeed)) / 16) * 0.16
            + min(1, span(of: homeRelevant.map(\.humidity)) / 0.35) * 0.16
        let volume = min(1, effectiveCount / 10) * 0.4
        let evidence = min(1, variety + volume)
        let latest = relevant.map(\.date).max()
        let isStale = latest.map { now.timeIntervalSince($0) > 150 * 86_400 } ?? false
        let status: CalibrationStatus
        let detail: String
        if valid.isEmpty {
            status = .needsExperience
            detail = "Your starting choices are a gentle first estimate. Check in across different kinds of days."
        } else if relevant.isEmpty || isStale {
            status = .needsRefreshing
            detail = "Your earlier moments still help, but a few current-season check-ins will make this feel current again."
        } else if effectiveCount >= 8 && evidence >= 0.62 {
            status = .wellCalibrated
            detail = "Sense recognizes a useful variety of temperatures and surrounding weather signals."
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
            dampnessSummary: contextSummary(.dampness, samples: relevant, coldText: "Rain and dampness often make conditions land cooler", warmText: "Rain and dampness can make warmth feel heavier"),
            relevantSampleCount: relevant.count,
            effectiveSampleCount: effectiveCount
        )
    }

    static func make(snapshot: ForecastSnapshot, temperaturePreference: Double, windSensitivity: Double, humiditySensitivity: Double = 0.5, usesFeelsLikeTemperature: Bool = true, samples: [GuidanceSample], now: Date = .now) -> PersonalGuidance {
        let summary = profileSummary(temperaturePreference: temperaturePreference, windSensitivity: windSensitivity, humiditySensitivity: humiditySensitivity, samples: samples, now: now)
        let current = snapshot.current
        let observed = Double(usesFeelsLikeTemperature ? current.apparentTemperature : current.temperature)
        let context = learnedContextResiduals(samples: samples, windSensitivity: windSensitivity, humiditySensitivity: humiditySensitivity)
        let transformed = transformedTemperature(observed: observed, humidity: current.humidity, windSpeed: Double(current.windSpeed), cloudCover: current.cloudCover, dewPoint: Double(current.dewPoint), windGust: Double(current.windGust), precipitationChance: current.precipitationChance, context: context)
        let difference = transformed - summary.comfortCenter
        let localFamiliarity = predictionFamiliarity(temperature: observed, humidity: current.humidity, windSpeed: Double(current.windSpeed), cloudCover: current.cloudCover, dewPoint: Double(current.dewPoint), windGust: Double(current.windGust), pressure: Double(current.pressure), visibility: Double(current.visibility), precipitationChance: current.precipitationChance, isDaylight: current.isDaylight, samples: samples, now: now)
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

        guard summary.canPersonalize, localFamiliarity >= predictionFamiliarityThreshold else {
            let unfamiliar = summary.canPersonalize
            if !samples.isEmpty && !unfamiliar {
                let earlyRead: String
                switch difference {
                case ..<(-6): earlyRead = "Likely cold for you"
                case ..<(-3): earlyRead = "Likely a little chilly"
                case 3..<6: earlyRead = "Likely a little warm"
                case 6...: earlyRead = "Likely hot for you"
                default: earlyRead = "Possibly near your comfort range"
                }
                return PersonalGuidance(
                    headline: earlyRead,
                    detail: "Early estimate only — Sense has \(samples.count) check-in\(samples.count == 1 ? "" : "s"), so this may be inaccurate. A few varied check-ins will make it more dependable.",
                    action: safetyAction,
                    calibrationLabel: "Low confidence",
                    isPersonalized: false,
                    isEstimate: true,
                    localFamiliarity: localFamiliarity
                )
            }
            return PersonalGuidance(
                headline: unfamiliar ? "These conditions are less familiar" : "Sense is still learning your range",
                detail: unfamiliar ? "Sense has learned your broader range, but has not seen enough weather like this to make a confident personal read." : "Check in occasionally across different conditions to make this personal.",
                action: safetyAction,
                calibrationLabel: summary.status.rawValue,
                isPersonalized: false,
                localFamiliarity: localFamiliarity
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
        return PersonalGuidance(headline: headline, detail: detail, action: safetyAction ?? personalAction, calibrationLabel: summary.status.rawValue, isPersonalized: true, localFamiliarity: localFamiliarity)
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
                && sample.pressure.map { abs($0 - Double(current.pressure)) < 18 } ?? true
                && sample.visibility.map { abs($0 - Double(current.visibility)) < 7 } ?? true
                && sample.precipitationChance.map { abs($0 - current.precipitationChance) < 0.3 } ?? true
                && sample.isDaylight.map { $0 == current.isDaylight } ?? true
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
        let context = learnedContextResiduals(samples: samples, windSensitivity: windSensitivity, humiditySensitivity: humiditySensitivity)
        let familiar = daytimeHours(in: hours, now: now, calendar: calendar).filter {
            predictionFamiliarity(temperature: Double(usesFeelsLikeTemperature ? $0.apparentTemperature : $0.temperature), humidity: $0.humidity, windSpeed: Double($0.windSpeed), cloudCover: $0.cloudCover, dewPoint: Double($0.dewPoint), windGust: Double($0.windGust), precipitationChance: $0.precipitationChance, isDaylight: $0.isDaylight, samples: samples, now: now) >= predictionFamiliarityThreshold
        }
        return familiar.min { fitScore($0, center: summary.comfortCenter, usesFeelsLikeTemperature: usesFeelsLikeTemperature, context: context) < fitScore($1, center: summary.comfortCenter, usesFeelsLikeTemperature: usesFeelsLikeTemperature, context: context) }
    }

    static func daySummary(day: DailyConditions, hours: [HourlyConditions], temperaturePreference: Double, windSensitivity: Double, humiditySensitivity: Double, usesFeelsLikeTemperature: Bool = true, samples: [GuidanceSample], now: Date = .now) -> String? {
        let summary = profileSummary(temperaturePreference: temperaturePreference, windSensitivity: windSensitivity, humiditySensitivity: humiditySensitivity, samples: samples, now: now)
        guard summary.canPersonalize else { return nil }
        let forecastTemperatures = hours.isEmpty ? [Double(day.low), Double(day.high)] : hours.map { Double(usesFeelsLikeTemperature ? $0.apparentTemperature : $0.temperature) }
        let locallyFamiliar = forecastTemperatures.contains { forecast in
            samples.contains { sample in
                abs(sample.apparentTemperature - forecast) < 7 && evidenceWeight(for: sample.date, now: now) * (sample.isTravel ? 0.45 : 1) >= 0.2
            }
        }
        guard locallyFamiliar else { return "Sense has limited experience with a day like this." }
        let middle = (Double(day.low) + Double(day.high)) / 2
        if Double(day.high) < summary.comfortLow - 3 { return "This day is likely cooler than your familiar range." }
        if Double(day.low) > summary.comfortHigh + 3 { return "This day is likely warmer than your familiar range." }
        if abs(middle - summary.comfortCenter) <= 5 { return "Part of this day is likely near your familiar range." }
        return middle < summary.comfortCenter ? "The milder hours may fit you best." : "The cooler hours may fit you best."
    }

    static func fitFamiliarity(hour: HourlyConditions, summary: SenseProfileSummary, windSensitivity: Double, humiditySensitivity: Double, usesFeelsLikeTemperature: Bool) -> Double {
        let score = abs(Double(usesFeelsLikeTemperature ? hour.apparentTemperature : hour.temperature) - summary.comfortCenter) + hour.precipitationChance * 3.5
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
            case .dampness: observedSecondary = sample.precipitationChance ?? (sample.contexts.contains(.dampness) ? 1 : 0); scale = 0.32
            default: observedSecondary = 0; scale = 1
            }
            let secondaryDistance = (observedSecondary - secondary) / scale
            return total + exp(-(tempDistance * tempDistance + secondaryDistance * secondaryDistance)) * evidenceWeight(for: sample.date, now: now) * (sample.isTravel ? 0.45 : 1)
        }
        return min(1, density / 1.7)
    }

    static func predictionFamiliarity(temperature: Double, humidity: Double, windSpeed: Double, cloudCover: Double, dewPoint: Double? = nil, windGust: Double? = nil, pressure: Double? = nil, visibility: Double? = nil, precipitationChance: Double? = nil, isDaylight: Bool? = nil, samples: [GuidanceSample], now: Date = .now) -> Double {
        let density = samples.reduce(0.0) { total, sample in
            let temperatureDistance = (sample.apparentTemperature - temperature) / 9
            let humidityDistance = (sample.humidity - humidity) / 0.2
            let windDistance = (sample.windSpeed - windSpeed) / 8
            let sunDistance = (sample.cloudCover - cloudCover) / 0.4
            var squared = temperatureDistance * temperatureDistance
                + humidityDistance * humidityDistance * 0.24
                + windDistance * windDistance * 0.20
                + sunDistance * sunDistance * 0.18
            if let dewPoint, let sampleDewPoint = sample.dewPoint { squared += pow((sampleDewPoint - dewPoint) / 12, 2) * 0.14 }
            if let windGust, let sampleWindGust = sample.windGust { squared += pow((sampleWindGust - windGust) / 12, 2) * 0.10 }
            if let pressure, let samplePressure = sample.pressure { squared += pow((samplePressure - pressure) / 20, 2) * 0.10 }
            if let visibility, let sampleVisibility = sample.visibility { squared += pow((sampleVisibility - visibility) / 8, 2) * 0.08 }
            if let precipitationChance, let samplePrecipitation = sample.precipitationChance { squared += pow((samplePrecipitation - precipitationChance) / 0.4, 2) * 0.14 }
            if let isDaylight, let sampleDaylight = sample.isDaylight, sampleDaylight != isDaylight { squared += 0.22 }
            let weight = evidenceWeight(for: sample.date, now: now) * (sample.isTravel ? 0.45 : 1) * (isSeasonallyRelevant(sample.date, now: now) ? 1 : 0.18)
            return total + exp(-squared) * weight
        }
        return min(1, density / 1.5)
    }

    static func seasonallyRelevant(samples: [GuidanceSample], now: Date) -> [GuidanceSample] {
        samples.filter { isSeasonallyRelevant($0.date, now: now) }
    }

    private static func fitScore(_ hour: HourlyConditions, center: Double, usesFeelsLikeTemperature: Bool, context: ContextResiduals) -> Double {
        let observed = Double(usesFeelsLikeTemperature ? hour.apparentTemperature : hour.temperature)
        let adjusted = transformedTemperature(observed: observed, humidity: hour.humidity, windSpeed: Double(hour.windSpeed), cloudCover: hour.cloudCover, dewPoint: Double(hour.dewPoint), windGust: Double(hour.windGust), precipitationChance: hour.precipitationChance, context: context)
        return abs(adjusted - center) + hour.precipitationChance * 3.5
    }

    private struct ContextResiduals {
        let wind: Double
        let humidity: Double
        let sun: Double
        let dampness: Double
    }

    private static func learnedContextResiduals(samples: [GuidanceSample], windSensitivity: Double, humiditySensitivity: Double) -> ContextResiduals {
        let learnedWind = learnedResidual(for: .wind, samples: samples)
        let explicitWindPrior = -max(0, windSensitivity - 0.5) * 1.5
        let learnedHumidity = learnedResidual(for: .humidity, samples: samples)
        let explicitHumidityPrior = max(0, humiditySensitivity - 0.5) * 1.5
        return ContextResiduals(
            wind: learnedWind == 0 ? explicitWindPrior : learnedWind,
            humidity: learnedHumidity == 0 ? explicitHumidityPrior : learnedHumidity,
            sun: learnedResidual(for: .sun, samples: samples),
            dampness: learnedResidual(for: .dampness, samples: samples)
        )
    }

    private static func learnedResidual(for context: FeelContext, samples: [GuidanceSample]) -> Double {
        let explicit = samples.filter { $0.contexts.contains(context) && $0.response != .comfortable }
        guard explicit.count >= 2 else { return 0 }
        let total = explicit.reduce(0.0) { partial, sample in
            let direction = sample.response.isWarm ? 1.0 : -1.0
            return partial + direction * min(3, abs(sample.response.comfortOffset) / 4)
        }
        return max(-3, min(3, total / Double(explicit.count)))
    }

    private static func transformedTemperature(_ sample: GuidanceSample, context: ContextResiduals) -> Double {
        transformedTemperature(observed: sample.apparentTemperature, humidity: sample.humidity, windSpeed: sample.windSpeed, cloudCover: sample.cloudCover, dewPoint: sample.dewPoint, windGust: sample.windGust, precipitationChance: sample.precipitationChance, context: context)
    }

    private static func transformedTemperature(observed: Double, humidity: Double, windSpeed: Double, cloudCover: Double, dewPoint: Double? = nil, windGust: Double? = nil, precipitationChance: Double? = nil, context: ContextResiduals) -> Double {
        let effectiveWind = max(windSpeed, (windGust ?? windSpeed) * 0.65)
        let windExposure = max(0, min(1, (effectiveWind - 6) / 16))
        let humidityExposure = max(
            max(0, min(1, (humidity - 0.5) / 0.35)),
            dewPoint.map { max(0, min(1, ($0 - 54) / 18)) } ?? 0
        )
        let sunExposure = max(0, min(1, (1 - cloudCover - 0.25) / 0.65))
        let dampnessExposure = max(0, min(1, precipitationChance ?? 0))
        return observed + context.wind * windExposure + context.humidity * humidityExposure + context.sun * sunExposure + context.dampness * dampnessExposure
    }

    private static func isSeasonallyRelevant(_ date: Date, now: Date) -> Bool {
        let calendar = Calendar.current
        let currentMonth = calendar.component(.month, from: now)
        let month = calendar.component(.month, from: date)
        return min(abs(month - currentMonth), 12 - abs(month - currentMonth)) <= 2
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

}
