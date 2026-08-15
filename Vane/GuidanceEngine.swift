import Foundation

struct GuidanceSample: Sendable {
    let date: Date
    let apparentTemperature: Double
    let humidity: Double
    let windSpeed: Double
    let response: FeelResponse
}

struct SenseProfileSummary: Sendable {
    struct CoverageCell: Identifiable, Sendable {
        let temperatureIndex: Int
        let windIndex: Int
        let familiarity: Double
        var id: String { "\(temperatureIndex)-\(windIndex)" }
    }

    let comfortCenter: Double
    let comfortLow: Double
    let comfortHigh: Double
    let confidence: Double
    let confidenceLabel: String
    let confidenceDetail: String
    let temperatureSummary: String
    let windSummary: String
    let humiditySummary: String
    let coverage: [CoverageCell]
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
    let confidenceLabel: String

    init(snapshot: ForecastSnapshot, profile: WeatherProfile?, checkIns: [WeatherCheckIn], now: Date = .now) {
        self = GuidanceEngine.make(
            snapshot: snapshot,
            temperaturePreference: profile?.temperaturePreference ?? 0,
            windSensitivity: profile?.windSensitivity ?? 0.5,
            humiditySensitivity: profile?.humiditySensitivity ?? 0.5,
            usesFeelsLikeTemperature: profile?.usesFeelsLikeTemperature ?? true,
            samples: checkIns.map {
                GuidanceSample(
                    date: $0.createdAt,
                    apparentTemperature: profile?.usesFeelsLikeTemperature == false ? $0.temperature : $0.apparentTemperature,
                    humidity: $0.humidity,
                    windSpeed: $0.windSpeed,
                    response: $0.feelResponse
                )
            },
            now: now
        )
    }

    init(headline: String, detail: String, action: Action?, humidityNote: String, confidenceLabel: String) {
        self.headline = headline
        self.detail = detail
        self.action = action
        self.humidityNote = humidityNote
        self.confidenceLabel = confidenceLabel
    }
}

enum GuidanceEngine {
    /// Builds a personal model from every answer. A cold or warm answer is evidence
    /// about that one set of conditions, not a permanent preference switch.
    static func profileSummary(
        temperaturePreference: Double,
        windSensitivity: Double,
        humiditySensitivity: Double,
        samples: [GuidanceSample],
        now: Date = .now
    ) -> SenseProfileSummary {
        let baseline = 71 + temperaturePreference * 5
        let relevant = seasonallyRelevant(samples: samples, now: now)
        let weightedSamples = relevant.map { sample in
            let responseOffset: Double
            switch sample.response {
            case .tooCold: responseOffset = 6
            case .comfortable: responseOffset = 0
            case .tooWarm: responseOffset = -6
            }
            let normalizedTemperature = sample.apparentTemperature
                - personalContextAdjustment(
                    apparentTemperature: sample.apparentTemperature,
                    humidity: sample.humidity,
                    windSpeed: sample.windSpeed,
                    windSensitivity: windSensitivity,
                    humiditySensitivity: humiditySensitivity
                )
            return (normalizedTemperature + responseOffset, evidenceWeight(for: sample.date, now: now))
        }

        // Onboarding remains a prior, so one unusual moment can refine it but cannot replace it.
        let priorWeight = max(1.5, 4 - Double(weightedSamples.count) * 0.25)
        let weightedTotal = weightedSamples.reduce(baseline * priorWeight) { $0 + $1.0 * $1.1 }
        let totalWeight = weightedSamples.reduce(priorWeight) { $0 + $1.1 }
        let center = min(86, max(56, weightedTotal / totalWeight))

        let temperatures = relevant.map(\.apparentTemperature)
        let winds = relevant.map(\.windSpeed)
        let humidities = relevant.map(\.humidity)
        let variety = min(1, span(of: temperatures) / 32) * 0.22
            + min(1, span(of: winds) / 18) * 0.14
            + min(1, span(of: humidities) / 0.38) * 0.14
        let volume = min(1, Double(relevant.count) / 9) * 0.5
        let confidence = min(1, volume + variety)
        let halfRange = 6 - confidence * 1.8

        let confidenceLabel: String
        let confidenceDetail: String
        switch confidence {
        case _ where relevant.isEmpty:
            confidenceLabel = "Starting point"
            confidenceDetail = "Your onboarding choices are the starting point. Different kinds of days will sharpen this view."
        case ..<0.36:
            confidenceLabel = "Early read"
            confidenceDetail = "A few more check-ins across different temperatures will matter more than repeating the same day."
        case ..<0.68:
            confidenceLabel = "Taking shape"
            confidenceDetail = "Vane has a useful pattern and is still separating temperature from wind and humidity."
        default:
            confidenceLabel = "Well rounded"
            confidenceDetail = "Your check-ins cover enough variety for Vane to compare similar conditions with confidence."
        }

        return SenseProfileSummary(
            comfortCenter: center,
            comfortLow: center - halfRange,
            comfortHigh: center + halfRange,
            confidence: confidence,
            confidenceLabel: confidenceLabel,
            confidenceDetail: confidenceDetail,
            temperatureSummary: temperatureSummary(center: center, baseline: baseline, samples: relevant),
            windSummary: windSummary(samples: relevant),
            humiditySummary: humiditySummary(samples: relevant, baseline: baseline),
            coverage: coverage(samples: relevant, now: now)
        )
    }

    static func make(
        snapshot: ForecastSnapshot,
        temperaturePreference: Double,
        windSensitivity: Double,
        humiditySensitivity: Double = 0.5,
        usesFeelsLikeTemperature: Bool = true,
        samples: [GuidanceSample],
        now: Date = .now
    ) -> PersonalGuidance {
        let current = snapshot.current
        let summary = profileSummary(
            temperaturePreference: temperaturePreference,
            windSensitivity: windSensitivity,
            humiditySensitivity: humiditySensitivity,
            samples: samples,
            now: now
        )
        let observedTemperature = Double(usesFeelsLikeTemperature ? current.apparentTemperature : current.temperature)
        let contextAdjustment = personalContextAdjustment(
            apparentTemperature: observedTemperature,
            humidity: current.humidity,
            windSpeed: Double(current.windSpeed),
            windSensitivity: windSensitivity,
            humiditySensitivity: humiditySensitivity
        )
        let personalDifference = observedTemperature + contextAdjustment - summary.comfortCenter
        let rainSoon = snapshot.hourly.prefix(6).map(\.precipitationChance).max() ?? current.precipitationChance

        let headline: String
        let detail: String
        if personalDifference <= -8 {
            headline = "This may feel cold to you."
            detail = current.windSpeed >= 12
                ? "Wind adds to a temperature that is already below your comfort range."
                : "These conditions sit well below your current comfort range."
        } else if personalDifference <= -4 {
            headline = "A little chilly for you."
            detail = current.windSpeed >= 12
                ? "A mix of temperature and wind puts this just below your range."
                : "A light layer should bring this closer to your range."
        } else if personalDifference >= 8 {
            headline = "This may feel hot to you."
            detail = current.humidity >= 0.65
                ? "Warmth and humidity combine to put this above your comfort range."
                : "These conditions sit well above your current comfort range."
        } else if personalDifference >= 4 {
            headline = "A little warm for you."
            detail = current.uvIndex >= 6
                ? "Warm conditions and strong sun may be more noticeable this afternoon."
                : "This is just above the range you have been comfortable in."
        } else {
            headline = "This should feel comfortable."
            detail = samples.isEmpty
                ? "This is close to your starting range. Each check-in adds context without locking in a permanent preference."
                : "Temperature, wind and humidity are close to the pattern your check-ins are building."
        }

        let action: PersonalGuidance.Action?
        if rainSoon >= 0.55 {
            action = .init(text: "Bring a rain layer", symbol: "umbrella.fill")
        } else if personalDifference <= -4 {
            action = .init(text: personalDifference <= -8 ? "Wear a warm layer" : "Bring a light layer", symbol: "thermometer.snowflake")
        } else if current.uvIndex >= 6 {
            action = .init(text: "Sun protection will help", symbol: "sun.max.fill")
        } else {
            action = nil
        }

        return PersonalGuidance(
            headline: headline,
            detail: detail,
            action: action,
            humidityNote: current.humidity >= 0.7 ? "Likely to feel muggy" : current.humidity <= 0.3 ? "Noticeably dry" : "Comfortable range",
            confidenceLabel: summary.confidenceLabel
        )
    }

    static func daytimeHours(in hours: [HourlyConditions], now: Date = .now, calendar: Calendar = .current) -> [HourlyConditions] {
        hours.filter { hour in
            let clockHour = calendar.component(.hour, from: hour.date)
            return calendar.isDate(hour.date, inSameDayAs: now)
                && hour.date >= now.addingTimeInterval(-300)
                && (7..<22).contains(clockHour)
        }
    }

    static func bestFitHour(
        in hours: [HourlyConditions],
        temperaturePreference: Double,
        windSensitivity: Double,
        humiditySensitivity: Double,
        usesFeelsLikeTemperature: Bool = true,
        samples: [GuidanceSample],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> HourlyConditions? {
        let candidates = daytimeHours(in: hours, now: now, calendar: calendar)
        let summary = profileSummary(
            temperaturePreference: temperaturePreference,
            windSensitivity: windSensitivity,
            humiditySensitivity: humiditySensitivity,
            samples: samples,
            now: now
        )
        return candidates.min { first, second in
            fitScore(first, center: summary.comfortCenter, windSensitivity: windSensitivity, humiditySensitivity: humiditySensitivity, usesFeelsLikeTemperature: usesFeelsLikeTemperature)
                < fitScore(second, center: summary.comfortCenter, windSensitivity: windSensitivity, humiditySensitivity: humiditySensitivity, usesFeelsLikeTemperature: usesFeelsLikeTemperature)
        }
    }

    static func seasonallyRelevant(samples: [GuidanceSample], now: Date) -> [GuidanceSample] {
        let calendar = Calendar.current
        let currentMonth = calendar.component(.month, from: now)
        let sameSeason = samples.filter { sample in
            let sampleMonth = calendar.component(.month, from: sample.date)
            let distance = min(abs(sampleMonth - currentMonth), 12 - abs(sampleMonth - currentMonth))
            return distance <= 2
        }
        return sameSeason.isEmpty ? samples : sameSeason
    }

    private static func fitScore(_ hour: HourlyConditions, center: Double, windSensitivity: Double, humiditySensitivity: Double, usesFeelsLikeTemperature: Bool) -> Double {
        let observedTemperature = Double(usesFeelsLikeTemperature ? hour.apparentTemperature : hour.temperature)
        let adjusted = observedTemperature + personalContextAdjustment(
            apparentTemperature: observedTemperature,
            humidity: hour.humidity,
            windSpeed: Double(hour.windSpeed),
            windSensitivity: windSensitivity,
            humiditySensitivity: humiditySensitivity
        )
        // Best means comfortable and practical, rather than simply closest in temperature.
        return abs(adjusted - center) + hour.precipitationChance * 3.5
    }

    private static func personalContextAdjustment(
        apparentTemperature: Double,
        humidity: Double,
        windSpeed: Double,
        windSensitivity: Double,
        humiditySensitivity: Double
    ) -> Double {
        let extraWindChill = windSpeed > 11
            ? -min(2.5, (windSpeed - 11) * 0.11 * max(0.2, windSensitivity))
            : 0
        let humidWarmth = apparentTemperature > 72 && humidity > 0.62
            ? min(2.2, (humidity - 0.62) * 8 * max(0.2, humiditySensitivity))
            : 0
        return extraWindChill + humidWarmth
    }

    private static func evidenceWeight(for date: Date, now: Date) -> Double {
        let days = max(0, now.timeIntervalSince(date) / 86_400)
        return max(0.22, exp(-days / 240))
    }

    private static func span(of values: [Double]) -> Double {
        guard let minimum = values.min(), let maximum = values.max() else { return 0 }
        return maximum - minimum
    }

    private static func temperatureSummary(center: Double, baseline: Double, samples: [GuidanceSample]) -> String {
        guard !samples.isEmpty else { return "Starting near mild conditions" }
        let shift = center - baseline
        if shift >= 2.5 { return "You tend to settle in on the warmer side" }
        if shift <= -2.5 { return "You tend to settle in on the cooler side" }
        return "Your comfortable center is staying near mild"
    }

    private static func windSummary(samples: [GuidanceSample]) -> String {
        let windy = samples.filter { $0.windSpeed >= 12 }
        guard windy.count >= 2 else { return "Needs more windy-day context" }
        let coldShare = Double(windy.filter { $0.response == .tooCold }.count) / Double(windy.count)
        if coldShare >= 0.5 { return "Wind often pulls conditions cooler for you" }
        return "Wind has not consistently changed your comfort"
    }

    private static func humiditySummary(samples: [GuidanceSample], baseline: Double) -> String {
        let humid = samples.filter { $0.humidity >= 0.65 && $0.apparentTemperature >= baseline }
        guard humid.count >= 2 else { return "Needs more humid-day context" }
        let warmShare = Double(humid.filter { $0.response == .tooWarm }.count) / Double(humid.count)
        if warmShare >= 0.5 { return "Humidity tends to amplify warmth for you" }
        return "Humidity has not shown a clear effect yet"
    }

    private static func coverage(samples: [GuidanceSample], now: Date) -> [SenseProfileSummary.CoverageCell] {
        let targetTemperatures = [50.0, 70.0, 88.0]
        let targetWinds = [3.0, 10.0, 19.0]
        return targetWinds.indices.flatMap { windIndex in
            targetTemperatures.indices.map { temperatureIndex in
                let density = samples.reduce(0.0) { total, sample in
                    let temperatureDistance = (sample.apparentTemperature - targetTemperatures[temperatureIndex]) / 13
                    let windDistance = (sample.windSpeed - targetWinds[windIndex]) / 8
                    let similarity = exp(-(temperatureDistance * temperatureDistance + windDistance * windDistance))
                    return total + similarity * evidenceWeight(for: sample.date, now: now)
                }
                return .init(
                    temperatureIndex: temperatureIndex,
                    windIndex: windIndex,
                    familiarity: min(1, density / 1.65)
                )
            }
        }
    }
}
