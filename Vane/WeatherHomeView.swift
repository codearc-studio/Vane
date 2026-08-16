import SwiftData
import SwiftUI

struct WeatherHomeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \WeatherCheckIn.createdAt, order: .reverse) private var checkIns: [WeatherCheckIn]
    @Query private var profiles: [WeatherProfile]
    @AppStorage("temperatureUnit") private var temperatureUnitRaw = TemperatureUnitPreference.fahrenheit.rawValue
    @AppStorage("windUnit") private var windUnitRaw = WindUnitPreference.milesPerHour.rawValue
    @AppStorage("pressureUnit") private var pressureUnitRaw = PressureUnitPreference.hectopascals.rawValue
    @AppStorage("precipitationUnit") private var precipitationUnitRaw = PrecipitationUnitPreference.inches.rawValue
    @Bindable var store: WeatherStore
    @State private var showLocations = false
    @State private var showCheckIn = false
    @State private var checkInPresenceWarning: CheckInPresence?
    @State private var selectedDay: DailyConditions?
    @State private var selectedDetail: WeatherDetailKind?
    @State private var scrollSection: String?

    private var snapshot: ForecastSnapshot { store.snapshot }
    private var profile: WeatherProfile? { profiles.first }
    private var temperatureUnit: TemperatureUnitPreference { TemperatureUnitPreference(rawValue: temperatureUnitRaw) ?? .fahrenheit }
    private var windUnit: WindUnitPreference { WindUnitPreference(rawValue: windUnitRaw) ?? .milesPerHour }
    private var pressureUnit: PressureUnitPreference { PressureUnitPreference(rawValue: pressureUnitRaw) ?? .hectopascals }
    private var formatting: WeatherFormatting { WeatherFormatting(temperature: temperatureUnit, wind: windUnit, pressure: pressureUnit, precipitation: PrecipitationUnitPreference(rawValue: precipitationUnitRaw) ?? .inches, timeZone: snapshot.timeZone) }
    private var samples: [GuidanceSample] {
        checkIns.compactMap {
            guard let response = $0.feelResponse else { return nil }
            return GuidanceSample(date: $0.createdAt, apparentTemperature: profile?.usesFeelsLikeTemperature == false ? $0.temperature : $0.apparentTemperature, humidity: $0.humidity, windSpeed: $0.windSpeed, response: response, contexts: $0.contexts, cloudCover: $0.cloudCover ?? 0.5, isTravel: $0.isTravel)
        }
    }
    private var summary: SenseProfileSummary { GuidanceEngine.profileSummary(temperaturePreference: profile?.temperaturePreference ?? 0, windSensitivity: profile?.windSensitivity ?? 0.5, humiditySensitivity: profile?.humiditySensitivity ?? 0.5, samples: samples) }
    private var guidance: PersonalGuidance { PersonalGuidance(snapshot: snapshot, profile: profile, checkIns: checkIns) }
    private var shouldPrompt: Bool { GuidanceEngine.shouldPrompt(snapshot: snapshot, samples: samples, frequency: profile?.checkInFrequency ?? .recommended) }

    var body: some View {
        ZStack {
            AtmosphericBackground(condition: snapshot.isPlaceholder ? nil : snapshot.current)
            if snapshot.isPlaceholder { emptyState } else { forecast }
        }
        .foregroundStyle(VaneTheme.ink)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showLocations) { LocationsView(store: store) }
        .sheet(isPresented: $showCheckIn) { CheckInView(snapshot: snapshot) }
        .confirmationDialog(checkInWarningTitle, isPresented: Binding(get: { checkInPresenceWarning != nil }, set: { if !$0 { checkInPresenceWarning = nil } }), titleVisibility: .visible) {
            Button("I’m here — continue") { checkInPresenceWarning = nil; showCheckIn = true }
            Button("Cancel", role: .cancel) { checkInPresenceWarning = nil }
        } message: { Text(checkInWarningMessage) }
        .navigationDestination(item: $selectedDay) { day in DayDetailView(day: day, snapshot: snapshot, profile: profile, samples: samples) }
        .navigationDestination(item: $selectedDetail) { detail in WeatherDetailView(kind: detail, snapshot: snapshot, formatting: formatting) }
    }

    private var forecast: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                header
                if !snapshot.alerts.isEmpty { alertBanner }
                weatherHero
                stateNotice
                personalRead
                if shouldPrompt { checkInPrompt }
                if bestFitHour != nil { bestFitToday }
                hourlyForecast
                dailyForecast.id("week")
                details.id("conditions")
                attribution
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? 210 : 110)
            .containerRelativeFrame(.horizontal)
        }
        .scrollIndicators(.hidden)
        .scrollPosition(id: $scrollSection, anchor: .top)
        .refreshable { await store.refreshSelectedSource() }
        .task {
            if ProcessInfo.processInfo.environment["VANE_SCREENSHOT_CHECKIN"] == "1" { try? await Task.sleep(for: .milliseconds(250)); showCheckIn = true }
            if ProcessInfo.processInfo.environment["VANE_SCREENSHOT_LOCATIONS"] == "1" { try? await Task.sleep(for: .milliseconds(250)); showLocations = true }
            if ProcessInfo.processInfo.environment["VANE_SCREENSHOT_DAY_DETAIL"] == "1" { try? await Task.sleep(for: .milliseconds(250)); selectedDay = snapshot.daily.dropFirst().first ?? snapshot.daily.first }
            if let detail = ProcessInfo.processInfo.environment["VANE_SCREENSHOT_DETAIL"].flatMap(WeatherDetailKind.init(rawValue:)) { try? await Task.sleep(for: .milliseconds(250)); selectedDetail = detail }
            guard let target = ProcessInfo.processInfo.environment["VANE_SCREENSHOT_SECTION"] else { return }
            try? await Task.sleep(for: .milliseconds(250)); scrollSection = target
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: store.isLoading ? "cloud.sun.fill" : "location.magnifyingglass").font(.system(size: 54)).foregroundStyle(VaneTheme.blue).symbolRenderingMode(.hierarchical)
            VStack(spacing: 8) {
                Text(store.isLoading ? "Loading weather" : "Choose a location").font(.largeTitle.bold())
                Text(store.errorMessage ?? "Use your location or search for a place to see a real forecast.").foregroundStyle(VaneTheme.muted).multilineTextAlignment(.center)
            }
            if !store.isLoading {
                Button { showLocations = true } label: { Label("Choose a Location", systemImage: "map.fill").font(.headline).frame(maxWidth: .infinity, minHeight: 54) }.vaneLiquidGlassButton(prominent: true)
                if store.authorizationStatus == .denied || store.authorizationStatus == .restricted { Button("Open iPhone Settings") { store.openLocationSettings() }.frame(minHeight: 44) }
            }
            Spacer()
        }.padding(28)
    }

    private var header: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) { brand; locationButton; if store.isLoading { updatingStatus } }
            } else {
                VStack(spacing: 7) {
                    HStack { brand; Spacer(); locationButton }
                    if store.isLoading { updatingStatus }
                }
            }
        }
    }

    private var brand: some View {
        HStack(spacing: 8) { VaneMark(size: 27); Text("Vane").font(.title3.bold()) }
            .accessibilityElement(children: .combine)
    }

    private var updatingStatus: some View {
        HStack(spacing: 7) {
            ProgressView().controlSize(.mini)
            Text("Refreshing \(snapshot.locationName)").font(.caption.weight(.medium))
            Spacer()
        }
        .foregroundStyle(VaneTheme.muted)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var locationButton: some View {
        Button { showLocations = true } label: {
            HStack(spacing: 6) { Image(systemName: store.isUsingCurrentLocation ? "location.fill" : "mappin"); Text(snapshot.locationName).lineLimit(1).minimumScaleFactor(0.75); Image(systemName: "chevron.down").font(.caption2.bold()) }
                .font(.subheadline.weight(.semibold)).padding(.horizontal, 13).frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, minHeight: 44)
        }.vaneLiquidGlassButton()
    }

    private var alertBanner: some View {
        NavigationLink { WeatherAlertsView(alerts: snapshot.alerts) } label: {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.title2)
                VStack(alignment: .leading, spacing: 2) { Text("Official weather alert").font(.headline); Text(snapshot.alerts[0].summary).font(.caption).lineLimit(2) }
                Spacer(); Image(systemName: "chevron.right").font(.caption.bold())
            }.padding(16).foregroundStyle(VaneTheme.ink)
        }
        .buttonStyle(.plain)
        .weatherLiquidGlass(radius: 24, interactive: true)
    }

    private var weatherHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    temperatureText
                    if guidance.isPersonalized || guidance.isEstimate { Text(guidance.headline).font(.title3.bold()).foregroundStyle(VaneTheme.blue) }
                    Label(snapshot.current.condition, systemImage: snapshot.current.symbolName).font(.title2.bold())
                    Text("Feels Like \(degrees(snapshot.current.apparentTemperature))  ·  H \(snapshot.daily.first.map { degrees($0.high) } ?? "—")  L \(snapshot.daily.first.map { degrees($0.low) } ?? "—")")
                        .font(.subheadline.weight(.medium)).foregroundStyle(VaneTheme.muted)
                }
            } else {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        temperatureText
                        if guidance.isPersonalized || guidance.isEstimate { Text(guidance.headline).font(.title3.bold()).foregroundStyle(VaneTheme.blue) }
                        Text(snapshot.current.condition).font(.title2.bold())
                        Text("Feels Like \(degrees(snapshot.current.apparentTemperature))  ·  H \(snapshot.daily.first.map { degrees($0.high) } ?? "—")  L \(snapshot.daily.first.map { degrees($0.low) } ?? "—")")
                            .font(.subheadline.weight(.medium)).foregroundStyle(VaneTheme.muted)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: snapshot.current.symbolName).symbolRenderingMode(.multicolor).font(.system(size: 58)).padding(.bottom, 18).accessibilityHidden(true)
                }
            }
            HStack(spacing: 6) {
                Text(store.attribution?.serviceName ?? "Apple Weather")
                Text("·")
                Text("Updated \(formatting.shortTime(snapshot.updatedAt))")
                if let accuracy = snapshot.locationAccuracy { Text("·"); Text(accuracy < 1_000 ? "within \(Int(accuracy.rounded())) m" : "approximate location") }
            }.font(.caption2).foregroundStyle(VaneTheme.muted)
        }.padding(.top, 18).padding(.bottom, 8).accessibilityElement(children: .combine)
    }

    private var temperatureText: some View {
        Text(degrees(snapshot.current.temperature))
            .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 76 : 104, weight: .thin, design: .rounded))
            .tracking(dynamicTypeSize.isAccessibilitySize ? -2 : -6)
            .lineLimit(1).minimumScaleFactor(0.72).contentTransition(.numericText())
    }

    @ViewBuilder private var stateNotice: some View {
        switch store.displayState {
        case .stale(let message), .unavailable(let message):
            HStack(spacing: 11) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .foregroundStyle(VaneTheme.blue)
                Text(message)
                    .font(.caption)
                Spacer()
                Button("Retry") {
                    Task { await store.refreshSelectedSource() }
                }
                .font(.caption.bold())
            }
            .padding(14)
            .weatherLiquidGlass(radius: 18)
        default: EmptyView()
        }
    }

    private var personalRead: some View {
        VStack(alignment: .leading, spacing: 13) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    SectionKicker(title: "Your Sense")
                    Text(guidance.calibrationLabel)
                        .font(.caption.bold())
                        .foregroundStyle(VaneTheme.muted)
                }
            } else {
                HStack {
                    SectionKicker(title: "Your Sense")
                    Spacer()
                    Text(guidance.calibrationLabel)
                        .font(.caption.bold())
                        .foregroundStyle(VaneTheme.muted)
                }
            }

            Text(guidance.headline)
                .font(.title2.bold())

            Text(guidance.detail)
                .font(.subheadline)
                .foregroundStyle(VaneTheme.muted)

            if let action = guidance.action {
                Label(action.text, systemImage: action.symbol)
                    .font(.subheadline.bold())
                    .foregroundStyle(snapshot.alerts.isEmpty ? VaneTheme.blue : .red)
            }
        }
        .padding(20)
        .weatherLiquidGlass(radius: 28)
    }

    private var checkInPrompt: some View {
        Button { beginCheckIn() } label: {
            HStack { Image(systemName: "checkmark.bubble.fill").foregroundStyle(VaneTheme.blue); VStack(alignment: .leading) { Text("Check in now").font(.headline); Text("This weather would add useful context.").font(.caption).foregroundStyle(VaneTheme.muted) }; Spacer(); Image(systemName: "chevron.right").font(.caption.bold()) }
                .padding(.horizontal, 16).frame(minHeight: 64).foregroundStyle(VaneTheme.ink)
        }
        .buttonStyle(.plain)
        .weatherLiquidGlass(radius: 22, interactive: true)
    }

    private var bestFitToday: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack { VStack(alignment: .leading) { SectionKicker(title: "Best fit today"); Text(bestWindowText).font(.title3.bold()) }; Spacer() }
            Text("Closest to your usual comfortable range").font(.caption).foregroundStyle(VaneTheme.muted)
            ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 0) { ForEach(GuidanceEngine.daytimeHours(in: snapshot.hourly).prefix(12)) { hour in hourCell(hour, personalized: true) } } }
        }
        .padding(20)
        .weatherLiquidGlass(radius: 28)
    }

    private var hourlyForecast: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack { SectionKicker(title: "Hourly forecast"); Spacer(); Text("Next 24 hours").font(.caption).foregroundStyle(VaneTheme.muted) }
            ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 0) { ForEach(snapshot.hourly.prefix(24)) { hour in hourCell(hour, personalized: false) } } }
        }
        .padding(20)
        .weatherLiquidGlass(radius: 28)
    }

    private func hourCell(_ hour: HourlyConditions, personalized: Bool) -> some View {
        VStack(spacing: 8) {
            Text(abs(hour.date.timeIntervalSinceNow) < 1_800 ? "Now" : formatting.hour(hour.date)).font(.caption2.weight(.semibold)).foregroundStyle(VaneTheme.muted)
            Image(systemName: hour.symbolName).symbolRenderingMode(.multicolor).frame(height: 24)
            if personalized { Capsule().fill(comfortColor(hour)).frame(width: 38, height: 5) }
            Text(degrees(hour.temperature)).font(.body.bold())
            if hour.precipitationChance >= 0.2 { Text(hour.precipitationChance.formatted(.percent.precision(.fractionLength(0)))).font(.caption2.bold()).foregroundStyle(VaneTheme.blue) }
            if hour.windSpeed >= 15 { Label("\(windUnit.value(hour.windSpeed))", systemImage: "wind").font(.caption2).foregroundStyle(VaneTheme.muted) }
        }.frame(width: 66).accessibilityElement(children: .ignore).accessibilityLabel("\(formatting.hour(hour.date)), \(formatting.degrees(hour.temperature, includeUnit: true)), \(hour.condition), \(hour.precipitationChance.formatted(.percent.precision(.fractionLength(0)))) chance of precipitation")
    }

    private var dailyForecast: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionKicker(title: "The week ahead")
            ForEach(Array(snapshot.daily.enumerated()), id: \.element.id) { index, day in
                let isToday = snapshot.calendar.isDate(day.date, inSameDayAs: .now)
                Button { selectedDay = day } label: {
                    HStack(spacing: 10) {
                        Text(isToday ? "Today" : formatting.weekday(day.date))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .frame(width: 90, alignment: .leading)
                        Image(systemName: day.symbolName).symbolRenderingMode(.multicolor).frame(width: 24)
                        Text(day.precipitationChance >= 0.2 ? day.precipitationChance.formatted(.percent.precision(.fractionLength(0))) : "").font(.caption2.bold()).foregroundStyle(VaneTheme.blue).frame(width: 42)
                        Spacer(); Text("L \(degrees(day.low))").foregroundStyle(VaneTheme.muted); Text("H \(degrees(day.high))").fontWeight(.semibold); Image(systemName: "chevron.right").font(.caption2).foregroundStyle(VaneTheme.muted)
                    }.font(.caption).padding(.vertical, 12).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("\(isToday ? "Today" : formatting.weekday(day.date)), \(day.condition), low \(formatting.degrees(day.low, includeUnit: true)), high \(formatting.degrees(day.high, includeUnit: true)), \(day.precipitationChance.formatted(.percent.precision(.fractionLength(0)))) chance of precipitation")
                if index < snapshot.daily.count - 1 { Divider().overlay(VaneTheme.hairline) }
            }
        }
        .padding(20)
        .weatherLiquidGlass(radius: 28)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionKicker(title: "Weather details")
            Button { selectedDetail = .map } label: {
                detailRow("Conditions map", "Temperature, precipitation and AQI at this location", "map.fill")
            }
            .buttonStyle(.plain)
            .weatherLiquidGlass(radius: 24, interactive: true)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                detailButton(.wind, "Wind", "\(windUnit.value(snapshot.current.windSpeed)) \(windUnit.title) \(snapshot.current.windDirection)", "wind")
                if let air = snapshot.airQuality { detailButton(.airQuality, "Air quality", "\(air.index) · \(air.category)", "aqi.medium") }
                detailButton(.sun, "Sun", snapshot.daily.first?.sunset.map { "Sunset \(formatting.shortTime($0))" } ?? "Times unavailable", "sun.max.fill")
                detailButton(.moon, "Moon", snapshot.daily.first?.moonPhase.isEmpty == false ? snapshot.daily.first!.moonPhase : "Times unavailable", "moon.stars.fill")
                detailButton(.visibility, "Visibility", formatting.visibility(snapshot.current.visibility), "eye.fill")
                detailButton(.pressure, "Pressure", pressureUnit.formatted(snapshot.current.pressure), "gauge.with.dots.needle.50percent")
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 0) {
                metric("Rain chance", snapshot.current.precipitationChance.formatted(.percent.precision(.fractionLength(0))), "drop.fill")
                metric("Humidity", snapshot.current.humidity.formatted(.percent.precision(.fractionLength(0))), "humidity.fill")
                metric("Dew point", degrees(snapshot.current.dewPoint), "thermometer.medium")
                metric("UV index", "\(snapshot.current.uvIndex)", "sun.max.fill")
            }
            .padding(8)
            .weatherLiquidGlass(radius: 28)
        }
    }

    private func detailButton(_ kind: WeatherDetailKind, _ title: String, _ value: String, _ symbol: String) -> some View {
        Button { selectedDetail = kind } label: {
            VStack(alignment: .leading, spacing: 9) {
                Label(title, systemImage: symbol).font(.caption).foregroundStyle(VaneTheme.muted)
                Text(value).font(.headline).minimumScaleFactor(0.7).lineLimit(2)
                Image(systemName: "arrow.up.right").font(.caption.bold()).foregroundStyle(VaneTheme.blue)
            }.frame(maxWidth: .infinity, minHeight: 112, alignment: .leading).padding(14).foregroundStyle(VaneTheme.ink)
        }
        .buttonStyle(.plain)
        .weatherLiquidGlass(radius: 24, interactive: true)
    }

    private func detailRow(_ title: String, _ value: String, _ symbol: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol).font(.title2).foregroundStyle(VaneTheme.blue).frame(width: 34)
            VStack(alignment: .leading, spacing: 2) { Text(title).font(.headline); Text(value).font(.caption).foregroundStyle(VaneTheme.muted).multilineTextAlignment(.leading) }
            Spacer(); Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(VaneTheme.muted)
        }.padding(16).foregroundStyle(VaneTheme.ink)
    }

    private func metric(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 7) { Label(title, systemImage: symbol).font(.caption).foregroundStyle(VaneTheme.muted); Text(value).font(.headline).minimumScaleFactor(0.72) }
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading).padding(.horizontal, 12)
    }

    @ViewBuilder private var attribution: some View {
        if let attribution = store.attribution {
            Link(destination: attribution.legalPageURL) {
                AsyncImage(url: colorScheme == .dark ? attribution.combinedMarkDarkURL : attribution.combinedMarkLightURL) { image in image.resizable().scaledToFit() } placeholder: { Text("Weather data by \(attribution.serviceName)").font(.caption2) }
                    .frame(maxWidth: 150, maxHeight: 36).foregroundStyle(VaneTheme.muted)
            }.accessibilityLabel("Weather data provided by \(attribution.serviceName). Opens legal attribution.")
        }
    }

    private func beginCheckIn() {
        let presence = store.checkInPresence(for: snapshot)
        if presence == .verified { showCheckIn = true } else { checkInPresenceWarning = presence }
    }
    private var checkInWarningTitle: String {
        if case .away = checkInPresenceWarning { return "Are you in \(snapshot.locationName)?" }
        return "Can’t verify this location"
    }
    private var checkInWarningMessage: String {
        switch checkInPresenceWarning {
        case .away(let miles): "Your iPhone appears to be about \(miles) miles away. Check-ins should describe weather you are actually experiencing, but you can continue if the location reading is wrong."
        case .unavailable: "Location access is off or unavailable. Continue only if you are currently experiencing the weather in \(snapshot.locationName)."
        default: ""
        }
    }
    private var bestFitHour: HourlyConditions? {
        GuidanceEngine.bestFitHour(in: snapshot.hourly, temperaturePreference: profile?.temperaturePreference ?? 0, windSensitivity: profile?.windSensitivity ?? 0.5, humiditySensitivity: profile?.humiditySensitivity ?? 0.5, usesFeelsLikeTemperature: profile?.usesFeelsLikeTemperature ?? true, samples: samples, calendar: snapshot.calendar)
    }
    private var bestWindowText: String {
        guard let best = bestFitHour else { return "No familiar daylight window remains" }
        let neighbors = snapshot.hourly.filter { abs($0.date.timeIntervalSince(best.date)) <= 3_600 && abs($0.apparentTemperature - best.apparentTemperature) <= 3 && $0.isDaylight }
        if let first = neighbors.first, let last = neighbors.last, first.id != last.id { return "\(formatting.hour(first.date))–\(formatting.hour(last.date))" }
        return "Around \(formatting.hour(best.date))"
    }
    private func comfortColor(_ hour: HourlyConditions) -> Color {
        let fit = GuidanceEngine.fitFamiliarity(hour: hour, summary: summary, windSensitivity: profile?.windSensitivity ?? 0.5, humiditySensitivity: profile?.humiditySensitivity ?? 0.5, usesFeelsLikeTemperature: profile?.usesFeelsLikeTemperature ?? true)
        return fit > 0.72 ? VaneTheme.cyan : fit > 0.4 ? VaneTheme.warm : VaneTheme.blue
    }
    private func degrees(_ fahrenheit: Int) -> String { formatting.degrees(fahrenheit) }
}


private struct WeatherLiquidGlassModifier: ViewModifier {
    let radius: CGFloat
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    interactive ? .regular.interactive() : .regular,
                    in: RoundedRectangle(cornerRadius: radius, style: .continuous)
                )
        } else {
            content
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: radius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(VaneTheme.hairline, lineWidth: 1)
                }
        }
    }
}

private extension View {
    func weatherLiquidGlass(
        radius: CGFloat = 28,
        interactive: Bool = false
    ) -> some View {
        modifier(
            WeatherLiquidGlassModifier(
                radius: radius,
                interactive: interactive
            )
        )
    }
}
