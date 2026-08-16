import SwiftUI

struct DayDetailView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("temperatureUnit") private var temperatureUnitRaw = TemperatureUnitPreference.fahrenheit.rawValue
    @AppStorage("windUnit") private var windUnitRaw = WindUnitPreference.milesPerHour.rawValue
    @AppStorage("precipitationUnit") private var precipitationUnitRaw = PrecipitationUnitPreference.inches.rawValue
    let day: DailyConditions
    let snapshot: ForecastSnapshot
    let profile: WeatherProfile?
    let samples: [GuidanceSample]

    private var hours: [HourlyConditions] { snapshot.hourly.filter { snapshot.calendar.isDate($0.date, inSameDayAs: day.date) } }
    private var formatting: WeatherFormatting {
        WeatherFormatting(temperature: TemperatureUnitPreference(rawValue: temperatureUnitRaw) ?? .fahrenheit, wind: WindUnitPreference(rawValue: windUnitRaw) ?? .milesPerHour, precipitation: PrecipitationUnitPreference(rawValue: precipitationUnitRaw) ?? .inches, timeZone: snapshot.timeZone)
    }
    private var personalizedSummary: String? {
        GuidanceEngine.daySummary(day: day, hours: hours, temperaturePreference: profile?.temperaturePreference ?? 0, windSensitivity: profile?.windSensitivity ?? 0.5, humiditySensitivity: profile?.humiditySensitivity ?? 0.5, usesFeelsLikeTemperature: profile?.usesFeelsLikeTemperature ?? true, samples: samples)
    }
    private var columns: [GridItem] { dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())] }
    private var atmosphere: CurrentConditions {
        CurrentConditions(temperature: day.high, apparentTemperature: day.high, condition: day.condition, symbolName: day.symbolName, precipitationChance: day.precipitationChance, humidity: hours.first?.humidity ?? 0.5, windSpeed: day.windSpeed, windDirection: "", uvIndex: day.uvIndex, visibility: snapshot.current.visibility, pressure: snapshot.current.pressure, isDaylight: true)
    }

    var body: some View {
        ZStack {
            AtmosphericBackground(condition: atmosphere)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(formatting.dayHeading(day.date)).font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 8) { condition; Text(formatting.temperatureRange(low: Double(day.low), high: Double(day.high))).font(.title2.bold()) }
                        } else {
                            HStack { condition; Spacer(); Text(formatting.temperatureRange(low: Double(day.low), high: Double(day.high))).font(.title2.bold()) }
                        }
                        if let personalizedSummary { Text(personalizedSummary).foregroundStyle(VaneTheme.muted) }
                    }

                    if !hours.isEmpty { hourlyCard }

                    GlassCard {
                        LazyVGrid(columns: columns, spacing: 0) {
                            DetailMetric(title: "Precipitation chance", value: day.precipitationChance.formatted(.percent.precision(.fractionLength(0))), symbol: "drop.fill")
                            if day.precipitationAmount > 0 { DetailMetric(title: "Precipitation amount", value: formatting.precipitationAmount(day.precipitationAmount), symbol: "cloud.rain.fill") }
                            DetailMetric(title: "Wind / gusts", value: formatting.windRange(day.windSpeed, day.windGust), symbol: "wind")
                            DetailMetric(title: "UV index", value: "\(day.uvIndex)", symbol: "sun.max.fill")
                            if let humidity = averageHumidity { DetailMetric(title: "Humidity", value: humidity.formatted(.percent.precision(.fractionLength(0))), symbol: "humidity.fill") }
                            if let dewPoint = averageDewPoint { DetailMetric(title: "Dew point", value: formatting.degrees(dewPoint), symbol: "thermometer.medium") }
                            DetailMetric(title: "Sunrise", value: day.sunrise.map(formatting.shortTime) ?? "—", symbol: "sunrise.fill")
                            DetailMetric(title: "Sunset", value: day.sunset.map(formatting.shortTime) ?? "—", symbol: "sunset.fill")
                        }.padding(8)
                    }
                }
                .padding(18)
                .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? 190 : 60)
                .frame(maxWidth: .infinity, alignment: .leading)
                .containerRelativeFrame(.horizontal)
            }
        }
        .navigationTitle("Day Detail")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var condition: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: day.symbolName).symbolRenderingMode(.multicolor)
            Text(day.condition).fixedSize(horizontal: false, vertical: true)
        }.font(.title2.bold())
    }

    private var hourlyCard: some View {
        GlassCard {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(hours) { hour in
                        VStack(spacing: 8) {
                            Text(formatting.hour(hour.date)).font(.caption)
                            Image(systemName: hour.symbolName).symbolRenderingMode(.multicolor)
                            Text(formatting.degrees(hour.temperature)).font(.headline)
                            if hour.precipitationChance >= 0.2 { Text(hour.precipitationChance.formatted(.percent.precision(.fractionLength(0)))).font(.caption2).foregroundStyle(VaneTheme.blue) }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(formatting.hour(hour.date)), \(formatting.degrees(hour.temperature, includeUnit: true)), \(hour.condition), \(hour.precipitationChance.formatted(.percent.precision(.fractionLength(0)))) chance of precipitation")
                    }
                }.padding(18)
            }
        }
    }

    private var averageHumidity: Double? { hours.isEmpty ? nil : hours.map(\.humidity).reduce(0, +) / Double(hours.count) }
    private var averageDewPoint: Int? { hours.isEmpty ? nil : Int((Double(hours.map(\.dewPoint).reduce(0, +)) / Double(hours.count)).rounded()) }
}

private struct DetailMetric: View {
    let title: String
    let value: String
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(VaneTheme.muted)
            Text(value).font(.headline).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, minHeight: 82, alignment: .leading).padding(.horizontal, 12)
    }
}

struct WeatherAlertsView: View {
    let alerts: [WeatherAlertSnapshot]
    var body: some View {
        List(alerts) { alert in
            Link(destination: alert.detailsURL) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack { Text(alert.severity.uppercased()).font(.caption.bold()).foregroundStyle(.red); Spacer(); Image(systemName: "arrow.up.right") }
                    Text(alert.summary).font(.headline).foregroundStyle(VaneTheme.ink)
                    if let region = alert.region { Text(region).font(.caption).foregroundStyle(VaneTheme.muted) }
                    Text("Official source: \(alert.source)").font(.caption2).foregroundStyle(VaneTheme.muted)
                }.padding(.vertical, 6)
            }
        }.navigationTitle("Weather Alerts")
    }
}
