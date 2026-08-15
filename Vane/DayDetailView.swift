import SwiftUI

struct DayDetailView: View {
    let day: DailyConditions
    let snapshot: ForecastSnapshot
    let personalizedSummary: String?

    private var hours: [HourlyConditions] { snapshot.hourly.filter { Calendar.current.isDate($0.date, inSameDayAs: day.date) } }

    var body: some View {
        ZStack {
            AtmosphericBackground(condition: snapshot.current)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(day.date.formatted(.dateTime.weekday(.wide).month(.wide).day())).font(.largeTitle.bold())
                        HStack {
                            Image(systemName: day.symbolName).symbolRenderingMode(.multicolor).font(.largeTitle)
                            Text(day.condition).font(.title2.bold())
                            Spacer()
                            Text("\(day.low.degrees)–\(day.high.degrees)").font(.title2.bold())
                        }
                        if let personalizedSummary { Text(personalizedSummary).foregroundStyle(VaneTheme.muted) }
                    }

                    if !hours.isEmpty {
                        GlassCard {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 18) {
                                    ForEach(hours) { hour in
                                        VStack(spacing: 8) {
                                            Text(hour.date.formatted(.dateTime.hour())).font(.caption)
                                            Image(systemName: hour.symbolName).symbolRenderingMode(.multicolor)
                                            Text(hour.temperature.degrees).font(.headline)
                                            if hour.precipitationChance >= 0.2 { Text(hour.precipitationChance.formatted(.percent.precision(.fractionLength(0)))).font(.caption2).foregroundStyle(VaneTheme.blue) }
                                        }
                                        .accessibilityElement(children: .ignore)
                                        .accessibilityLabel("\(hour.date.formatted(.dateTime.hour())), \(hour.temperature) degrees, \(hour.condition), \(hour.precipitationChance.formatted(.percent.precision(.fractionLength(0)))) chance of precipitation")
                                    }
                                }
                                .padding(18)
                            }
                        }
                    }

                    GlassCard {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 0) {
                            DetailMetric(title: "Precipitation", value: day.precipitationChance.formatted(.percent.precision(.fractionLength(0))), symbol: "drop.fill")
                            DetailMetric(title: "Wind / gusts", value: "\(day.windSpeed) / \(day.windGust) mph", symbol: "wind")
                            DetailMetric(title: "UV index", value: "\(day.uvIndex)", symbol: "sun.max.fill")
                            DetailMetric(title: "Air quality", value: "Data unavailable", symbol: "aqi.medium")
                            DetailMetric(title: "Sunrise", value: day.sunrise?.formatted(date: .omitted, time: .shortened) ?? "—", symbol: "sunrise.fill")
                            DetailMetric(title: "Sunset", value: day.sunset?.formatted(date: .omitted, time: .shortened) ?? "—", symbol: "sunset.fill")
                        }
                        .padding(8)
                    }
                }
                .padding(18)
                .padding(.bottom, 60)
            }
        }
        .navigationTitle("Day Detail")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DetailMetric: View {
    let title: String
    let value: String
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(VaneTheme.muted)
            Text(value).font(.headline).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .padding(.horizontal, 12)
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
        }
        .navigationTitle("Weather Alerts")
    }
}
