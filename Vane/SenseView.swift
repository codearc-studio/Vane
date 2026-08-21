import SwiftData
import SwiftUI

struct SenseView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("temperatureUnit") private var temperatureUnitRaw = TemperatureUnitPreference.localizedDefault.rawValue
    @Query(sort: \WeatherCheckIn.createdAt, order: .reverse) private var checkIns: [WeatherCheckIn]
    @Query private var profiles: [WeatherProfile]
    @State private var appeared = false
    @State private var scrollSection: String?
    let snapshot: ForecastSnapshot

    private var profile: WeatherProfile? { profiles.first }
    private var temperatureUnit: TemperatureUnitPreference { TemperatureUnitPreference(rawValue: temperatureUnitRaw) ?? .localizedDefault }
    private var formatting: WeatherFormatting { WeatherFormatting(temperature: temperatureUnit, timeZone: snapshot.timeZone) }
    private var samples: [GuidanceSample] {
        checkIns.compactMap { $0.guidanceSample(usesFeelsLikeTemperature: profile?.usesFeelsLikeTemperature ?? true) }
    }
    private var summary: SenseProfileSummary {
        GuidanceEngine.profileSummary(
            temperaturePreference: profile?.temperaturePreference ?? 0,
            windSensitivity: profile?.windSensitivity ?? 0.5,
            humiditySensitivity: profile?.humiditySensitivity ?? 0.5,
            samples: samples
        )
    }
    private var currentGuidance: PersonalGuidance {
        GuidanceEngine.make(
            snapshot: snapshot,
            temperaturePreference: profile?.temperaturePreference ?? 0,
            windSensitivity: profile?.windSensitivity ?? 0.5,
            humiditySensitivity: profile?.humiditySensitivity ?? 0.5,
            usesFeelsLikeTemperature: profile?.usesFeelsLikeTemperature ?? true,
            samples: samples
        )
    }
    private var weatherPersonality: WeatherPersonality? {
        WeatherFeatureEngine.personality(summary: summary, samples: samples)
    }

    var body: some View {
        ZStack {
            AtmosphericBackground(condition: snapshot.current)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    currentRead.id("current")
                    WeatherPersonalityCard(personality: weatherPersonality).id("style")
                    calibration.id("calibration")
                    signals.id("signals")
                    learningNote
                }
                .padding(18)
                .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? 190 : 80)
                .containerRelativeFrame(.horizontal)
                .scrollTargetLayout()
                .opacity(appeared ? 1 : 0)
                .offset(y: reduceMotion || appeared ? 0 : 12)
            }
            .scrollIndicators(.hidden)
            .scrollPosition(id: $scrollSection, anchor: .top)
        }
        .navigationTitle("Sense")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.55, bounce: 0.1)) {
                appeared = true
            }
        }
        .task {
            guard let target = ProcessInfo.processInfo.environment["VANE_SCREENSHOT_SENSE_SECTION"] else { return }
            try? await Task.sleep(for: .milliseconds(350))
            scrollSection = target
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                VaneMark(size: 42)
                Text("Sense").font(.title2.bold())
            }
            Text("Your weather, in context.")
                .font(.largeTitle.bold())
            Text("Sense compares the whole weather moment with what you have actually checked in about—then stays honest when a pattern is still new.")
                .foregroundStyle(VaneTheme.muted)
        }
    }

    private var currentRead: some View {
        GlassCard(radius: 34, tint: VaneTheme.blue.opacity(0.10)) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 22) {
                    SenseCurrentLens(
                        current: snapshot.current,
                        temperatureText: formatting.degrees(snapshot.current.apparentTemperature),
                        animate: !reduceMotion
                    )
                    currentReadCopy
                }
                VStack(alignment: .center, spacing: 18) {
                    SenseCurrentLens(
                        current: snapshot.current,
                        temperatureText: formatting.degrees(snapshot.current.apparentTemperature),
                        animate: !reduceMotion
                    )
                    currentReadCopy
                }
            }
            .padding(21)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    private var currentReadCopy: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionKicker(title: "Sense lens")
                Spacer()
                Text(familiarityLabel(currentGuidance.localFamiliarity))
                    .font(.caption2.bold())
                    .foregroundStyle(VaneTheme.blue)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.24), in: Capsule())
            }
            Text(currentGuidance.isPersonalized || currentGuidance.isEstimate ? currentFitTitle : "Still learning your range")
                .font(.title2.bold())
            Text(currentReadDetail)
                .font(.subheadline)
                .foregroundStyle(VaneTheme.muted)
            HStack(spacing: 8) {
                sensePill(formatting.degrees(snapshot.current.apparentTemperature), "thermometer.medium")
                sensePill(snapshot.current.humidity.formatted(.percent.precision(.fractionLength(0))), "humidity.fill")
                sensePill(snapshot.current.precipitationChance.formatted(.percent.precision(.fractionLength(0))), "drop.fill")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sensePill(_ value: String, _ symbol: String) -> some View {
        Label(value, systemImage: symbol)
            .font(.caption2.bold())
            .foregroundStyle(VaneTheme.blue)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(.white.opacity(0.24), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.30), lineWidth: 0.5))
    }

    private var calibration: some View {
        GlassCard(tint: VaneTheme.cyan.opacity(0.055)) {
            VStack(alignment: .leading, spacing: 17) {
                HStack(spacing: 18) {
                    SenseCoverageRing(progress: summary.evidence)
                    VStack(alignment: .leading, spacing: 5) {
                        SectionKicker(title: "Calibration")
                        Text(summary.status.rawValue)
                            .font(.title2.bold())
                        Text(summary.statusDetail)
                            .font(.subheadline)
                            .foregroundStyle(VaneTheme.muted)
                    }
                }

                Divider()

                LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                    calibrationTile("Comfort range", summary.canPersonalize ? formatting.temperatureRange(low: summary.comfortLow, high: summary.comfortHigh) : "Exploring", "thermometer.medium")
                    calibrationTile("Weather variety", evidenceLabel, "circle.hexagongrid.fill")
                    calibrationTile("Current match", familiarityLabel(currentGuidance.localFamiliarity), "scope")
                }

                Text("This ring shows breadth of experience, not certainty. New seasons and unfamiliar weather can always add context.")
                    .font(.caption)
                    .foregroundStyle(VaneTheme.muted)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    private func calibrationTile(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(VaneTheme.blue)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(VaneTheme.muted)
            Text(value)
                .font(.caption.bold())
                .lineLimit(2)
                .minimumScaleFactor(0.78)
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .background(VaneTheme.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var signals: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                SectionKicker(title: "Signals Sense has learned")
                Text("More than a temperature")
                    .font(.title2.bold())
                Text("A signal only becomes familiar through varied check-ins. Until then, Sense labels it as new or learning.")
                    .font(.subheadline)
                    .foregroundStyle(VaneTheme.muted)
            }

            LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(signalItems) { item in
                    SenseSignalCard(item: item)
                }
            }
        }
    }

    private var learningNote: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 15) {
                SectionKicker(title: "How a moment becomes a Sense read")
                HStack(alignment: .top, spacing: 4) {
                    learningStep("checkmark.bubble.fill", "You check in")
                    learningConnector
                    learningStep("circle.hexagongrid.fill", "Weather matches")
                    learningConnector
                    learningStep("calendar.badge.clock", "Season weighs in")
                    learningConnector
                    learningStep("sparkles", "Sense responds")
                }
                Text("Recent and seasonally similar moments matter more. Home patterns receive more weight; travel still helps when comparable weather returns.")
                    .font(.caption)
                    .foregroundStyle(VaneTheme.muted)
            }
            .padding(20)
        }
    }

    private func learningStep(_ symbol: String, _ title: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(VaneTheme.blue)
                .frame(width: 38, height: 38)
                .background(VaneTheme.blue.opacity(0.09), in: Circle())
            Text(title)
                .font(.caption2.bold())
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var learningConnector: some View {
        Capsule()
            .fill(VaneTheme.blue.opacity(0.18))
            .frame(width: 12, height: 2)
            .padding(.top, 18)
    }

    private var signalItems: [SenseSignalItem] {
        let dewPoints = samples.compactMap(\.dewPoint)
        let gusts = samples.compactMap(\.windGust)
        let pressures = samples.compactMap(\.pressure)
        let visibility = samples.compactMap(\.visibility)
        let precipitation = samples.compactMap(\.precipitationChance)
        let daylight = samples.compactMap(\.isDaylight)
        let months = Set(samples.map { Calendar.current.component(.month, from: $0.date) })
        let travelMoments = samples.filter(\.isTravel).count

        return [
            .init(title: "Temperature", symbol: "thermometer.medium", detail: summary.temperatureSummary, strength: max(summary.evidence, coverage(samples.map(\.apparentTemperature), usefulSpan: 24))),
            .init(title: "Wind", symbol: "wind", detail: summary.windSummary, strength: coverage(samples.map(\.windSpeed), usefulSpan: 14)),
            .init(title: "Humidity", symbol: "humidity.fill", detail: summary.humiditySummary, strength: coverage(samples.map(\.humidity), usefulSpan: 0.3)),
            .init(title: "Sun & cloud", symbol: "sun.max.fill", detail: summary.sunSummary, strength: coverage(samples.map(\.cloudCover), usefulSpan: 0.55)),
            .init(title: "Rain & dampness", symbol: "cloud.rain.fill", detail: summary.dampnessSummary, strength: coverage(precipitation, usefulSpan: 0.45)),
            .init(title: "Dew point", symbol: "drop.degreesign.fill", detail: coverageCopy(dewPoints.count, learned: "Helps separate dry air from muggy air"), strength: coverage(dewPoints, usefulSpan: 14)),
            .init(title: "Wind gusts", symbol: "wind.circle.fill", detail: coverageCopy(gusts.count, learned: "Distinguishes steady wind from sharper bursts"), strength: coverage(gusts, usefulSpan: 16)),
            .init(title: "Pressure", symbol: "gauge.with.dots.needle.50percent", detail: coverageCopy(pressures.count, learned: "Matches moments from similar weather systems"), strength: coverage(pressures, usefulSpan: 24)),
            .init(title: "Visibility", symbol: "eye.fill", detail: coverageCopy(visibility.count, learned: "Adds clear, foggy and hazy context"), strength: coverage(visibility, usefulSpan: 7)),
            .init(title: "Daylight", symbol: "sun.and.horizon.fill", detail: coverageCopy(daylight.count, learned: Set(daylight).count > 1 ? "Separates daylight from after-dark patterns" : "Learning one part of the day"), strength: min(1, Double(daylight.count) / 6 * (Set(daylight).count > 1 ? 1 : 0.55))),
            .init(title: "Season", symbol: "leaf.fill", detail: samples.isEmpty ? "Waiting for check-ins" : "Similar times of year receive more weight", strength: min(1, Double(months.count) / 4)),
            .init(title: "Home & travel", symbol: "location.fill.viewfinder", detail: samples.isEmpty ? "Waiting for check-ins" : travelMoments > 0 ? "Keeps travel useful without overpowering home" : "Building the long-term home pattern", strength: min(1, Double(samples.count) / 8))
        ]
    }

    private func coverage(_ values: [Double], usefulSpan: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let span = (values.max() ?? 0) - (values.min() ?? 0)
        let volume = min(1, Double(values.count) / 7)
        let variety = min(1, span / usefulSpan)
        return min(1, volume * 0.58 + variety * 0.42)
    }

    private func coverageCopy(_ count: Int, learned: String) -> String {
        if count >= 3 { return learned }
        if count > 0 { return "An early signal—still learning" }
        return "Available with new check-ins"
    }

    private var currentReadDetail: String {
        if currentGuidance.isEstimate { return currentGuidance.detail }
        if currentGuidance.isPersonalized { return "Compared with recent, seasonally similar weather across temperature, moisture, wind, light, rain and surrounding conditions." }
        return "Current weather is visible here, but Sense will not present it as a learned personal result yet."
    }

    private var currentFitTitle: String {
        switch currentGuidance.headline {
        case let value where value.contains("Freezing") || value.contains("Cold") || value.contains("Chilly"): return "Below your familiar range"
        case let value where value.contains("Warm") || value.contains("Hot"): return "Above your familiar range"
        default: return "Inside your familiar range"
        }
    }

    private var evidenceLabel: String {
        switch summary.evidence {
        case 0.62...: "Broad"
        case 0.24...: "Growing"
        default: "Early"
        }
    }

    private func familiarityLabel(_ value: Double) -> String {
        value >= 0.62 ? "Familiar" : value >= 0.2 ? "Some context" : "New territory"
    }
}

private struct SenseCurrentLens: View {
    let current: CurrentConditions
    let temperatureText: String
    let animate: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.20))
            Circle()
                .stroke(.white.opacity(0.42), lineWidth: 1)
            Circle()
                .trim(from: 0.06, to: 0.78)
                .stroke(
                    AngularGradient(colors: [VaneTheme.cyan.opacity(0.28), VaneTheme.blue, Color.cyan, VaneTheme.blue.opacity(0.28)], center: .center),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-94))
                .padding(5)

            VStack(spacing: 3) {
                Image(systemName: current.symbolName)
                    .font(.system(size: 35, weight: .light))
                    .symbolRenderingMode(.multicolor)
                    .symbolEffect(.bounce, value: animate)
                Text(temperatureText)
                    .font(.headline.bold().monospacedDigit())
                Text("FEELS LIKE")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(VaneTheme.muted)
            }
        }
        .frame(width: 132, height: 132)
        .shadow(color: VaneTheme.blue.opacity(0.14), radius: 18, y: 9)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sense lens. Current conditions: \(current.condition). Feels like \(temperatureText).")
    }
}

private struct SenseCoverageRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(VaneTheme.blue.opacity(0.1), lineWidth: 9)
            Circle()
                .trim(from: 0, to: max(0.04, min(0.92, progress * 0.92)))
                .stroke(
                    AngularGradient(colors: [Color.cyan, VaneTheme.blue, Color.mint], center: .center),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(VaneTheme.blue)
                .symbolEffect(.bounce, value: progress)
        }
        .frame(width: 88, height: 88)
        .accessibilityLabel("Calibration breadth is \(progress >= 0.62 ? "broad" : progress >= 0.24 ? "growing" : "early")")
    }
}

private struct SenseSignalItem: Identifiable {
    let title: String
    let symbol: String
    let detail: String
    let strength: Double
    var id: String { title }
}

private struct SenseSignalCard: View {
    let item: SenseSignalItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: item.symbol)
                    .font(.headline)
                    .foregroundStyle(VaneTheme.blue)
                    .frame(width: 34, height: 34)
                    .background(VaneTheme.blue.opacity(0.09), in: Circle())
                Spacer()
                Text(strengthLabel)
                    .font(.caption2.bold())
                    .foregroundStyle(VaneTheme.blue)
            }
            Text(item.title)
                .font(.headline)
            Text(item.detail)
                .font(.caption)
                .foregroundStyle(VaneTheme.muted)
                .frame(maxWidth: .infinity, minHeight: 46, alignment: .topLeading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(VaneTheme.blue.opacity(0.09))
                    Capsule()
                        .fill(VaneTheme.blue.gradient)
                        .frame(width: max(5, proxy.size.width * min(1, max(0, item.strength))))
                }
            }
            .frame(height: 5)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.title), \(strengthLabel), \(item.detail)")
    }

    private var strengthLabel: String {
        item.strength >= 0.65 ? "Familiar" : item.strength >= 0.24 ? "Learning" : "New"
    }
}
