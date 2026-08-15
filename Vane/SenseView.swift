import SwiftData
import SwiftUI

struct SenseView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \WeatherCheckIn.createdAt, order: .reverse) private var checkIns: [WeatherCheckIn]
    @Query private var profiles: [WeatherProfile]
    @State private var appeared = false
    @State private var scrollSection: String?
    let snapshot: ForecastSnapshot

    private var profile: WeatherProfile? { profiles.first }
    private var samples: [GuidanceSample] {
        checkIns.map {
            GuidanceSample(
                date: $0.createdAt,
                apparentTemperature: profile?.usesFeelsLikeTemperature == false ? $0.temperature : $0.apparentTemperature,
                humidity: $0.humidity,
                windSpeed: $0.windSpeed,
                response: $0.feelResponse
            )
        }
    }
    private var summary: SenseProfileSummary {
        GuidanceEngine.profileSummary(
            temperaturePreference: profile?.temperaturePreference ?? 0,
            windSensitivity: profile?.windSensitivity ?? 0.5,
            humiditySensitivity: profile?.humiditySensitivity ?? 0.5,
            samples: samples
        )
    }

    var body: some View {
        ZStack {
            AtmosphericBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    hero
                        .senseEntrance(appeared: appeared, delay: 0, reduceMotion: reduceMotion)
                    currentRead
                        .senseEntrance(appeared: appeared, delay: 0.06, reduceMotion: reduceMotion)
                    learnedPattern
                        .senseEntrance(appeared: appeared, delay: 0.12, reduceMotion: reduceMotion)
                    coverageMap.id("coverage")
                        .senseEntrance(appeared: appeared, delay: 0.18, reduceMotion: reduceMotion)
                    learnedSignals.id("signals")
                        .senseEntrance(appeared: appeared, delay: 0.24, reduceMotion: reduceMotion)
                    if !checkIns.isEmpty {
                        recentContext
                            .senseEntrance(appeared: appeared, delay: 0.3, reduceMotion: reduceMotion)
                    }
                    learningNote
                        .senseEntrance(appeared: appeared, delay: 0.34, reduceMotion: reduceMotion)
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 140)
                .containerRelativeFrame(.horizontal)
            }
            .scrollIndicators(.hidden)
            .scrollPosition(id: $scrollSection, anchor: .top)
        }
        .foregroundStyle(VaneTheme.ink)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.7, bounce: 0.12)) {
                appeared = true
            }
        }
        .task {
            guard let target = ProcessInfo.processInfo.environment["VANE_SCREENSHOT_SECTION"] else { return }
            try? await Task.sleep(for: .milliseconds(250))
            scrollSection = target
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 9) {
                    VaneMark(size: 42)
                    Text("Sense")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                }
                Spacer()
                Text(summary.confidenceLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VaneTheme.muted)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(.regularMaterial, in: Capsule())
            }

            Text("Weather that learns\nthe whole picture.")
                .font(.system(size: 39, weight: .bold, design: .rounded))
                .tracking(-1.5)
                .fixedSize(horizontal: false, vertical: true)
            Text("Every check-in belongs to the temperature, wind, humidity, season and time it happened. One answer can guide Vane without defining you.")
                .font(.body)
                .foregroundStyle(VaneTheme.muted)
                .lineSpacing(4)
                .frame(maxWidth: 355, alignment: .leading)
        }
        .padding(.bottom, 4)
    }

    private var currentRead: some View {
        GlassCard(radius: 30) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        SectionKicker(title: "Right now")
                        Text(currentFitTitle)
                            .font(.title2.bold())
                    }
                    Spacer()
                    Text(senseTemperature.degrees)
                        .font(.system(size: 38, weight: .light, design: .rounded))
                }

                Text(currentFitDetail)
                    .font(.subheadline)
                    .foregroundStyle(VaneTheme.muted)
                    .lineSpacing(3)

                HStack(spacing: 8) {
                    ContextPill(symbol: "thermometer.medium", text: "\(temperatureBasisLabel) \(senseTemperature.degrees)")
                    ContextPill(symbol: "wind", text: "\(snapshot.current.windSpeed) mph")
                    ContextPill(symbol: "humidity.fill", text: snapshot.current.humidity.formatted(.percent.precision(.fractionLength(0))))
                }
            }
            .padding(22)
        }
    }

    private var learnedPattern: some View {
        GlassCard(radius: 30) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        SectionKicker(title: "Your comfort pattern")
                        Text("A range, not a rule")
                            .font(.title2.bold())
                    }
                    Spacer()
                    Text("~\(Int(summary.comfortCenter.rounded()))°")
                        .font(.title2.bold())
                        .foregroundStyle(VaneTheme.cyan)
                }

                VStack(spacing: 9) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(VaneTheme.ink.opacity(0.08))
                            Capsule()
                                .fill(LinearGradient(colors: [VaneTheme.blue, VaneTheme.cyan, VaneTheme.warm], startPoint: .leading, endPoint: .trailing))
                                .frame(width: proxy.size.width * 0.48)
                                .offset(x: proxy.size.width * 0.26)
                            Circle()
                                .fill(VaneTheme.ink)
                                .frame(width: 15, height: 15)
                                .shadow(color: VaneTheme.cyan.opacity(0.8), radius: 8)
                                .offset(x: proxy.size.width * 0.5 - 7.5)
                        }
                    }
                    .frame(height: 15)
                    HStack {
                        Text("Cooler")
                        Spacer()
                        Text("Comfort now: \(Int(summary.comfortLow.rounded()))–\(Int(summary.comfortHigh.rounded()))°")
                        Spacer()
                        Text("Warmer")
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(VaneTheme.muted)
                }

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("Clarity")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Text(summary.confidenceLabel)
                            .font(.caption)
                            .foregroundStyle(VaneTheme.muted)
                    }
                    ProgressView(value: summary.confidence)
                        .tint(VaneTheme.cyan)
                    Text(summary.confidenceDetail)
                        .font(.caption)
                        .foregroundStyle(VaneTheme.muted)
                        .lineSpacing(3)
                }
            }
            .padding(22)
        }
    }

    private var coverageMap: some View {
        GlassCard(radius: 30) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    SectionKicker(title: "Sense field")
                    HStack(alignment: .firstTextBaseline) {
                        Text("Conditions mapped")
                            .font(.title2.bold())
                        Spacer()
                        Text("TEMP × WIND")
                            .font(.caption2.bold())
                            .tracking(0.8)
                            .foregroundStyle(VaneTheme.muted)
                    }
                    Text("A continuous view of nearby weather moments. Color strength shows how much relevant context the model can draw from.")
                        .font(.caption)
                        .foregroundStyle(VaneTheme.muted)
                        .lineSpacing(3)
                }

                VStack(spacing: 8) {
                    HStack(spacing: 9) {
                        VStack {
                            Text("CALM")
                            Spacer()
                            Text("WINDY")
                        }
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(VaneTheme.muted)
                        .frame(width: 38, height: 179)

                        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                            ForEach(0..<5, id: \.self) { row in
                                GridRow {
                                    ForEach(0..<7, id: \.self) { column in
                                        let familiarity = fieldFamiliarity(row: row, column: column)
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .fill(fieldColor(column: column).opacity(0.10 + familiarity * 0.86))
                                            .frame(height: 31)
                                            .overlay {
                                                if familiarity > 0.68 {
                                                    Circle()
                                                        .fill(.white.opacity(0.9))
                                                        .frame(width: 4, height: 4)
                                                }
                                            }
                                            .accessibilityLabel(fieldAccessibility(row: row, column: column, familiarity: familiarity))
                                    }
                                }
                            }
                        }
                    }

                    HStack {
                        Text("COOLER")
                        Spacer()
                        Text("MILDER")
                        Spacer()
                        Text("WARMER")
                    }
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(VaneTheme.muted)
                }

                HStack(spacing: 9) {
                    Text("Less context")
                    HStack(spacing: 4) {
                        ForEach(0..<5, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(VaneTheme.cyan.opacity(0.12 + Double(index) * 0.2))
                                .frame(width: 24, height: 7)
                        }
                    }
                    Text("More context")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(VaneTheme.muted)
            }
            .padding(22)
        }
    }

    private var learnedSignals: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionKicker(title: "Signals in the model")
            SenseSignalRow(symbol: "thermometer.medium", title: "Temperature", detail: summary.temperatureSummary, tint: VaneTheme.cyan)
            SenseSignalRow(symbol: "wind", title: "Wind", detail: summary.windSummary, tint: VaneTheme.sky)
            SenseSignalRow(symbol: "humidity.fill", title: "Humidity", detail: summary.humiditySummary, tint: VaneTheme.blue)
        }
    }

    private var recentContext: some View {
        GlassCard(radius: 28) {
            VStack(alignment: .leading, spacing: 15) {
                SectionKicker(title: "Recent context")
                ForEach(Array(checkIns.prefix(3).enumerated()), id: \.element.persistentModelID) { index, checkIn in
                    HStack(spacing: 13) {
                        Image(systemName: checkIn.feelResponse.symbol)
                            .font(.caption.bold())
                            .foregroundStyle(responseColor(checkIn.feelResponse))
                            .frame(width: 34, height: 34)
                            .background(responseColor(checkIn.feelResponse).opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(checkIn.feelResponse.rawValue)
                                .font(.subheadline.bold())
                            Text("\(temperatureBasisLabel) \(Int(checkInTemperature(checkIn).rounded()))° · \(Int(checkIn.windSpeed.rounded())) mph wind · \(checkIn.humidity.formatted(.percent.precision(.fractionLength(0)))) humidity")
                                .font(.caption2)
                                .foregroundStyle(VaneTheme.muted)
                                .lineLimit(2)
                        }
                        Spacer()
                        Text(checkIn.createdAt.formatted(.relative(presentation: .named)))
                            .font(.caption2)
                            .foregroundStyle(VaneTheme.muted.opacity(0.8))
                    }
                    if index < min(3, checkIns.count) - 1 {
                        Divider().overlay(VaneTheme.hairline)
                    }
                }
            }
            .padding(20)
        }
    }

    private var learningNote: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.subheadline.bold())
                .foregroundStyle(VaneTheme.cyan)
                .frame(width: 34, height: 34)
                .background(VaneTheme.cyan.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text("Built to adapt")
                    .font(.subheadline.bold())
                Text("Recent and seasonally similar moments carry more weight. Older answers stay useful, but they gradually step back as your pattern changes.")
                    .font(.caption)
                    .foregroundStyle(VaneTheme.muted)
                    .lineSpacing(3)
            }
        }
        .padding(.horizontal, 3)
    }

    private var currentFitTitle: String {
        let current = Double(senseTemperature)
        if current < summary.comfortLow - 3 { return "Below your range" }
        if current > summary.comfortHigh + 3 { return "Above your range" }
        if current < summary.comfortLow { return "Near the cool edge" }
        if current > summary.comfortHigh { return "Near the warm edge" }
        return "Inside your range"
    }

    private var currentFitDetail: String {
        if checkIns.isEmpty {
            return "This compares current conditions with your onboarding starting point. Check-ins will add weather-specific context."
        }
        return "This compares today with seasonally relevant check-ins, then accounts for the wind and humidity around them."
    }

    private var senseTemperature: Int {
        profile?.usesFeelsLikeTemperature == false ? snapshot.current.temperature : snapshot.current.apparentTemperature
    }

    private var temperatureBasisLabel: String {
        profile?.usesFeelsLikeTemperature == false ? "Actual" : "Feels"
    }

    private func checkInTemperature(_ checkIn: WeatherCheckIn) -> Double {
        profile?.usesFeelsLikeTemperature == false ? checkIn.temperature : checkIn.apparentTemperature
    }

    private func coverageCell(temperature: Int, wind: Int) -> SenseProfileSummary.CoverageCell {
        summary.coverage.first { $0.temperatureIndex == temperature && $0.windIndex == wind }
            ?? .init(temperatureIndex: temperature, windIndex: wind, familiarity: 0)
    }

    private func fieldFamiliarity(row: Int, column: Int) -> Double {
        let temperature = Double(column) / 6 * 2
        let wind = Double(row) / 4 * 2
        let left = min(Int(floor(temperature)), 1)
        let top = min(Int(floor(wind)), 1)
        let temperatureMix = temperature - Double(left)
        let windMix = wind - Double(top)

        let upper = coverageCell(temperature: left, wind: top).familiarity * (1 - temperatureMix)
            + coverageCell(temperature: left + 1, wind: top).familiarity * temperatureMix
        let lower = coverageCell(temperature: left, wind: top + 1).familiarity * (1 - temperatureMix)
            + coverageCell(temperature: left + 1, wind: top + 1).familiarity * temperatureMix
        return min(max(upper * (1 - windMix) + lower * windMix, 0), 1)
    }

    private func fieldColor(column: Int) -> Color {
        Color(hue: 0.61 - (Double(column) / 6 * 0.48), saturation: 0.72, brightness: 0.98)
    }

    private func fieldAccessibility(row: Int, column: Int, familiarity: Double) -> String {
        let temperature = column < 2 ? "cool" : column > 4 ? "warm" : "mild"
        let wind = row < 2 ? "calm" : row > 2 ? "windy" : "breezy"
        let context = familiarity >= 0.62 ? "strong context" : familiarity >= 0.18 ? "some context" : "little context"
        return "\(temperature), \(wind), \(context)"
    }

    private func responseColor(_ response: FeelResponse) -> Color {
        switch response {
        case .tooCold: VaneTheme.blue
        case .comfortable: VaneTheme.cyan
        case .tooWarm: VaneTheme.warm
        }
    }
}

private struct ContextPill: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(VaneTheme.ink.opacity(0.055), in: Capsule())
    }
}

private struct SenseSignalRow: View {
    let symbol: String
    let title: String
    let detail: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.caption).foregroundStyle(VaneTheme.muted)
            }
            Spacer(minLength: 4)
        }
        .padding(15)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private extension View {
    func senseEntrance(appeared: Bool, delay: Double, reduceMotion: Bool) -> some View {
        opacity(appeared ? 1 : 0)
            .offset(y: reduceMotion || appeared ? 0 : 16)
            .animation(reduceMotion ? nil : .spring(duration: 0.62, bounce: 0.1).delay(delay), value: appeared)
    }
}
