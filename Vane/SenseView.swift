import SwiftData
import SwiftUI

struct SenseView: View {
    @Query(sort: \WeatherCheckIn.createdAt, order: .reverse) private var checkIns: [WeatherCheckIn]
    @Query private var profiles: [WeatherProfile]
    @State private var axis: FeelContext = .humidity
    let snapshot: ForecastSnapshot

    private var profile: WeatherProfile? { profiles.first }
    private var samples: [GuidanceSample] {
        checkIns.compactMap {
            guard let response = $0.feelResponse else { return nil }
            return GuidanceSample(date: $0.createdAt, apparentTemperature: profile?.usesFeelsLikeTemperature == false ? $0.temperature : $0.apparentTemperature, humidity: $0.humidity, windSpeed: $0.windSpeed, response: response, contexts: $0.contexts, cloudCover: $0.cloudCover ?? 0.5, isTravel: $0.isTravel)
        }
    }
    private var summary: SenseProfileSummary { GuidanceEngine.profileSummary(temperaturePreference: profile?.temperaturePreference ?? 0, windSensitivity: profile?.windSensitivity ?? 0.5, humiditySensitivity: profile?.humiditySensitivity ?? 0.5, samples: samples) }

    var body: some View {
        ZStack {
            AtmosphericBackground(condition: snapshot.current)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        SectionKicker(title: "Sense")
                        Text("Conditions Sense recognizes")
                            .font(.largeTitle.bold())
                        Text("Stronger areas are conditions Sense has seen more often. This shows familiarity, not scientific certainty.")
                            .foregroundStyle(VaneTheme.muted)
                    }

                    currentRead
                    calibration
                    field
                    signals
                    learningNote
                }
                .padding(18)
                .padding(.bottom, 80)
                .containerRelativeFrame(.horizontal)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Sense")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var currentRead: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack { SectionKicker(title: "Right now"); Spacer(); Text(summary.status.rawValue).font(.caption.bold()).foregroundStyle(VaneTheme.blue) }
                if summary.canPersonalize {
                    Text(currentFitTitle).font(.title2.bold())
                    Text("Current conditions are compared with recent and seasonally similar check-ins.").font(.subheadline).foregroundStyle(VaneTheme.muted)
                } else {
                    Text("Still learning your range").font(.title2.bold())
                    Text("Current weather is not presented as a learned personal result yet.").font(.subheadline).foregroundStyle(VaneTheme.muted)
                }
            }.padding(20)
        }
    }

    private var calibration: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionKicker(title: "Calibration status")
                Text(summary.status.rawValue).font(.title2.bold())
                Text(summary.statusDetail).font(.subheadline).foregroundStyle(VaneTheme.muted)
                Text("Sense never becomes “100% learned.” New seasons and unfamiliar weather can always add context.").font(.caption).foregroundStyle(VaneTheme.muted)
            }.padding(20)
        }
    }

    private var field: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionKicker(title: "Familiar conditions")
                Picker("Second condition", selection: $axis) {
                    Text("Humidity").tag(FeelContext.humidity)
                    Text("Wind").tag(FeelContext.wind)
                    Text("Sun").tag(FeelContext.sun)
                }.pickerStyle(.segmented)

                HStack(alignment: .top, spacing: 8) {
                    VStack { Text(axisHighLabel); Spacer(); Text(axisLowLabel) }
                        .font(.caption2.bold()).foregroundStyle(VaneTheme.muted).frame(width: 42, height: 188)
                    Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                        ForEach(0..<5, id: \.self) { row in
                            GridRow {
                                ForEach(0..<7, id: \.self) { column in
                                    let familiarity = familiarity(row: row, column: column)
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(fieldColor(column: column).opacity(0.10 + familiarity * 0.82))
                                        .frame(height: 32)
                                        .overlay { Text(familiarity >= 0.62 ? "•" : familiarity >= 0.2 ? "·" : "").foregroundStyle(.white).accessibilityHidden(true) }
                                        .accessibilityLabel("\(temperatureLabel(column)), \(secondaryLabel(row)), \(familiarityLabel(familiarity))")
                                }
                            }
                        }
                    }
                }
                HStack { Text("COOLER"); Spacer(); Text("MILD"); Spacer(); Text("WARMER") }.font(.caption2.bold()).foregroundStyle(VaneTheme.muted)
                Text("Dots and color strength both indicate familiarity: little, some, or familiar context.").font(.caption).foregroundStyle(VaneTheme.muted)
            }.padding(20)
        }
    }

    private var signals: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionKicker(title: "Signals Sense has learned")
            signal("thermometer.medium", "Temperature", summary.temperatureSummary)
            signal("wind", "Wind", summary.windSummary)
            signal("humidity.fill", "Humidity", summary.humiditySummary)
            signal("sun.max.fill", "Sun", summary.sunSummary)
        }
    }

    private func signal(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol).foregroundStyle(VaneTheme.blue).frame(width: 34, height: 44)
            VStack(alignment: .leading, spacing: 2) { Text(title).font(.headline); Text(detail).font(.caption).foregroundStyle(VaneTheme.muted) }
            Spacer()
        }.padding(.horizontal, 16).frame(minHeight: 64).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var learningNote: some View {
        Label("Recent and seasonally similar moments matter more. Travel check-ins can help when similar weather returns, but receive less weight than your long-term pattern.", systemImage: "arrow.triangle.2.circlepath")
            .font(.caption).foregroundStyle(VaneTheme.muted).padding(4)
    }

    private var currentFitTitle: String {
        let current = Double(profile?.usesFeelsLikeTemperature == false ? snapshot.current.temperature : snapshot.current.apparentTemperature)
        if current < summary.comfortLow - 3 { return "Below your familiar range" }
        if current > summary.comfortHigh + 3 { return "Above your familiar range" }
        return "Inside your familiar range"
    }

    private var axisHighLabel: String { axis == .wind ? "WINDY" : axis == .sun ? "BRIGHT" : "HUMID" }
    private var axisLowLabel: String { axis == .wind ? "CALM" : axis == .sun ? "SHADE" : "DRY" }
    private func familiarity(row: Int, column: Int) -> Double {
        let temperature = 48 + Double(column) / 6 * 44
        let progress = 1 - Double(row) / 4
        let secondary = axis == .wind ? progress * 22 : progress
        return GuidanceEngine.familiarity(temperature: temperature, secondary: secondary, axis: axis, samples: samples)
    }
    private func fieldColor(column: Int) -> Color { Color(hue: 0.61 - Double(column) / 6 * 0.48, saturation: 0.72, brightness: 0.98) }
    private func temperatureLabel(_ column: Int) -> String { column < 2 ? "cool" : column > 4 ? "warm" : "mild" }
    private func secondaryLabel(_ row: Int) -> String { row < 2 ? axisHighLabel.lowercased() : row > 2 ? axisLowLabel.lowercased() : "moderate" }
    private func familiarityLabel(_ value: Double) -> String { value >= 0.62 ? "familiar context" : value >= 0.2 ? "some context" : "little context" }
}
