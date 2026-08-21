import SwiftUI

enum WeatherDetailKind: String, Identifiable, Hashable {
    case wind, moon, sun, visibility, pressure
    var id: String { rawValue }
    var title: String {
        switch self {
        case .wind: "Wind"
        case .moon: "Moon"
        case .sun: "Sun & Light"
        case .visibility: "Visibility"
        case .pressure: "Pressure"
        }
    }
}

struct WeatherDetailView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let kind: WeatherDetailKind
    let snapshot: ForecastSnapshot
    let formatting: WeatherFormatting

    var body: some View {
        ZStack {
            AtmosphericBackground(condition: snapshot.current)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    detailHeader
                    content
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? 130 : 34)
                .containerRelativeFrame(.horizontal)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            SectionKicker(title: snapshot.locationName)
            Text(kind.title).font(.largeTitle.bold())
            Text("Updated \(formatting.shortTime(snapshot.updatedAt))")
                .font(.caption)
                .foregroundStyle(VaneTheme.muted)
        }
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .wind: wind
        case .moon: moon
        case .sun: sun
        case .visibility: visibility
        case .pressure: pressure
        }
    }

    private var wind: some View {
        VStack(spacing: 14) {
            ConditionHeroCard(
                symbol: "wind",
                value: formatting.windSpeed(snapshot.current.windSpeed),
                title: windTitle,
                detail: windDescription
            ) {
                DirectionDial(direction: snapshot.current.windDirection, degrees: snapshot.current.windDirectionDegrees)
            }
            detailCard {
                detailLine("Sustained wind", formatting.windSpeed(snapshot.current.windSpeed), symbol: "wind")
                Divider()
                detailLine("Gusts", formatting.windSpeed(snapshot.current.windGust), symbol: "wind.circle.fill")
                Divider()
                detailLine("Direction", "\(snapshot.current.windDirection) · \(Int(snapshot.current.windDirectionDegrees.rounded()))°", symbol: "location.north.fill")
            }
        }
    }

    private var moon: some View {
        let day = snapshot.daily.first
        return VStack(spacing: 14) {
            ConditionHeroCard(
                symbol: moonSymbol(day?.moonPhase ?? ""),
                value: day?.moonPhase.isEmpty == false ? day!.moonPhase : "Unavailable",
                title: snapshot.current.isDaylight ? "Tonight’s moon" : "Night sky",
                detail: snapshot.current.isDaylight ? "Moonrise and moonset are shown in \(snapshot.locationName)’s local time." : "It is currently nighttime in \(snapshot.locationName)."
            ) { EmptyView() }
            detailCard {
                detailLine("Moonrise", day?.moonrise.map(formatting.shortTime) ?? "Not during this day", symbol: "moonrise.fill")
                Divider()
                detailLine("Moonset", day?.moonset.map(formatting.shortTime) ?? "Not during this day", symbol: "moonset.fill")
                Text("Moonrise and moonset can fall outside a calendar day, so one may not occur today.")
                    .font(.caption)
                    .foregroundStyle(VaneTheme.muted)
            }
        }
    }

    private var sun: some View {
        let day = snapshot.daily.first
        return VStack(spacing: 14) {
            ConditionHeroCard(
                symbol: snapshot.current.isDaylight ? "sun.max.fill" : "moon.stars.fill",
                value: sunHeroValue,
                title: snapshot.current.isDaylight ? "Daylight now" : "Nighttime now",
                detail: sunHeroDetail
            ) {
                DaylightProgress(day: day, now: .now, formatting: formatting)
            }
            detailCard {
                detailLine("First light", day?.civilDawn.map(formatting.shortTime) ?? "—", symbol: "sun.horizon.fill")
                Divider()
                detailLine("Sunrise", day?.sunrise.map(formatting.shortTime) ?? "—", symbol: "sunrise.fill")
                Divider()
                detailLine("Solar noon", day?.solarNoon.map(formatting.shortTime) ?? "—", symbol: "sun.max.fill")
                Divider()
                detailLine("Sunset", day?.sunset.map(formatting.shortTime) ?? "—", symbol: "sunset.fill")
                Divider()
                detailLine("Last light", day?.civilDusk.map(formatting.shortTime) ?? "—", symbol: "sun.horizon.fill")
                if snapshot.current.isDaylight {
                    Divider()
                    detailLine("UV index", "\(snapshot.current.uvIndex)", symbol: "sun.max.trianglebadge.exclamationmark.fill")
                }
            }
        }
    }

    private var visibility: some View {
        VStack(spacing: 14) {
            ConditionHeroCard(
                symbol: visibilitySymbol,
                value: formatting.visibility(snapshot.current.visibility),
                title: visibilityDescription,
                detail: "Visibility is the estimated horizontal distance at which prominent objects can be seen."
            ) { EmptyView() }
            detailCard {
                detailLine("Current range", formatting.visibility(snapshot.current.visibility), symbol: "eye.fill")
                Divider()
                detailLine("Weather", snapshot.current.condition, symbol: snapshot.current.symbolName)
                Text("Fog, haze, precipitation and smoke can reduce how far you can see.")
                    .font(.caption)
                    .foregroundStyle(VaneTheme.muted)
            }
        }
    }

    private var pressure: some View {
        VStack(spacing: 14) {
            ConditionHeroCard(
                symbol: pressureTrendSymbol,
                value: formatting.pressureValue(snapshot.current.pressure),
                title: "\(snapshot.current.pressureTrend) pressure",
                detail: "Sea-level pressure is normalized so readings from different elevations can be compared."
            ) {
                PressureScale(pressure: snapshot.current.pressure)
            }
            detailCard {
                detailLine("Trend", snapshot.current.pressureTrend, symbol: pressureTrendSymbol)
                Divider()
                detailLine("Reading", formatting.pressureValue(snapshot.current.pressure), symbol: "gauge.with.dots.needle.50percent")
                Text("The trend is often more useful than one number: falling pressure can accompany an approaching system, while rising pressure often follows one.")
                    .font(.caption)
                    .foregroundStyle(VaneTheme.muted)
            }
        }
    }

    private func detailCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) { content() }
                .padding(20)
        }
    }

    private func detailLine(_ title: String, _ value: String, symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(VaneTheme.blue).frame(width: 24)
            Text(title).foregroundStyle(VaneTheme.muted)
            Spacer()
            Text(value).fontWeight(.semibold).multilineTextAlignment(.trailing)
        }
    }

    private var windTitle: String {
        switch snapshot.current.windSpeed {
        case ..<5: "Light air"
        case ..<15: "Noticeable breeze"
        case ..<25: "Windy"
        default: "Strong wind"
        }
    }
    private var windDescription: String {
        snapshot.current.windGust > snapshot.current.windSpeed + 5
            ? "Gusts reach \(formatting.windSpeed(snapshot.current.windGust)), so short bursts may feel stronger than the sustained reading."
            : "Sustained wind and gusts are close, so conditions should feel fairly steady."
    }
    private var visibilityDescription: String {
        snapshot.current.visibility >= 10 ? "Very clear" : snapshot.current.visibility >= 6 ? "Generally clear" : snapshot.current.visibility >= 3 ? "Reduced visibility" : "Poor visibility"
    }
    private var visibilitySymbol: String {
        snapshot.current.visibility >= 6 ? "eye.fill" : "cloud.fog.fill"
    }
    private var pressureTrendSymbol: String {
        snapshot.current.pressureTrend.lowercased().contains("fall") ? "arrow.down.right" : snapshot.current.pressureTrend.lowercased().contains("ris") ? "arrow.up.right" : "arrow.right"
    }
    private var sunHeroValue: String {
        if snapshot.current.isDaylight,
           let sunset = snapshot.daily.compactMap(\.sunset).first(where: { $0 > .now }) {
            return "Sunset \(formatting.shortTime(sunset))"
        }
        if let sunrise = snapshot.daily.compactMap(\.sunrise).first(where: { $0 > .now }) {
            return "Sunrise \(formatting.shortTime(sunrise))"
        }
        return "Times unavailable"
    }
    private var sunHeroDetail: String {
        snapshot.current.isDaylight
            ? "The sun is above the horizon in \(snapshot.locationName)."
            : "The sun is below the horizon. UV is hidden until daylight returns."
    }
    private func moonSymbol(_ phase: String) -> String {
        phase.lowercased().contains("full") ? "moonphase.full.moon" : phase.lowercased().contains("new") ? "moonphase.new.moon" : phase.lowercased().contains("waning") ? "moonphase.waning.crescent" : "moonphase.waxing.crescent"
    }
}

private struct ConditionHeroCard<Accessory: View>: View {
    let symbol: String
    let value: String
    let title: String
    let detail: String
    let accessory: Accessory

    init(symbol: String, value: String, title: String, detail: String, @ViewBuilder accessory: () -> Accessory) {
        self.symbol = symbol
        self.value = value
        self.title = title
        self.detail = detail
        self.accessory = accessory()
    }

    var body: some View {
        GlassCard(radius: 32) {
            VStack(spacing: 16) {
                Image(systemName: symbol)
                    .font(.system(size: 60, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(VaneTheme.blue)
                VStack(spacing: 6) {
                    Text(value)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.72)
                    Text(title).font(.headline)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(VaneTheme.muted)
                        .multilineTextAlignment(.center)
                }
                accessory
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
    }
}

private struct DirectionDial: View {
    let direction: String
    let degrees: Double

    var body: some View {
        ZStack {
            Circle().stroke(VaneTheme.blue.opacity(0.16), lineWidth: 8)
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(VaneTheme.muted.opacity(0.45))
                    .frame(width: 2, height: 8)
                    .offset(y: -38)
                    .rotationEffect(.degrees(Double(index) * 90))
            }
            Image(systemName: "location.north.fill")
                .font(.system(size: 28))
                .foregroundStyle(VaneTheme.blue)
                .rotationEffect(.degrees(degrees))
            Text(direction)
                .font(.caption.bold())
                .offset(y: 27)
        }
        .frame(width: 86, height: 86)
        .accessibilityLabel("Wind from \(direction)")
    }
}

private struct DaylightProgress: View {
    let day: DailyConditions?
    let now: Date
    let formatting: WeatherFormatting

    private var progress: Double {
        guard let sunrise = day?.sunrise, let sunset = day?.sunset, sunset > sunrise else { return 0 }
        return min(1, max(0, now.timeIntervalSince(sunrise) / sunset.timeIntervalSince(sunrise)))
    }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(VaneTheme.blue.opacity(0.14)).frame(height: 8)
                    Capsule().fill(VaneTheme.blue).frame(width: max(8, proxy.size.width * progress), height: 8)
                }
            }
            .frame(height: 8)
            HStack {
                Text(day?.sunrise.map(formatting.shortTime) ?? "—")
                Spacer()
                Text(day?.sunset.map(formatting.shortTime) ?? "—")
            }
            .font(.caption2.bold())
            .foregroundStyle(VaneTheme.muted)
        }
        .accessibilityLabel("Daylight from \(day?.sunrise.map(formatting.shortTime) ?? "unknown") to \(day?.sunset.map(formatting.shortTime) ?? "unknown")")
    }
}

private struct PressureScale: View {
    let pressure: Int
    private var progress: Double { min(1, max(0, Double(pressure - 970) / 80)) }

    var body: some View {
        VStack(spacing: 7) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    LinearGradient(colors: [VaneTheme.cyan, VaneTheme.blue, VaneTheme.warm], startPoint: .leading, endPoint: .trailing)
                        .frame(height: 9)
                        .clipShape(Capsule())
                    Circle()
                        .fill(.white)
                        .stroke(VaneTheme.blue, lineWidth: 3)
                        .frame(width: 18, height: 18)
                        .offset(x: min(proxy.size.width - 18, max(0, proxy.size.width * progress - 9)))
                }
            }
            .frame(height: 18)
            HStack { Text("Low"); Spacer(); Text("Typical"); Spacer(); Text("High") }
                .font(.caption2)
                .foregroundStyle(VaneTheme.muted)
        }
    }
}

struct WeatherAlertsView: View {
    let alerts: [WeatherAlertSnapshot]
    let locationName: String
    let updatedAt: Date
    let formatting: WeatherFormatting

    private var orderedAlerts: [WeatherAlertSnapshot] { alerts.sorted(by: WeatherAlertSnapshot.priorityOrder) }
    private var activeCount: Int { alerts.filter(\.isActive).count }

    var body: some View {
        ZStack {
            AtmosphericBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    alertStatusHeader

                    if orderedAlerts.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 42))
                                .foregroundStyle(VaneTheme.blue)
                            Text("No current alerts")
                                .font(.title2.bold())
                            Text("The latest Apple Weather refresh did not return an official alert for \(locationName).")
                                .font(.subheadline)
                                .foregroundStyle(VaneTheme.muted)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(30)
                        .weatherLiquidGlass(radius: 28)
                    } else {
                        ForEach(orderedAlerts) { alert in
                            NavigationLink {
                                WeatherAlertDetailView(alert: alert, locationName: locationName, formatting: formatting)
                            } label: {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Label(alert.isActive ? alert.severityLevel.title : "Expired", systemImage: alert.severityLevel.symbolName)
                                            .font(.caption.bold())
                                            .foregroundStyle(alert.isActive ? alert.severityLevel.tint : VaneTheme.muted)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption.bold())
                                            .foregroundStyle(VaneTheme.muted)
                                    }
                                    Text(alert.summary)
                                        .font(.title3.bold())
                                        .multilineTextAlignment(.leading)
                                    if let region = alert.region {
                                        Label(region, systemImage: "mappin.and.ellipse")
                                            .font(.subheadline)
                                            .foregroundStyle(VaneTheme.muted)
                                    }
                                    HStack(spacing: 12) {
                                        if let expiresAt = alert.expiresAt {
                                            Label(alert.isActive ? "Until \(formatting.shortDateTime(expiresAt))" : "Ended \(formatting.shortDateTime(expiresAt))", systemImage: "clock")
                                        }
                                        Text(alert.source)
                                            .lineLimit(1)
                                    }
                                    .font(.caption)
                                    .foregroundStyle(VaneTheme.muted)
                                }
                                .padding(20)
                                .foregroundStyle(VaneTheme.ink)
                                .background(alert.severityLevel.tint.opacity(alert.isActive ? 0.07 : 0.025), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                                .weatherLiquidGlass(radius: 26, interactive: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text("Alert availability last checked with Apple Weather at \(formatting.shortTime(updatedAt)). Safety instructions and updates come directly from each issuing authority.")
                        .font(.caption)
                        .foregroundStyle(VaneTheme.muted)
                        .padding(.horizontal, 4)
                }
                .padding(18)
                .padding(.bottom, 34)
                .containerRelativeFrame(.horizontal)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Weather Alerts")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var alertStatusHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionKicker(title: "\(locationName) safety")
                    Text(activeCount == 0 ? "All clear right now" : activeCount == 1 ? "1 active official alert" : "\(activeCount) active official alerts")
                        .font(.title2.bold())
                }
                Spacer()
                Image(systemName: activeCount == 0 ? "checkmark.shield.fill" : orderedAlerts.first?.severityLevel.symbolName ?? "exclamationmark.triangle.fill")
                    .font(.title)
                    .foregroundStyle(activeCount == 0 ? VaneTheme.blue : orderedAlerts.first?.severityLevel.tint ?? VaneTheme.blue)
            }
            Text(activeCount == 0 ? "Vane will surface new alerts here after the forecast refreshes." : "Open an alert for timing, coverage, and the issuing authority’s official guidance.")
                .font(.subheadline)
                .foregroundStyle(VaneTheme.muted)
        }
        .padding(22)
        .weatherLiquidGlass(radius: 30)
    }
}

private struct WeatherAlertDetailView: View {
    let alert: WeatherAlertSnapshot
    let locationName: String
    let formatting: WeatherFormatting

    var body: some View {
        ZStack {
            AtmosphericBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 16) {
                        Label(alert.isActive ? "\(alert.severityLevel.title) alert" : "Expired alert", systemImage: alert.severityLevel.symbolName)
                            .font(.subheadline.bold())
                            .foregroundStyle(alert.isActive ? alert.severityLevel.tint : VaneTheme.muted)
                        Text(alert.summary)
                            .font(.largeTitle.bold())
                            .minimumScaleFactor(0.78)
                        Text(alert.isActive ? "An official alert applies to this forecast area. Review the issuer’s instructions before relying on your usual weather routine." : "This alert’s listed end time has passed. Open the official source to confirm its latest status.")
                            .font(.body)
                            .foregroundStyle(VaneTheme.muted)
                    }
                    .padding(22)
                    .background(alert.severityLevel.tint.opacity(alert.isActive ? 0.08 : 0.03), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .weatherLiquidGlass(radius: 30)

                    VStack(alignment: .leading, spacing: 0) {
                        alertFact("Area", value: alert.region ?? locationName, symbol: "mappin.and.ellipse")
                        Divider().overlay(VaneTheme.hairline)
                        alertFact("Issued by", value: alert.source, symbol: "building.columns.fill")
                        if let issuedAt = alert.issuedAt {
                            Divider().overlay(VaneTheme.hairline)
                            alertFact("Available since", value: formatting.shortDateTime(issuedAt), symbol: "calendar.badge.clock")
                        }
                        if let expiresAt = alert.expiresAt {
                            Divider().overlay(VaneTheme.hairline)
                            alertFact(alert.isActive ? "Listed until" : "Listed end", value: formatting.shortDateTime(expiresAt), symbol: "clock.fill")
                        }
                    }
                    .padding(.horizontal, 20)
                    .weatherLiquidGlass(radius: 28)

                    Link(destination: alert.detailsURL) {
                        Label("Open official alert", systemImage: "safari.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 54)
                    }
                    .vaneLiquidGlassButton(prominent: true)

                    ShareLink(item: alert.detailsURL) {
                        Label("Share official alert", systemImage: "square.and.arrow.up")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .vaneLiquidGlassButton()

                    Label("Vane summarizes the alert metadata supplied by Apple Weather. The issuing authority’s page is the source of truth for instructions and changes.", systemImage: "checkmark.shield.fill")
                        .font(.caption)
                        .foregroundStyle(VaneTheme.muted)
                        .padding(4)
                }
                .padding(18)
                .padding(.bottom, 34)
                .containerRelativeFrame(.horizontal)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Alert Details")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func alertFact(_ title: String, value: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(alert.severityLevel.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption).foregroundStyle(VaneTheme.muted)
                Text(value).font(.subheadline.weight(.semibold))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 15)
        .accessibilityElement(children: .combine)
    }
}
