import SwiftData
import SwiftUI

struct WeatherHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \WeatherCheckIn.createdAt, order: .reverse) private var checkIns: [WeatherCheckIn]
    @Query private var profiles: [WeatherProfile]
    @Bindable var store: WeatherStore
    @State private var didCheckIn = false
    @State private var showLocations = false
    @State private var scrollSection: String?
    @State private var appeared = false
    @State private var iconFloating = false

    private var snapshot: ForecastSnapshot { store.snapshot }
    private var guidance: PersonalGuidance {
        PersonalGuidance(snapshot: snapshot, profile: profiles.first, checkIns: checkIns)
    }
    private var guidanceSamples: [GuidanceSample] {
        checkIns.map {
            GuidanceSample(
                date: $0.createdAt,
                apparentTemperature: profiles.first?.usesFeelsLikeTemperature == false ? $0.temperature : $0.apparentTemperature,
                humidity: $0.humidity,
                windSpeed: $0.windSpeed,
                response: $0.feelResponse
            )
        }
    }

    var body: some View {
        ZStack {
            AtmosphericBackground()
            ScrollView {
                LazyVStack(spacing: 18) {
                    header
                        .weatherEntrance(appeared: appeared, delay: 0, reduceMotion: reduceMotion)
                    personalRead
                        .weatherEntrance(appeared: appeared, delay: 0.06, reduceMotion: reduceMotion)
                    weatherHero
                        .weatherEntrance(appeared: appeared, delay: 0.12, reduceMotion: reduceMotion)
                    if snapshot.isSample || store.errorMessage != nil { availabilityNotice }
                    checkIn
                    dayline
                    week.id("week")
                    conditions.id("conditions")
                    Text("Weather data provided by Apple Weather")
                        .font(.caption2)
                        .foregroundStyle(VaneTheme.muted.opacity(0.7))
                        .padding(.top, 4)
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 110)
                .containerRelativeFrame(.horizontal)
            }
            .scrollIndicators(.hidden)
            .scrollPosition(id: $scrollSection, anchor: .top)
            .refreshable { store.requestCurrentLocation() }
            .task {
                if ProcessInfo.processInfo.environment["VANE_SCREENSHOT_LOCATIONS"] == "1" {
                    try? await Task.sleep(for: .milliseconds(250))
                    showLocations = true
                }
                guard let target = ProcessInfo.processInfo.environment["VANE_SCREENSHOT_SECTION"] else { return }
                try? await Task.sleep(for: .milliseconds(250))
                scrollSection = target
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showLocations) { LocationsView(store: store) }
        .sensoryFeedback(.success, trigger: didCheckIn)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.7, bounce: 0.12)) {
                appeared = true
            }
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                iconFloating = true
            }
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 9) {
                VaneMark(size: 40)
                Text("Vane").font(.system(size: 18, weight: .bold, design: .rounded))
            }
            Spacer()
            Button { showLocations = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: store.isUsingCurrentLocation ? "location.fill" : "mappin")
                        .font(.caption)
                    Text(snapshot.locationName).lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption2.bold())
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 13)
                .frame(height: 38)
            }
            .vaneLiquidGlassButton()
        }
        .foregroundStyle(VaneTheme.ink)
        .frame(maxWidth: .infinity)
    }

    private var weatherHero: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.current.temperature.degrees)
                    .font(.system(size: 104, weight: .thin, design: .rounded))
                    .tracking(-6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .allowsTightening(true)
                    .layoutPriority(1)
                .contentTransition(.numericText())
                Text(snapshot.current.condition)
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                Text("Feels \(snapshot.current.apparentTemperature.degrees)  ·  H \(snapshot.daily.first?.high.degrees ?? "—")  L \(snapshot.daily.first?.low.degrees ?? "—")")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(VaneTheme.muted)
            }
            Spacer(minLength: 0)
            ZStack {
                Image(systemName: snapshot.current.symbolName)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 58))
                    .shadow(color: .white.opacity(0.75), radius: 18)
            }
            .padding(.bottom, 24)
            .offset(y: iconFloating ? -4 : 3)
            .scaleEffect(iconFloating ? 1.025 : 0.98)
        }
        .foregroundStyle(VaneTheme.ink)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var availabilityNotice: some View {
        Button { store.requestCurrentLocation() } label: {
            HStack(spacing: 12) {
                Image(systemName: "location.circle.fill").font(.title2).foregroundStyle(VaneTheme.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Showing a sample forecast").font(.subheadline.bold())
                    Text(store.errorMessage ?? "Allow location to load live conditions.")
                        .font(.caption).foregroundStyle(VaneTheme.muted)
                }
                Spacer()
                Image(systemName: "arrow.clockwise").font(.caption.bold()).foregroundStyle(VaneTheme.muted)
            }
            .padding(16)
        }
        .vaneLiquidGlassButton()
    }

    private var personalRead: some View {
        GlassCard(radius: 32) {
            ZStack(alignment: .trailing) {
                CompassRose(color: VaneTheme.ink).frame(width: 170, height: 170).offset(x: 52, y: 34)
                VStack(alignment: .leading, spacing: 17) {
                    HStack {
                        SectionKicker(title: "Your Sense")
                        Spacer()
                        Text(guidance.confidenceLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(VaneTheme.muted)
                    }
                    Text(guidance.headline)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .tracking(-1)
                        .frame(maxWidth: 300, alignment: .leading)
                    Text(guidance.detail)
                        .font(.subheadline)
                        .foregroundStyle(VaneTheme.muted)
                        .lineSpacing(3)
                        .frame(maxWidth: 310, alignment: .leading)
                    if let action = guidance.action {
                        Label(action.text, systemImage: action.symbol)
                            .font(.subheadline.bold())
                            .padding(.horizontal, 13)
                            .frame(height: 38)
                            .background(VaneTheme.blue.opacity(0.11), in: Capsule())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .foregroundStyle(VaneTheme.ink)
        }
    }

    @ViewBuilder
    private var checkIn: some View {
        if didCheckIn {
            HStack(spacing: 11) {
                Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                    .frame(width: 28, height: 28).background(VaneTheme.blue, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text("Noted for days like this").font(.subheadline.bold())
                    Text("That answer is now part of your Sense.").font(.caption).foregroundStyle(VaneTheme.muted)
                }
                Spacer()
            }
            .padding(.horizontal, 4)
            .transition(.blurReplace)
        } else {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Tune your Sense").font(.headline)
                    Spacer()
                    Text("ONE TAP").font(.caption2.bold()).tracking(0.8).foregroundStyle(VaneTheme.muted)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3), spacing: 7) {
                    ForEach(FeelResponse.allCases) { response in
                        Button { record(response) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: response.symbol).font(.caption)
                                Text(shortLabel(for: response)).font(.caption.bold()).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                        }
                        .vaneLiquidGlassButton()
                    }
                }
            }
            .foregroundStyle(VaneTheme.ink)
            .padding(.horizontal, 4)
        }
    }

    private var dayline: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionKicker(title: "Best fit today")
                    Text(bestWindowText).font(.title3.bold())
                }
                Spacer()
                Text("Next 12 hours").font(.caption).foregroundStyle(VaneTheme.muted)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(snapshot.hourly.prefix(12))) { hour in
                        VStack(spacing: 10) {
                            Text(isCurrentHour(hour) ? "Now" : hour.date.formatted(.dateTime.hour()))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(VaneTheme.muted)
                            Image(systemName: hour.symbolName)
                                .symbolRenderingMode(.multicolor)
                                .font(.title3)
                                .frame(height: 24)
                            ZStack {
                                Capsule().fill(daylineColor(for: hour).opacity(0.25)).frame(width: 54, height: 4)
                                Circle().fill(daylineColor(for: hour)).frame(width: 10, height: 10)
                                    .overlay { Circle().stroke(.white, lineWidth: 2) }
                            }
                            Text(hour.temperature.degrees).font(.body.bold())
                            Text(hour.precipitationChance >= 0.25 ? hour.precipitationChance.formatted(.percent.precision(.fractionLength(0))) : " ")
                                .font(.caption2.bold()).foregroundStyle(VaneTheme.blue)
                        }
                        .frame(width: 64)
                    }
                }
            }
        }
        .foregroundStyle(VaneTheme.ink)
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var week: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                SectionKicker(title: "The week ahead")
                Spacer()
                Text("Rain  ·  Low / High")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(VaneTheme.muted)
            }
            ForEach(Array(snapshot.daily.enumerated()), id: \.element.id) { index, day in
                HStack(spacing: 10) {
                    Text(index == 0 ? "Today" : day.date.formatted(.dateTime.weekday(.wide)))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(width: 82, alignment: .leading)
                    Image(systemName: day.symbolName).symbolRenderingMode(.multicolor).frame(width: 24)
                    Label(day.precipitationChance.formatted(.percent.precision(.fractionLength(0))), systemImage: "drop.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(day.precipitationChance >= 0.3 ? VaneTheme.blue : VaneTheme.muted)
                        .frame(width: 54, alignment: .leading)
                    Spacer(minLength: 1)
                    Text("L \(day.low.degrees)")
                        .foregroundStyle(VaneTheme.muted)
                        .frame(width: 42, alignment: .trailing)
                    Text("H \(day.high.degrees)")
                        .fontWeight(.semibold)
                        .frame(width: 44, alignment: .trailing)
                }
                .font(.caption)
                .padding(.vertical, 11)
                if index < snapshot.daily.count - 1 { Divider().overlay(VaneTheme.hairline) }
            }
        }
        .foregroundStyle(VaneTheme.ink)
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var conditions: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionKicker(title: "The details")
            GlassCard(radius: 28) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 0), GridItem(.flexible())], spacing: 0) {
                    ConditionMetric(title: "Rain chance", value: snapshot.current.precipitationChance.formatted(.percent.precision(.fractionLength(0))), symbol: "drop.fill", accent: VaneTheme.blue)
                    ConditionMetric(title: "Wind", value: "\(snapshot.current.windSpeed) mph \(snapshot.current.windDirection)", symbol: "wind", accent: VaneTheme.cyan)
                    ConditionMetric(title: "Humidity", value: snapshot.current.humidity.formatted(.percent.precision(.fractionLength(0))), symbol: "humidity.fill", accent: VaneTheme.cyan)
                    ConditionMetric(title: "UV index", value: "\(snapshot.current.uvIndex)", symbol: "sun.max.fill", accent: VaneTheme.warm)
                    ConditionMetric(title: "Visibility", value: "\(snapshot.current.visibility) mi", symbol: "eye.fill", accent: VaneTheme.blue)
                    ConditionMetric(title: "Pressure", value: "\(snapshot.current.pressure) hPa", symbol: "gauge.with.dots.needle.50percent", accent: VaneTheme.warm)
                }
            }
        }
    }

    private var bestWindowText: String {
        let profile = profiles.first
        guard let best = GuidanceEngine.bestFitHour(
            in: snapshot.hourly,
            temperaturePreference: profile?.temperaturePreference ?? 0,
            windSensitivity: profile?.windSensitivity ?? 0.5,
            humiditySensitivity: profile?.humiditySensitivity ?? 0.5,
            usesFeelsLikeTemperature: profile?.usesFeelsLikeTemperature ?? true,
            samples: guidanceSamples
        ) else {
            return "Today’s daytime window has ended"
        }
        return best.date.formatted(.dateTime.hour()) + " looks most comfortable"
    }

    private func daylineColor(for hour: HourlyConditions) -> Color {
        let distance = hour.temperature - 71
        if distance <= -5 { return VaneTheme.blue }
        if distance >= 6 { return VaneTheme.warm }
        return VaneTheme.cyan
    }

    private func isCurrentHour(_ hour: HourlyConditions) -> Bool {
        abs(hour.date.timeIntervalSinceNow) < 1_800
    }

    private func shortLabel(for response: FeelResponse) -> String {
        switch response {
        case .tooCold: "Cold"
        case .comfortable: "Just right"
        case .tooWarm: "Warm"
        }
    }

    private func record(_ response: FeelResponse) {
        let current = snapshot.current
        modelContext.insert(
            WeatherCheckIn(
                temperature: Double(current.temperature),
                apparentTemperature: Double(current.apparentTemperature),
                humidity: current.humidity,
                windSpeed: Double(current.windSpeed),
                response: response
            )
        )
        withAnimation(.spring(duration: 0.4)) { didCheckIn = true }
    }
}

private struct ConditionMetric: View {
    let title: String
    let value: String
    let symbol: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: symbol).foregroundStyle(accent)
                Text(title).font(.caption).foregroundStyle(VaneTheme.muted)
            }
            Text(value)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
        .padding(.horizontal, 16)
        .overlay(alignment: .trailing) { Rectangle().fill(VaneTheme.hairline).frame(width: 1).padding(.vertical, 14) }
        .overlay(alignment: .bottom) { Rectangle().fill(VaneTheme.hairline).frame(height: 1).padding(.horizontal, 14) }
    }
}

private extension View {
    func weatherEntrance(appeared: Bool, delay: Double, reduceMotion: Bool) -> some View {
        opacity(appeared ? 1 : 0)
            .offset(y: reduceMotion || appeared ? 0 : 16)
            .animation(reduceMotion ? nil : .spring(duration: 0.62, bounce: 0.12).delay(delay), value: appeared)
    }
}
