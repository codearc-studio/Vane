import Foundation

nonisolated enum WeatherMoodStyle: String, Sendable {
    case sunshine
    case fresh
    case cozy
    case electric
    case crisp
    case night
}

struct WeatherMood: Sendable, Equatable {
    let title: String
    let detail: String
    let symbolName: String
    let style: WeatherMoodStyle
}

nonisolated enum WeatherActivityKind: String, CaseIterable, Identifiable, Sendable {
    case walk
    case run
    case outdoorCoffee
    case picnic
    case dogWalk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .walk: "Walk"
        case .run: "Run"
        case .outdoorCoffee: "Outdoor coffee"
        case .picnic: "Picnic"
        case .dogWalk: "Dog walk"
        }
    }

    var symbolName: String {
        switch self {
        case .walk: "figure.walk"
        case .run: "figure.run"
        case .outdoorCoffee: "cup.and.saucer.fill"
        case .picnic: "basket.fill"
        case .dogWalk: "dog.fill"
        }
    }
}

struct WeatherActivityRecommendation: Identifiable, Sendable {
    let kind: WeatherActivityKind
    let score: Int
    let reason: String
    let bestStart: Date?
    let bestEnd: Date?

    var id: WeatherActivityKind { kind }
}

struct SeasonalWeatherMoment: Sendable, Equatable {
    let title: String
    let detail: String
    let symbolName: String
}

struct WeatherPersonality: Sendable, Equatable {
    let title: String
    let detail: String
    let symbolName: String
}

struct DayWeatherExperience: Sendable {
    let mood: WeatherMood
    let outdoorScore: Int
    let outdoorLabel: String
    let outdoorDetail: String
    let activities: [WeatherActivityRecommendation]
    let seasonalMoment: SeasonalWeatherMoment?
    let isPersonalized: Bool
}

enum WeatherFeatureEngine {
    static func makeExperience(
        snapshot: ForecastSnapshot,
        temperaturePreference: Double,
        windSensitivity: Double,
        humiditySensitivity: Double,
        usesFeelsLikeTemperature: Bool,
        samples: [GuidanceSample],
        now: Date = .now
    ) -> DayWeatherExperience {
        let summary = GuidanceEngine.profileSummary(
            temperaturePreference: temperaturePreference,
            windSensitivity: windSensitivity,
            humiditySensitivity: humiditySensitivity,
            samples: samples,
            now: now
        )
        let current = snapshot.current
        let center = summary.comfortCenter
        let currentTemperature = Double(usesFeelsLikeTemperature ? current.apparentTemperature : current.temperature)
        let hasSafetyAlert = snapshot.alerts.contains { $0.isActive && $0.severityLevel.priority >= WeatherAlertSeverity.moderate.priority }
        var outdoorScore = conditionsScore(
            temperature: currentTemperature,
            target: center,
            precipitationChance: current.precipitationChance,
            humidity: current.humidity,
            windSpeed: Double(current.windSpeed),
            isDaylight: current.isDaylight,
            kind: nil
        )
        if hasSafetyAlert { outdoorScore = min(outdoorScore, 24) }

        var activities: [WeatherActivityRecommendation] = []
        for kind in WeatherActivityKind.allCases {
            let recommendation = activityRecommendation(
                    kind: kind,
                    snapshot: snapshot,
                    comfortCenter: center,
                    usesFeelsLikeTemperature: usesFeelsLikeTemperature,
                    hasSafetyAlert: hasSafetyAlert,
                    now: now
                )
            activities.append(recommendation)
        }
        activities.sort { lhs, rhs in
            lhs.score == rhs.score ? lhs.kind.rawValue < rhs.kind.rawValue : lhs.score > rhs.score
        }

        return DayWeatherExperience(
            mood: mood(for: snapshot, outdoorScore: outdoorScore),
            outdoorScore: outdoorScore,
            outdoorLabel: scoreLabel(outdoorScore),
            outdoorDetail: outdoorDetail(
                score: outdoorScore,
                current: current,
                comfortCenter: center,
                hasSafetyAlert: hasSafetyAlert,
                isPersonalized: summary.canPersonalize
            ),
            activities: activities,
            seasonalMoment: seasonalMoment(snapshot: snapshot, now: now),
            isPersonalized: summary.canPersonalize
        )
    }

    static func personality(summary: SenseProfileSummary, samples: [GuidanceSample]) -> WeatherPersonality? {
        guard summary.canPersonalize else { return nil }

        let comfortable = samples.filter { $0.response == .comfortable }
        let sunnyComfort = comfortable.filter { ($0.isDaylight ?? true) && $0.cloudCover <= 0.35 }.count
        let cloudyComfort = comfortable.filter { $0.cloudCover >= 0.68 || ($0.precipitationChance ?? 0) >= 0.45 }.count
        let breezyComfort = comfortable.filter { $0.windSpeed >= 11 }.count

        if summary.comfortCenter >= 77 {
            return WeatherPersonality(title: "Heat Lover", detail: "Your check-ins lean toward warmer-than-mild conditions.", symbolName: "thermometer.sun.fill")
        }
        if summary.comfortCenter <= 65 {
            return WeatherPersonality(title: "Winter Soul", detail: "Your check-ins lean toward cooler, crisp conditions.", symbolName: "snowflake")
        }
        if cloudyComfort >= 2 && cloudyComfort > sunnyComfort {
            return WeatherPersonality(title: "Cozy Cloud", detail: "Cloudier, softer weather shows up in your comfortable moments.", symbolName: "cloud.fill")
        }
        if breezyComfort >= 2 {
            return WeatherPersonality(title: "Fresh Air Person", detail: "A little breeze often appears in weather you find comfortable.", symbolName: "wind")
        }
        if sunnyComfort >= 2 {
            return WeatherPersonality(title: "Sun Seeker", detail: "Brighter skies often appear in weather you find comfortable.", symbolName: "sun.max.fill")
        }
        return WeatherPersonality(title: "Mild-Day Person", detail: "Your check-ins cluster around easygoing, moderate weather.", symbolName: "cloud.sun.fill")
    }

    private static func activityRecommendation(
        kind: WeatherActivityKind,
        snapshot: ForecastSnapshot,
        comfortCenter: Double,
        usesFeelsLikeTemperature: Bool,
        hasSafetyAlert: Bool,
        now: Date
    ) -> WeatherActivityRecommendation {
        let candidates = snapshot.hourly.filter {
            $0.date >= now.addingTimeInterval(-300)
                && snapshot.calendar.isDate($0.date, inSameDayAs: now)
                && $0.isDaylight
        }
        let ranked = candidates.map { hour in
            let temperature = Double(usesFeelsLikeTemperature ? hour.apparentTemperature : hour.temperature)
            let score = conditionsScore(
                temperature: temperature,
                target: targetTemperature(for: kind, comfortCenter: comfortCenter),
                precipitationChance: hour.precipitationChance,
                humidity: hour.humidity,
                windSpeed: Double(max(hour.windSpeed, Int((Double(hour.windGust) * 0.65).rounded()))),
                isDaylight: hour.isDaylight,
                kind: kind
            )
            return (hour, hasSafetyAlert ? min(score, 24) : score)
        }
        let best = ranked.max { lhs, rhs in
            lhs.1 == rhs.1 ? lhs.0.date > rhs.0.date : lhs.1 < rhs.1
        }

        let currentTemperature = Double(usesFeelsLikeTemperature ? snapshot.current.apparentTemperature : snapshot.current.temperature)
        let fallbackScore = conditionsScore(
            temperature: currentTemperature,
            target: targetTemperature(for: kind, comfortCenter: comfortCenter),
            precipitationChance: snapshot.current.precipitationChance,
            humidity: snapshot.current.humidity,
            windSpeed: Double(snapshot.current.windSpeed),
            isDaylight: snapshot.current.isDaylight,
            kind: kind
        )
        let score = hasSafetyAlert ? min(best?.1 ?? fallbackScore, 24) : best?.1 ?? fallbackScore
        let conditions = best?.0
        let bestStart = best?.0.date
        let bestEnd = bestStart.map { start in
            let nearby = ranked
                .filter { $0.0.date >= start && $0.0.date <= start.addingTimeInterval(7_200) && $0.1 >= score - 7 }
                .map(\.0.date)
                .max() ?? start
            return nearby.addingTimeInterval(3_600)
        }

        return WeatherActivityRecommendation(
            kind: kind,
            score: score,
            reason: activityReason(
                score: score,
                temperature: Double(usesFeelsLikeTemperature ? conditions?.apparentTemperature ?? snapshot.current.apparentTemperature : conditions?.temperature ?? snapshot.current.temperature),
                target: targetTemperature(for: kind, comfortCenter: comfortCenter),
                precipitationChance: conditions?.precipitationChance ?? snapshot.current.precipitationChance,
                windSpeed: Double(conditions?.windSpeed ?? snapshot.current.windSpeed),
                hasSafetyAlert: hasSafetyAlert
            ),
            bestStart: bestStart,
            bestEnd: bestEnd
        )
    }

    private static func targetTemperature(for kind: WeatherActivityKind, comfortCenter: Double) -> Double {
        switch kind {
        case .run: comfortCenter - 8
        case .dogWalk: comfortCenter - 4
        case .walk: comfortCenter - 2
        case .outdoorCoffee: comfortCenter
        case .picnic: comfortCenter + 1
        }
    }

    private static func conditionsScore(
        temperature: Double,
        target: Double,
        precipitationChance: Double,
        humidity: Double,
        windSpeed: Double,
        isDaylight: Bool,
        kind: WeatherActivityKind?
    ) -> Int {
        var score = 100.0
        let temperatureWeight = kind == .run || kind == .dogWalk ? 3.2 : 2.7
        score -= abs(temperature - target) * temperatureWeight
        let rainWeight: Double = switch kind {
        case .picnic: 62
        case .outdoorCoffee: 56
        case .run: 42
        default: 48
        }
        score -= precipitationChance * rainWeight
        let windThreshold: Double = kind == .run ? 12 : 9
        score -= max(0, windSpeed - windThreshold) * (kind == .picnic || kind == .outdoorCoffee ? 2.4 : 1.55)
        score -= max(0, humidity - 0.72) * (kind == .run ? 52 : 30)
        if !isDaylight { score -= kind == .outdoorCoffee ? 6 : 12 }
        if kind == .dogWalk && temperature >= 90 { score -= (temperature - 89) * 5 }
        if kind == .run && temperature >= 84 { score -= (temperature - 83) * 3.5 }
        return Int(max(0, min(100, score)).rounded())
    }

    private static func scoreLabel(_ score: Int) -> String {
        switch score {
        case 86...: "Excellent"
        case 70...: "Good"
        case 50...: "Fair"
        case 30...: "Limited"
        default: "Stay flexible"
        }
    }

    private static func outdoorDetail(score: Int, current: CurrentConditions, comfortCenter: Double, hasSafetyAlert: Bool, isPersonalized: Bool) -> String {
        if hasSafetyAlert { return "An active official alert outweighs otherwise comfortable conditions." }
        if current.precipitationChance >= 0.55 { return "Rain is the biggest constraint right now." }
        if current.windSpeed >= 20 { return "Strong wind is the main drawback right now." }
        if Double(current.apparentTemperature) > comfortCenter + 12 { return "The heat pulls the score down; a cooler window may work better." }
        if Double(current.apparentTemperature) < comfortCenter - 12 { return "The cold pulls the score down; a milder window may work better." }
        if score >= 80 { return isPersonalized ? "Conditions sit close to your learned comfort range." : "Mild temperatures and a low rain chance line up nicely." }
        return "There is a workable window, with a few weather tradeoffs." 
    }

    private static func activityReason(score: Int, temperature: Double, target: Double, precipitationChance: Double, windSpeed: Double, hasSafetyAlert: Bool) -> String {
        if hasSafetyAlert { return "Check the official alert before making outdoor plans." }
        if precipitationChance >= 0.5 { return "A drier window would make this easier." }
        if windSpeed >= 20 { return "Wind is the main tradeoff." }
        if temperature >= target + 10 { return "Best after the warmest part of the day." }
        if temperature <= target - 10 { return "Best once temperatures climb a little." }
        if score >= 82 { return "Comfortable temperatures with few weather tradeoffs." }
        if score >= 65 { return "A solid option if the timing works for you." }
        return "Possible, but the weather asks for flexibility." 
    }

    private static func mood(for snapshot: ForecastSnapshot, outdoorScore: Int) -> WeatherMood {
        let current = snapshot.current
        let symbol = current.symbolName.lowercased()
        if snapshot.alerts.contains(where: { $0.isActive && $0.severityLevel.priority >= WeatherAlertSeverity.severe.priority }) {
            return WeatherMood(title: "Stay-Aware Day", detail: "The sky has something important to say.", symbolName: "exclamationmark.triangle.fill", style: .electric)
        }
        if symbol.contains("thunder") || symbol.contains("storm") {
            return WeatherMood(title: "Electric Skies", detail: "A dramatic weather day is unfolding.", symbolName: "cloud.bolt.rain.fill", style: .electric)
        }
        if current.precipitationKind == .snow || symbol.contains("snow") {
            return WeatherMood(title: "Snow Globe Day", detail: "Soft skies and wintry scenery set the mood.", symbolName: "snowflake", style: .crisp)
        }
        if current.precipitationChance >= 0.52 || symbol.contains("rain") {
            return WeatherMood(title: "Cozy Weather", detail: "A slower, rain-at-the-window kind of day.", symbolName: "cloud.rain.fill", style: .cozy)
        }
        if !current.isDaylight {
            return WeatherMood(title: "Soft Evening", detail: "The day has settled into its quieter side.", symbolName: "moon.stars.fill", style: .night)
        }
        if outdoorScore >= 86 && symbol.contains("sun") {
            return WeatherMood(title: "Golden Day", detail: "Bright skies and easy outdoor conditions align.", symbolName: "sun.max.fill", style: .sunshine)
        }
        if outdoorScore >= 74 {
            return WeatherMood(title: "Fresh Air Day", detail: "There is a good reason to step outside.", symbolName: "wind", style: .fresh)
        }
        if current.apparentTemperature >= 88 {
            return WeatherMood(title: "Summer Energy", detail: "Warmth is running the show today.", symbolName: "sun.haze.fill", style: .sunshine)
        }
        if current.apparentTemperature <= 42 {
            return WeatherMood(title: "Crisp & Bright", detail: "Cool air gives the day a sharper edge.", symbolName: "sparkles", style: .crisp)
        }
        if current.cloudCover >= 0.68 {
            return WeatherMood(title: "Slow-Sky Day", detail: "Soft cloud cover keeps everything low-key.", symbolName: "cloud.fill", style: .cozy)
        }
        return WeatherMood(title: "Easygoing Weather", detail: "A balanced day with room to improvise.", symbolName: "cloud.sun.fill", style: .fresh)
    }

    private static func seasonalMoment(snapshot: ForecastSnapshot, now: Date) -> SeasonalWeatherMoment? {
        let month = snapshot.calendar.component(.month, from: now)
        let current = snapshot.current
        guard current.precipitationChance < 0.4, current.windSpeed < 18 else { return nil }
        switch month {
        case 3...5 where (58...76).contains(current.apparentTemperature):
            return SeasonalWeatherMoment(title: "Spring is showing off", detail: "Mild air and manageable wind make this feel especially springlike.", symbolName: "leaf.fill")
        case 6...8 where (68...82).contains(current.apparentTemperature):
            return SeasonalWeatherMoment(title: "A soft summer day", detail: "Warm without being at the loudest end of summer.", symbolName: "sun.min.fill")
        case 9...11 where (48...68).contains(current.apparentTemperature):
            return SeasonalWeatherMoment(title: "That crisp fall feeling", detail: "Cooler air and a calmer sky bring the season into focus.", symbolName: "leaf.circle.fill")
        case 12, 1, 2:
            guard current.isDaylight && (32...50).contains(current.apparentTemperature) else { return nil }
            return SeasonalWeatherMoment(title: "Winter sun moment", detail: "A little daylight makes the cold feel more inviting.", symbolName: "sun.snow.fill")
        default:
            return nil
        }
    }
}
