import SwiftUI

struct DayDetailView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("temperatureUnit") private var temperatureUnitRaw = TemperatureUnitPreference.localizedDefault.rawValue
    @AppStorage("windUnit") private var windUnitRaw = WindUnitPreference.localizedDefault.rawValue
    @AppStorage("precipitationUnit") private var precipitationUnitRaw = PrecipitationUnitPreference.localizedDefault.rawValue

    let day: DailyConditions
    let snapshot: ForecastSnapshot
    let profile: WeatherProfile?
    let samples: [GuidanceSample]

    private var hours: [HourlyConditions] {
        snapshot.hourly.filter { snapshot.calendar.isDate($0.date, inSameDayAs: day.date) }
    }
    private var formatting: WeatherFormatting {
        WeatherFormatting(
            temperature: TemperatureUnitPreference(rawValue: temperatureUnitRaw) ?? .localizedDefault,
            wind: WindUnitPreference(rawValue: windUnitRaw) ?? .localizedDefault,
            precipitation: PrecipitationUnitPreference(rawValue: precipitationUnitRaw) ?? .localizedDefault,
            timeZone: snapshot.timeZone
        )
    }
    private var personalizedSummary: String? {
        GuidanceEngine.daySummary(
            day: day,
            hours: hours,
            temperaturePreference: profile?.temperaturePreference ?? 0,
            windSensitivity: profile?.windSensitivity ?? 0.5,
            humiditySensitivity: profile?.humiditySensitivity ?? 0.5,
            usesFeelsLikeTemperature: profile?.usesFeelsLikeTemperature ?? true,
            samples: samples
        )
    }
    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())]
    }
    private var atmosphere: CurrentConditions {
        CurrentConditions(
            temperature: day.high,
            apparentTemperature: day.high,
            condition: day.condition,
            symbolName: day.symbolName,
            precipitationChance: day.precipitationChance,
            humidity: averageHumidity ?? 0.5,
            windSpeed: day.windSpeed,
            windDirection: "",
            uvIndex: day.uvIndex,
            visibility: snapshot.current.visibility,
            pressure: snapshot.current.pressure,
            isDaylight: true
        )
    }

    var body: some View {
        ZStack {
            AtmosphericBackground(condition: atmosphere)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    if !hours.isEmpty {
                        dayparts
                        hourlyCard
                    }
                    conditionsCard
                    solarCard
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? 130 : 34)
                .frame(maxWidth: .infinity, alignment: .leading)
                .containerRelativeFrame(.horizontal)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Day Detail")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hero: some View {
        GlassCard(radius: 32) {
            VStack(alignment: .leading, spacing: 18) {
                Text(formatting.dayHeading(day.date))
                    .font(.largeTitle.bold())
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .center, spacing: 18) {
                    Image(systemName: day.symbolName)
                        .font(.system(size: 62))
                        .symbolRenderingMode(.multicolor)
                        .frame(width: 76)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(day.condition)
                            .font(.title2.bold())
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(formatting.degrees(day.high))
                                .font(.system(size: 46, weight: .medium, design: .rounded))
                            Text("Low \(formatting.degrees(day.low))")
                                .font(.headline)
                                .foregroundStyle(VaneTheme.muted)
                        }
                    }
                }

                if let personalizedSummary {
                    Label(personalizedSummary, systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(VaneTheme.blue)
                } else {
                    Text(dayNarrative)
                        .font(.subheadline)
                        .foregroundStyle(VaneTheme.muted)
                }

                HStack(spacing: 10) {
                    heroPill(day.precipitationChance.formatted(.percent.precision(.fractionLength(0))), "drop.fill")
                    heroPill(formatting.windSpeed(day.windSpeed), "wind")
                    if day.uvIndex > 0 { heroPill("Peak UV \(day.uvIndex)", "sun.max.fill") }
                }
            }
            .padding(22)
        }
    }

    private var dayparts: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionKicker(title: "How the day changes")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    daypart("Morning", range: 5..<12, symbol: "sunrise.fill")
                    daypart("Afternoon", range: 12..<17, symbol: "sun.max.fill")
                    daypart("Evening", range: 17..<24, symbol: "sunset.fill")
                }
            }
        }
    }

    private func daypart(_ title: String, range: Range<Int>, symbol: String) -> some View {
        let matching = hours.filter { range.contains(snapshot.calendar.component(.hour, from: $0.date)) }
        let temperatures = matching.map(\.temperature)
        let high = temperatures.max()
        let low = temperatures.min()
        let wettest = matching.map(\.precipitationChance).max() ?? 0
        return GlassCard(radius: 23) {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: symbol)
                    .font(.caption.bold())
                    .foregroundStyle(VaneTheme.blue)
                Text(high.map { formatting.degrees($0) } ?? "—")
                    .font(.title2.bold())
                Text(low.map { "Low \(formatting.degrees($0))" } ?? "No hourly data")
                    .font(.caption)
                    .foregroundStyle(VaneTheme.muted)
                if wettest >= 0.2 {
                    Label(wettest.formatted(.percent.precision(.fractionLength(0))), systemImage: "drop.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(VaneTheme.blue)
                }
            }
            .frame(width: 128, alignment: .leading)
            .frame(minHeight: 116, alignment: .leading)
            .padding(16)
        }
    }

    private var hourlyCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionKicker(title: "Hour by hour")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(hours) { hour in
                            VStack(spacing: 8) {
                                Text(formatting.hour(hour.date))
                                    .font(.caption2.bold())
                                    .foregroundStyle(VaneTheme.muted)
                                Image(systemName: hour.symbolName)
                                    .symbolRenderingMode(.multicolor)
                                    .frame(height: 24)
                                Text(formatting.degrees(hour.temperature))
                                    .font(.headline)
                                Text("Feels \(formatting.degrees(hour.apparentTemperature))")
                                    .font(.caption2)
                                    .foregroundStyle(VaneTheme.muted)
                                if hour.precipitationChance >= 0.2 {
                                    Text(hour.precipitationChance.formatted(.percent.precision(.fractionLength(0))))
                                        .font(.caption2.bold())
                                        .foregroundStyle(VaneTheme.blue)
                                }
                            }
                            .frame(width: 72)
                            .frame(minHeight: 126)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(formatting.hour(hour.date)), \(formatting.degrees(hour.temperature, includeUnit: true)), feels like \(formatting.degrees(hour.apparentTemperature, includeUnit: true)), \(hour.condition)")
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private var conditionsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionKicker(title: "Day at a glance")
                LazyVGrid(columns: columns, spacing: 10) {
                    DayMetric(title: "Precipitation", value: day.precipitationChance.formatted(.percent.precision(.fractionLength(0))), detail: day.precipitationAmount > 0 ? formatting.precipitationAmount(day.precipitationAmount) : "Little or none", symbol: "drop.fill")
                    DayMetric(title: "Wind", value: formatting.windSpeed(day.windSpeed), detail: "Gusts \(formatting.windSpeed(day.windGust))", symbol: "wind")
                    if let humidity = averageHumidity {
                        DayMetric(title: "Humidity", value: humidity.formatted(.percent.precision(.fractionLength(0))), detail: "Daily average", symbol: "humidity.fill")
                    }
                    if let dewPoint = averageDewPoint {
                        DayMetric(title: "Dew point", value: formatting.degrees(dewPoint), detail: "Daily average", symbol: "thermometer.medium")
                    }
                    DayMetric(title: "Peak UV", value: "\(day.uvIndex)", detail: uvDescription, symbol: "sun.max.fill")
                    DayMetric(title: "Moon", value: day.moonPhase.isEmpty ? "Unavailable" : day.moonPhase, detail: day.moonrise.map { "Rises \(formatting.shortTime($0))" } ?? "No rise time", symbol: "moon.stars.fill")
                }
            }
            .padding(18)
        }
    }

    private var solarCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                SectionKicker(title: "Sunlight")
                HStack(alignment: .center, spacing: 10) {
                    solarPoint("Sunrise", day.sunrise, "sunrise.fill")
                    Capsule().fill(VaneTheme.blue.opacity(0.22)).frame(height: 4)
                    solarPoint("Solar noon", day.solarNoon, "sun.max.fill")
                    Capsule().fill(VaneTheme.blue.opacity(0.22)).frame(height: 4)
                    solarPoint("Sunset", day.sunset, "sunset.fill")
                }
                if let dawn = day.civilDawn, let dusk = day.civilDusk {
                    Text("First light \(formatting.shortTime(dawn)) · Last light \(formatting.shortTime(dusk))")
                        .font(.caption)
                        .foregroundStyle(VaneTheme.muted)
                }
            }
            .padding(20)
        }
    }

    private func heroPill(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .foregroundStyle(VaneTheme.blue)
            .background(VaneTheme.blue.opacity(0.10), in: Capsule())
    }

    private func solarPoint(_ title: String, _ date: Date?, _ symbol: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol).foregroundStyle(VaneTheme.blue)
            Text(title).font(.caption2).foregroundStyle(VaneTheme.muted)
            Text(date.map(formatting.shortTime) ?? "—").font(.caption.bold())
        }
        .frame(minWidth: 72)
    }

    private var averageHumidity: Double? {
        hours.isEmpty ? nil : hours.map(\.humidity).reduce(0, +) / Double(hours.count)
    }
    private var averageDewPoint: Int? {
        hours.isEmpty ? nil : Int((Double(hours.map(\.dewPoint).reduce(0, +)) / Double(hours.count)).rounded())
    }
    private var uvDescription: String {
        switch day.uvIndex {
        case ...2: "Low"
        case ...5: "Moderate"
        case ...7: "High"
        case ...10: "Very high"
        default: "Extreme"
        }
    }
    private var dayNarrative: String {
        if day.precipitationChance >= 0.6 { return "Rain is likely during part of the day. The hourly view shows when the chance is highest." }
        if day.windGust >= 25 { return "A breezy day with stronger gusts. Conditions can feel different from the temperature alone." }
        if day.high - day.low >= 20 { return "A wide temperature swing. Morning and evening may feel very different from the afternoon." }
        return "A closer look at the temperature, wind, moisture and daylight through this day."
    }
}

private struct DayMetric: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(VaneTheme.muted)
            Text(value)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(VaneTheme.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 94, alignment: .leading)
        .padding(14)
        .background(VaneTheme.ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
