import SwiftUI
import WidgetKit

nonisolated enum VaneWidgetKind: String, Sendable {
    case now
    case forecast
    case details
    case sun
    case sense
}

nonisolated enum VaneWidgetMetric: String, CaseIterable, Codable, Sendable {
    case automatic
    case precipitation
    case feelsLike
    case wind
    case humidity
    case uvIndex
}

struct VaneWidgetBackground: View {
    let snapshot: VaneWidgetSnapshot?

    private var colors: [Color] {
        guard let snapshot else {
            return [Color(red: 0.08, green: 0.25, blue: 0.48), Color(red: 0.11, green: 0.46, blue: 0.78)]
        }
        let symbol = snapshot.symbolName.lowercased()
        if !snapshot.isDaylight {
            return [Color(red: 0.015, green: 0.055, blue: 0.14), Color(red: 0.04, green: 0.17, blue: 0.34)]
        }
        if symbol.contains("thunder") || symbol.contains("rain") {
            return [Color(red: 0.12, green: 0.24, blue: 0.36), Color(red: 0.30, green: 0.48, blue: 0.62)]
        }
        if symbol.contains("snow") {
            return [Color(red: 0.38, green: 0.58, blue: 0.74), Color(red: 0.68, green: 0.82, blue: 0.92)]
        }
        if symbol.contains("cloud") {
            return [Color(red: 0.22, green: 0.46, blue: 0.68), Color(red: 0.50, green: 0.70, blue: 0.84)]
        }
        return [Color(red: 0.08, green: 0.42, blue: 0.83), Color(red: 0.25, green: 0.72, blue: 0.92)]
    }

    var body: some View {
        GeometryReader { _ in
            ZStack {
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()
                    .fill(.white.opacity(snapshot?.isDaylight == false ? 0.05 : 0.18))
                    .frame(width: 190, height: 190)
                    .blur(radius: 30)
                    .offset(x: -70, y: -85)
                Circle()
                    .fill(Color.cyan.opacity(0.16))
                    .frame(width: 220, height: 220)
                    .blur(radius: 50)
                    .offset(x: 105, y: 110)
            }
            .clipped()
        }
    }
}

struct VaneSenseWidgetBackground: View {
    let snapshot: VaneWidgetSnapshot?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.025, green: 0.08, blue: 0.20),
                        Color(red: 0.08, green: 0.30, blue: 0.58),
                        Color(red: 0.08, green: 0.52, blue: 0.64)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(.cyan.opacity(0.18))
                    .frame(width: geometry.size.width * 0.82)
                    .blur(radius: 42)
                    .offset(x: geometry.size.width * 0.43, y: geometry.size.height * 0.36)
                Circle()
                    .fill(.white.opacity(snapshot?.guidanceIsPersonalized == true ? 0.13 : 0.08))
                    .frame(width: geometry.size.width * 0.56)
                    .blur(radius: 30)
                    .offset(x: -geometry.size.width * 0.34, y: -geometry.size.height * 0.38)
            }
            .clipped()
        }
    }
}

struct VaneWidgetContentView: View {
    let family: WidgetFamily
    let kind: VaneWidgetKind
    let snapshot: VaneWidgetSnapshot?
    var metric: VaneWidgetMetric = .automatic
    var date: Date = .now

    var body: some View {
        Group {
            if let snapshot {
                switch family {
                case .accessoryInline:
                    inline(snapshot)
                case .accessoryCircular:
                    circular(snapshot)
                case .accessoryRectangular:
                    rectangular(snapshot)
                case .systemSmall:
                    small(snapshot)
                case .systemMedium:
                    medium(snapshot)
                case .systemLarge:
                    large(snapshot)
                case .systemExtraLarge:
                    extraLarge(snapshot)
                default:
                    small(snapshot)
                }
            } else {
                missingData
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func small(_ snapshot: VaneWidgetSnapshot) -> some View {
        switch kind {
        case .now: NowSmall(snapshot: snapshot)
        case .forecast: ForecastSmall(snapshot: snapshot)
        case .details: DetailsSmall(snapshot: snapshot, metric: resolvedMetric(snapshot))
        case .sun: SunSmall(snapshot: snapshot, date: date)
        case .sense: SenseSmall(snapshot: snapshot)
        }
    }

    @ViewBuilder
    private func medium(_ snapshot: VaneWidgetSnapshot) -> some View {
        switch kind {
        case .now: NowMedium(snapshot: snapshot, date: date)
        case .forecast: ForecastMedium(snapshot: snapshot)
        case .details: DetailsMedium(snapshot: snapshot, primaryMetric: resolvedMetric(snapshot))
        case .sun: SunMedium(snapshot: snapshot, date: date)
        case .sense: SenseMedium(snapshot: snapshot)
        }
    }

    @ViewBuilder
    private func large(_ snapshot: VaneWidgetSnapshot) -> some View {
        switch kind {
        case .forecast: ForecastLarge(snapshot: snapshot, date: date, dayLimit: 7)
        case .now: ForecastLarge(snapshot: snapshot, date: date, dayLimit: 5)
        case .details: DetailsLarge(snapshot: snapshot, primaryMetric: resolvedMetric(snapshot))
        case .sun: SunLarge(snapshot: snapshot, date: date)
        case .sense: SenseLarge(snapshot: snapshot)
        }
    }

    @ViewBuilder
    private func extraLarge(_ snapshot: VaneWidgetSnapshot) -> some View {
        switch kind {
        case .forecast, .now: ForecastExtraLarge(snapshot: snapshot, date: date)
        case .details: DetailsLarge(snapshot: snapshot, primaryMetric: resolvedMetric(snapshot))
        case .sun: SunLarge(snapshot: snapshot, date: date)
        case .sense: SenseLarge(snapshot: snapshot)
        }
    }

    @ViewBuilder
    private func inline(_ snapshot: VaneWidgetSnapshot) -> some View {
        switch kind {
        case .sun:
            if let sunset = snapshot.today?.sunset {
                Label("Vane · Sunset \(snapshot.shortTime(sunset))", systemImage: "sunset.fill")
            } else {
                Label("Vane · Sun times unavailable", systemImage: "sun.max")
            }
        case .details:
            let value = WidgetMetricValue(snapshot: snapshot, metric: resolvedMetric(snapshot))
            Label("Vane · \(value.title) \(value.value)", systemImage: value.symbol)
        case .sense:
            Label("Vane Sense · \(SenseWidgetPresentation(snapshot).headline)", systemImage: SenseWidgetPresentation(snapshot).symbol)
        default:
            Label("Vane · \(snapshot.temperatureText(snapshot.temperature)) · \(snapshot.condition)", systemImage: snapshot.symbolName)
        }
    }

    @ViewBuilder
    private func circular(_ snapshot: VaneWidgetSnapshot) -> some View {
        if kind == .sun {
            AccessorySunCircle(snapshot: snapshot, date: date)
        } else if kind == .details {
            let value = WidgetMetricValue(snapshot: snapshot, metric: resolvedMetric(snapshot))
            VStack(spacing: 0) {
                Text("VANE").font(.system(size: 6, weight: .bold)).tracking(0.45)
                Image(systemName: value.symbol).font(.caption)
                Text(value.shortValue).font(.system(size: 15, weight: .bold, design: .rounded)).minimumScaleFactor(0.7)
            }
            .widgetAccentable()
        } else if kind == .sense {
            let read = SenseWidgetPresentation(snapshot)
            VStack(spacing: -1) {
                Text("VANE").font(.system(size: 6, weight: .bold)).tracking(0.45)
                Image(systemName: read.symbol).font(.caption)
                Text(snapshot.temperatureText(snapshot.apparentTemperature))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .widgetAccentable()
            .accessibilityLabel("Sense, \(read.headline)")
        } else {
            VStack(spacing: -1) {
                Text("VANE").font(.system(size: 6, weight: .bold)).tracking(0.45)
                Image(systemName: snapshot.symbolName).font(.caption)
                Text(snapshot.temperatureText(snapshot.temperature))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
            }
            .widgetAccentable()
        }
    }

    @ViewBuilder
    private func rectangular(_ snapshot: VaneWidgetSnapshot) -> some View {
        if kind == .sun {
            AccessorySunRectangle(snapshot: snapshot, date: date)
        } else if kind == .details {
            let value = WidgetMetricValue(snapshot: snapshot, metric: resolvedMetric(snapshot))
            HStack(spacing: 8) {
                Image(systemName: value.symbol).font(.title3).widgetAccentable()
                VStack(alignment: .leading, spacing: 1) {
                    Text("Vane · \(value.title)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(value.value).font(.headline).minimumScaleFactor(0.72)
                }
            }
        } else if kind == .sense {
            let read = SenseWidgetPresentation(snapshot)
            HStack(spacing: 8) {
                Image(systemName: read.symbol).font(.title3).widgetAccentable()
                VStack(alignment: .leading, spacing: 1) {
                    Text("Vane Sense · \(read.status)").font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
                    Text(read.headline).font(.headline).lineLimit(1).minimumScaleFactor(0.72)
                }
            }
        } else {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: snapshot.symbolName).font(.title2).widgetAccentable()
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(snapshot.temperatureText(snapshot.temperature))  \(snapshot.condition)")
                        .font(.headline).lineLimit(1).minimumScaleFactor(0.72)
                    Text("Vane · \(snapshot.guidanceHeadline ?? snapshot.locationName)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }

    private var missingData: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: "wind").font(.title2).widgetAccentable()
            Text("Open Vane")
                .font(.headline)
            Text("Load weather to begin.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(family == .accessoryRectangular ? 0 : 14)
    }

    private func resolvedMetric(_ snapshot: VaneWidgetSnapshot) -> VaneWidgetMetric {
        guard metric == .automatic else { return metric }
        if snapshot.precipitationChance >= 0.35 { return .precipitation }
        if snapshot.windSpeed >= 15 { return .wind }
        if snapshot.uvIndex >= 6 && snapshot.isDaylight { return .uvIndex }
        if snapshot.humidity >= 0.67 { return .humidity }
        return .feelsLike
    }
}

private struct SenseWidgetPresentation {
    let headline: String
    let detail: String
    let compactDetail: String
    let status: String
    let symbol: String
    let action: String?
    let isPersonalized: Bool

    init(_ snapshot: VaneWidgetSnapshot) {
        isPersonalized = snapshot.guidanceIsPersonalized
        headline = snapshot.guidanceHeadline ?? "Sense needs a moment"
        detail = snapshot.guidanceDetail ?? "Open Vane after weather loads to update your Sense read."
        symbol = snapshot.guidanceSymbol ?? (snapshot.guidanceIsPersonalized ? "sparkles" : "waveform.path.ecg")
        action = snapshot.guidanceActionText
        if snapshot.guidanceHeadline == nil {
            compactDetail = "Open Vane once to refresh this read."
        } else if snapshot.guidanceIsPersonalized {
            compactDetail = "Based on similar check-ins."
        } else if snapshot.guidanceIsEstimate == true {
            compactDetail = "An early read while Sense learns."
        } else {
            compactDetail = "Check in to teach Sense your range."
        }
        if snapshot.guidanceIsPersonalized {
            status = "Personal read"
        } else if snapshot.guidanceIsEstimate == true {
            status = "Early estimate"
        } else {
            status = snapshot.guidanceCalibrationLabel ?? "Still learning"
        }
    }
}

private struct SenseWidgetHeader: View {
    let snapshot: VaneWidgetSnapshot

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.caption.bold())
                .widgetAccentable()
            Text("VANE · SENSE")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.25)
            Spacer(minLength: 5)
            Text(snapshot.locationName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }
}

private struct SenseStatusBadge: View {
    let read: SenseWidgetPresentation

    var body: some View {
        Text(read.status.uppercased())
            .font(.system(size: 8, weight: .bold))
            .tracking(0.8)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.white.opacity(read.isPersonalized ? 0.17 : 0.10), in: Capsule())
    }
}

private struct SenseSmall: View {
    let snapshot: VaneWidgetSnapshot

    var body: some View {
        let read = SenseWidgetPresentation(snapshot)
        VStack(alignment: .leading, spacing: 0) {
            SenseWidgetHeader(snapshot: snapshot)
            Spacer(minLength: 7)
            Image(systemName: read.symbol)
                .font(.title2)
                .widgetAccentable()
            Text(read.headline)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
            Spacer(minLength: 5)
            HStack(spacing: 5) {
                SenseStatusBadge(read: read)
                Spacer(minLength: 0)
                Text(snapshot.temperatureText(snapshot.apparentTemperature))
                    .font(.caption.bold())
            }
        }
        .foregroundStyle(.white)
        .padding(14)
    }
}

private struct SenseMedium: View {
    let snapshot: VaneWidgetSnapshot

    var body: some View {
        let read = SenseWidgetPresentation(snapshot)
        HStack(spacing: 15) {
            VStack(alignment: .leading, spacing: 6) {
                SenseWidgetHeader(snapshot: snapshot)
                Spacer(minLength: 0)
                Text(read.headline)
                    .font(.title3.bold())
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                Text(read.compactDetail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.70))
                    .lineLimit(2)
            }
            VStack(alignment: .leading, spacing: 5) {
                Image(systemName: read.symbol).font(.title2).widgetAccentable()
                Spacer(minLength: 0)
                Text(snapshot.temperatureText(snapshot.apparentTemperature))
                    .font(.system(size: 30, weight: .medium, design: .rounded))
                Text("Feels like")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.68))
                SenseStatusBadge(read: read)
            }
            .frame(width: 118, alignment: .leading)
            .padding(12)
            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .foregroundStyle(.white)
        .padding(15)
    }
}

private struct SenseLarge: View {
    let snapshot: VaneWidgetSnapshot

    var body: some View {
        let read = SenseWidgetPresentation(snapshot)
        VStack(alignment: .leading, spacing: 14) {
            SenseWidgetHeader(snapshot: snapshot)
            HStack(alignment: .top, spacing: 15) {
                VStack(alignment: .leading, spacing: 7) {
                    SenseStatusBadge(read: read)
                    Text(read.headline)
                        .font(.title.bold())
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                    Text(read.detail)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(3)
                }
                Spacer(minLength: 5)
                VStack(alignment: .trailing, spacing: 1) {
                    Image(systemName: read.symbol).font(.title2).widgetAccentable()
                    Text(snapshot.temperatureText(snapshot.apparentTemperature))
                        .font(.system(size: 42, weight: .medium, design: .rounded))
                    Text("Feels like")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.62))
                }
            }
            HStack(spacing: 9) {
                SenseSignalCard(title: "Conditions", value: snapshot.condition, symbol: snapshot.symbolName)
                SenseSignalCard(title: "Wind", value: snapshot.windText(snapshot.windSpeed), symbol: "wind")
                SenseSignalCard(title: "Humidity", value: snapshot.percentText(snapshot.humidity), symbol: "humidity.fill")
            }
            if let action = read.action {
                Label(action, systemImage: read.symbol)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.white.opacity(0.10), in: Capsule())
            } else {
                Text("Sense compares right now with relevant, seasonally similar check-ins.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
        .foregroundStyle(.white)
        .padding(17)
    }
}

private struct SenseSignalCard: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: symbol).font(.subheadline).widgetAccentable()
            Text(value).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.68)
            Text(title).font(.caption2).foregroundStyle(.white.opacity(0.62))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct NowSmall: View {
    let snapshot: VaneWidgetSnapshot

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 0) {
                WidgetLocationHeader(snapshot: snapshot)
                Spacer().frame(height: 8)
                HStack(alignment: .center, spacing: 6) {
                    Text(snapshot.temperatureText(snapshot.temperature))
                        .font(.system(size: 38, weight: .medium, design: .rounded))
                        .tracking(-2)
                        .minimumScaleFactor(0.68)
                    Spacer(minLength: 0)
                    Image(systemName: snapshot.symbolName)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 27))
                        .accessibilityHidden(true)
                }
                Text(snapshot.condition)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let day = snapshot.today {
                    Text("H \(snapshot.temperatureText(day.high))  L \(snapshot.temperatureText(day.low))")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.76))
                }
            }
            .frame(width: max(0, geometry.size.width - 28), height: max(0, geometry.size.height - 28), alignment: .topLeading)
            .padding(14)
        }
        .foregroundStyle(.white)
    }
}

private struct NowMedium: View {
    let snapshot: VaneWidgetSnapshot
    let date: Date

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                WidgetLocationHeader(snapshot: snapshot)
                Spacer().frame(height: 8)
                HStack(spacing: 9) {
                    Text(snapshot.temperatureText(snapshot.temperature))
                        .font(.system(size: 47, weight: .medium, design: .rounded))
                        .tracking(-2)
                    Image(systemName: snapshot.symbolName)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 34))
                        .accessibilityHidden(true)
                }
                Text(snapshot.guidanceHeadline ?? snapshot.condition)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                ForEach(snapshot.hours(after: date, limit: 4)) { hour in
                    VStack(spacing: 7) {
                        Text(snapshot.hourText(hour.date)).font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                        Image(systemName: hour.symbolName).symbolRenderingMode(.multicolor).font(.title3)
                        Text(snapshot.temperatureText(hour.temperature)).font(.subheadline.bold())
                        if hour.precipitationChance >= 0.25 {
                            Text(snapshot.percentText(hour.precipitationChance)).font(.system(size: 9, weight: .bold)).foregroundStyle(.cyan.opacity(0.9))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: 174)
        }
        .foregroundStyle(.white)
        .padding(16)
    }
}

private struct ForecastSmall: View {
    let snapshot: VaneWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            WidgetLocationHeader(snapshot: snapshot)
            ForEach(snapshot.daily.prefix(3)) { day in
                ForecastDayRow(snapshot: snapshot, day: day, compact: true)
            }
        }
        .foregroundStyle(.white)
        .padding(14)
    }
}

private struct ForecastMedium: View {
    let snapshot: VaneWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                WidgetLocationHeader(snapshot: snapshot)
                Spacer()
                Text(snapshot.condition).font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.72)).lineLimit(1)
            }
            HStack(spacing: 0) {
                ForEach(snapshot.daily.prefix(5)) { day in
                    VStack(spacing: 7) {
                        Text(snapshot.dayText(day.date)).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.74))
                        Image(systemName: day.symbolName).symbolRenderingMode(.multicolor).font(.title3)
                        Text(snapshot.temperatureText(day.high)).font(.subheadline.bold())
                        Text(snapshot.temperatureText(day.low)).font(.caption2.weight(.medium)).foregroundStyle(.white.opacity(0.65))
                        if day.precipitationChance >= 0.25 {
                            Text(snapshot.percentText(day.precipitationChance)).font(.system(size: 9, weight: .bold)).foregroundStyle(.cyan.opacity(0.9))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(16)
    }
}

private struct ForecastLarge: View {
    let snapshot: VaneWidgetSnapshot
    let date: Date
    let dayLimit: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    WidgetLocationHeader(snapshot: snapshot)
                    Text(snapshot.guidanceHeadline ?? snapshot.condition).font(.subheadline.weight(.semibold)).lineLimit(1)
                }
                Spacer()
                Image(systemName: snapshot.symbolName).symbolRenderingMode(.multicolor).font(.system(size: 38))
                Text(snapshot.temperatureText(snapshot.temperature)).font(.system(size: 39, weight: .medium, design: .rounded)).tracking(-1)
            }
            HStack(spacing: 0) {
                ForEach(snapshot.hours(after: date, limit: 5)) { hour in
                    VStack(spacing: 5) {
                        Text(snapshot.hourText(hour.date)).font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                        Image(systemName: hour.symbolName).symbolRenderingMode(.multicolor).font(.body)
                        Text(snapshot.temperatureText(hour.temperature)).font(.caption.bold())
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 9)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(spacing: 0) {
                ForEach(Array(snapshot.daily.prefix(dayLimit).enumerated()), id: \.element.id) { index, day in
                    ForecastDayRow(snapshot: snapshot, day: day)
                        .padding(.vertical, 5)
                    if index < min(dayLimit, snapshot.daily.count) - 1 { Divider().overlay(.white.opacity(0.15)) }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(17)
    }
}

private struct ForecastExtraLarge: View {
    let snapshot: VaneWidgetSnapshot
    let date: Date

    var body: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                WidgetLocationHeader(snapshot: snapshot)
                HStack(alignment: .center, spacing: 12) {
                    Text(snapshot.temperatureText(snapshot.temperature)).font(.system(size: 62, weight: .medium, design: .rounded)).tracking(-3)
                    Image(systemName: snapshot.symbolName).symbolRenderingMode(.multicolor).font(.system(size: 45))
                }
                Text(snapshot.guidanceHeadline ?? snapshot.condition).font(.title3.bold())
                Text(snapshot.guidanceDetail ?? "Feels like \(snapshot.temperatureText(snapshot.apparentTemperature)).")
                    .font(.caption).foregroundStyle(.white.opacity(0.72)).lineLimit(2)
                Spacer().frame(height: 4)
                HStack(spacing: 0) {
                    ForEach(snapshot.hours(after: date, limit: 6)) { hour in
                        VStack(spacing: 5) {
                            Text(snapshot.hourText(hour.date)).font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                            Image(systemName: hour.symbolName).symbolRenderingMode(.multicolor)
                            Text(snapshot.temperatureText(hour.temperature)).font(.caption.bold())
                        }.frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 0) {
                ForEach(Array(snapshot.daily.prefix(8).enumerated()), id: \.element.id) { index, day in
                    ForecastDayRow(snapshot: snapshot, day: day)
                        .padding(.vertical, 7)
                    if index < min(8, snapshot.daily.count) - 1 { Divider().overlay(.white.opacity(0.15)) }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(.white)
        .padding(20)
    }
}

private struct ForecastDayRow: View {
    let snapshot: VaneWidgetSnapshot
    let day: VaneWidgetSnapshot.Day
    var compact = false

    var body: some View {
        HStack(spacing: 8) {
            Text(snapshot.dayText(day.date)).font((compact ? Font.caption2 : .caption).weight(.semibold)).frame(width: compact ? 27 : 34, alignment: .leading)
            Image(systemName: day.symbolName).symbolRenderingMode(.multicolor).font(compact ? .caption : .body).frame(width: 24)
            if day.precipitationChance >= 0.25 {
                Text(snapshot.percentText(day.precipitationChance)).font(.system(size: compact ? 8 : 10, weight: .bold)).foregroundStyle(.cyan.opacity(0.9)).frame(width: compact ? 26 : 34, alignment: .leading)
            } else {
                Spacer().frame(width: compact ? 26 : 34)
            }
            Spacer(minLength: 2)
            Text(snapshot.temperatureText(day.low)).foregroundStyle(.white.opacity(0.62))
            Text(snapshot.temperatureText(day.high)).fontWeight(.bold)
        }
        .font(compact ? .caption2 : .caption)
    }
}

private struct DetailsSmall: View {
    let snapshot: VaneWidgetSnapshot
    let metric: VaneWidgetMetric

    var body: some View {
        let value = WidgetMetricValue(snapshot: snapshot, metric: metric)
        VStack(alignment: .leading, spacing: 0) {
            WidgetLocationHeader(snapshot: snapshot)
            Spacer().frame(height: 12)
            Image(systemName: value.symbol).font(.title2).widgetAccentable()
            Text(value.value).font(.system(size: 27, weight: .bold, design: .rounded)).minimumScaleFactor(0.62).lineLimit(1)
            Text(value.title).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.72))
            Text(value.detail).font(.caption2).foregroundStyle(.white.opacity(0.62)).lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(14)
    }
}

private struct DetailsMedium: View {
    let snapshot: VaneWidgetSnapshot
    let primaryMetric: VaneWidgetMetric

    private var metrics: [VaneWidgetMetric] {
        let values: [VaneWidgetMetric] = [primaryMetric, .wind, .humidity, .uvIndex]
        var seen = Set<VaneWidgetMetric>()
        return values.filter { seen.insert($0).inserted }.prefix(4).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetLocationHeader(snapshot: snapshot)
            HStack(spacing: 9) {
                ForEach(metrics, id: \.rawValue) { metric in
                    let value = WidgetMetricValue(snapshot: snapshot, metric: metric)
                    VStack(alignment: .leading, spacing: 4) {
                        Image(systemName: value.symbol).font(.subheadline).widgetAccentable()
                        Spacer(minLength: 0)
                        Text(value.shortValue).font(.headline).minimumScaleFactor(0.66).lineLimit(1)
                        Text(value.title).font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
            }
        }
        .foregroundStyle(.white)
        .padding(15)
    }
}

private struct DetailsLarge: View {
    let snapshot: VaneWidgetSnapshot
    let primaryMetric: VaneWidgetMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                WidgetLocationHeader(snapshot: snapshot)
                Spacer()
                Text("CONDITIONS").font(.system(size: 10, weight: .bold)).tracking(1.2).foregroundStyle(.white.opacity(0.62))
            }
            let primary = WidgetMetricValue(snapshot: snapshot, metric: primaryMetric)
            HStack(spacing: 13) {
                Image(systemName: primary.symbol).font(.system(size: 34)).widgetAccentable()
                VStack(alignment: .leading, spacing: 1) {
                    Text(primary.value).font(.title.bold()).minimumScaleFactor(0.72)
                    Text(primary.detail).font(.caption).foregroundStyle(.white.opacity(0.68))
                }
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach([VaneWidgetMetric.feelsLike, .precipitation, .wind, .humidity, .uvIndex], id: \.rawValue) { metric in
                    let value = WidgetMetricValue(snapshot: snapshot, metric: metric)
                    HStack(spacing: 9) {
                        Image(systemName: value.symbol).frame(width: 20).widgetAccentable()
                        VStack(alignment: .leading, spacing: 1) {
                            Text(value.title).font(.caption2).foregroundStyle(.white.opacity(0.62))
                            Text(value.value).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(11)
                    .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            if let headline = snapshot.guidanceHeadline {
                HStack(spacing: 8) {
                    Image(systemName: snapshot.guidanceSymbol ?? "sparkles").widgetAccentable()
                    Text(headline).font(.subheadline.weight(.semibold)).lineLimit(1)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(17)
    }
}

private struct SunSmall: View {
    let snapshot: VaneWidgetSnapshot
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetLocationHeader(snapshot: snapshot)
            Spacer().frame(height: 12)
            Image(systemName: snapshot.isDaylight ? "sun.max.fill" : "moon.stars.fill")
                .symbolRenderingMode(.multicolor).font(.title)
            Text(daylightHeadline(snapshot: snapshot, date: date))
                .font(.headline).lineLimit(2).minimumScaleFactor(0.75)
            if let day = snapshot.today {
                Text("↑ \(day.sunrise.map(snapshot.shortTime) ?? "—")   ↓ \(day.sunset.map(snapshot.shortTime) ?? "—")")
                    .font(.caption2.weight(.medium)).foregroundStyle(.white.opacity(0.68))
            }
        }
        .foregroundStyle(.white)
        .padding(14)
    }
}

private struct SunMedium: View {
    let snapshot: VaneWidgetSnapshot
    let date: Date

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                WidgetLocationHeader(snapshot: snapshot)
                Spacer()
                Image(systemName: snapshot.isDaylight ? "sun.max.fill" : "moon.stars.fill").symbolRenderingMode(.multicolor).font(.title)
                Text(daylightHeadline(snapshot: snapshot, date: date)).font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.65)
            }
            if let day = snapshot.today {
                VStack(spacing: 10) {
                    SunTimeRow(title: "Sunrise", date: day.sunrise, symbol: "sunrise.fill", snapshot: snapshot)
                    SunTimeRow(title: "Sunset", date: day.sunset, symbol: "sunset.fill", snapshot: snapshot)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(.white)
        .padding(16)
    }
}

private struct SunLarge: View {
    let snapshot: VaneWidgetSnapshot
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            WidgetLocationHeader(snapshot: snapshot)
            HStack(spacing: 12) {
                Image(systemName: snapshot.isDaylight ? "sun.max.fill" : "moon.stars.fill").symbolRenderingMode(.multicolor).font(.system(size: 38))
                VStack(alignment: .leading) {
                    Text(daylightHeadline(snapshot: snapshot, date: date)).font(.title2.bold())
                    Text("Sun times use \(snapshot.locationName)’s local time.").font(.caption).foregroundStyle(.white.opacity(0.66))
                }
            }
            if let day = snapshot.today {
                DaylightBar(snapshot: snapshot, day: day, date: date)
                HStack(spacing: 10) {
                    SunTimeCard(title: "Sunrise", date: day.sunrise, symbol: "sunrise.fill", snapshot: snapshot)
                    SunTimeCard(title: "Sunset", date: day.sunset, symbol: "sunset.fill", snapshot: snapshot)
                    SunTimeCard(title: "UV index", value: "\(snapshot.uvIndex)", symbol: "sun.max.trianglebadge.exclamationmark.fill")
                }
            }
        }
        .foregroundStyle(.white)
        .padding(17)
    }
}

private struct AccessorySunCircle: View {
    let snapshot: VaneWidgetSnapshot
    let date: Date

    var body: some View {
        let progress = daylightProgress(snapshot: snapshot, date: date)
        ZStack {
            Gauge(value: progress) {
                Image(systemName: snapshot.isDaylight ? "sun.max.fill" : "moon.stars.fill")
            } currentValueLabel: {
                Image(systemName: snapshot.isDaylight ? "sun.max.fill" : "moon.stars.fill").font(.caption)
            }
            Text("VANE")
                .font(.system(size: 5, weight: .bold))
                .tracking(0.35)
                .offset(y: 16)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
    }
}

private struct AccessorySunRectangle: View {
    let snapshot: VaneWidgetSnapshot
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("VANE · SUN")
                .font(.system(size: 8, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Label(daylightHeadline(snapshot: snapshot, date: date), systemImage: snapshot.isDaylight ? "sun.max.fill" : "moon.stars.fill")
                .font(.headline).widgetAccentable()
            if let day = snapshot.today {
                HStack {
                    Text("↑ \(day.sunrise.map(snapshot.shortTime) ?? "—")")
                    Spacer()
                    Text("↓ \(day.sunset.map(snapshot.shortTime) ?? "—")")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct DaylightBar: View {
    let snapshot: VaneWidgetSnapshot
    let day: VaneWidgetSnapshot.Day
    let date: Date

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.14))
                    Capsule().fill(.yellow.opacity(0.78)).frame(width: geometry.size.width * daylightProgress(snapshot: snapshot, date: date))
                }
            }
            .frame(height: 7)
            HStack {
                Text(day.sunrise.map(snapshot.shortTime) ?? "—")
                Spacer()
                Text(day.sunset.map(snapshot.shortTime) ?? "—")
            }
            .font(.caption2).foregroundStyle(.white.opacity(0.64))
        }
    }
}

private struct SunTimeRow: View {
    let title: String
    let date: Date?
    let symbol: String
    let snapshot: VaneWidgetSnapshot

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).font(.title3).widgetAccentable()
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption2).foregroundStyle(.white.opacity(0.65))
                Text(date.map(snapshot.shortTime) ?? "—").font(.headline)
            }
            Spacer()
        }
        .padding(10)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

private struct SunTimeCard: View {
    let title: String
    let value: String
    let symbol: String

    init(title: String, date: Date?, symbol: String, snapshot: VaneWidgetSnapshot) {
        self.title = title
        self.value = date.map(snapshot.shortTime) ?? "—"
        self.symbol = symbol
    }

    init(title: String, value: String, symbol: String) {
        self.title = title
        self.value = value
        self.symbol = symbol
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: symbol).widgetAccentable()
            Text(value).font(.headline)
            Text(title).font(.caption2).foregroundStyle(.white.opacity(0.64))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct WidgetLocationHeader: View {
    let snapshot: VaneWidgetSnapshot

    var body: some View {
        HStack(spacing: 5) {
            Text("VANE")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.8)
                .widgetAccentable()
            Capsule()
                .fill(.white.opacity(0.38))
                .frame(width: 1, height: 9)
            Text(snapshot.locationName).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.72)
            if snapshot.alertSummary != nil {
                Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(.yellow)
            }
            if snapshot.isStale {
                Image(systemName: "clock.badge.exclamationmark").font(.caption2).foregroundStyle(.white.opacity(0.66))
            }
        }
    }
}

private struct WidgetMetricValue {
    let title: String
    let value: String
    let shortValue: String
    let detail: String
    let symbol: String

    init(snapshot: VaneWidgetSnapshot, metric: VaneWidgetMetric) {
        switch metric {
        case .automatic, .feelsLike:
            title = "Feels like"
            value = snapshot.temperatureText(snapshot.apparentTemperature)
            shortValue = value
            detail = "Actual \(snapshot.temperatureText(snapshot.temperature))"
            symbol = "thermometer.medium"
        case .precipitation:
            title = "Precipitation"
            value = snapshot.percentText(snapshot.precipitationChance)
            shortValue = value
            detail = snapshot.precipitationChance >= 0.5 ? "Likely this hour" : "Chance this hour"
            symbol = "drop.fill"
        case .wind:
            title = "Wind"
            value = snapshot.windText(snapshot.windSpeed)
            shortValue = snapshot.windUnit == "kilometersPerHour" ? "\(Int((Double(snapshot.windSpeed) * 1.60934).rounded()))" : "\(snapshot.windSpeed)"
            detail = "\(snapshot.windDirection) · Gusts \(snapshot.windText(snapshot.windGust))"
            symbol = "wind"
        case .humidity:
            title = "Humidity"
            value = snapshot.percentText(snapshot.humidity)
            shortValue = value
            detail = "Dew point \(snapshot.temperatureText(snapshot.dewPoint))"
            symbol = "humidity.fill"
        case .uvIndex:
            title = "UV index"
            value = "\(snapshot.uvIndex)"
            shortValue = value
            detail = uvDescription(snapshot.uvIndex)
            symbol = "sun.max.trianglebadge.exclamationmark.fill"
        }
    }
}

private func uvDescription(_ value: Int) -> String {
    switch value {
    case 0...2: "Low"
    case 3...5: "Moderate"
    case 6...7: "High"
    case 8...10: "Very high"
    default: "Extreme"
    }
}

private func daylightHeadline(snapshot: VaneWidgetSnapshot, date: Date) -> String {
    guard let day = snapshot.today else { return "Sun times unavailable" }
    if snapshot.isDaylight, let sunset = day.sunset {
        return "Sunset at \(snapshot.shortTime(sunset))"
    }
    if let sunrise = day.sunrise, sunrise > date {
        return "Sunrise at \(snapshot.shortTime(sunrise))"
    }
    return "Night in \(snapshot.locationName)"
}

private func daylightProgress(snapshot: VaneWidgetSnapshot, date: Date) -> Double {
    guard let day = snapshot.today, let sunrise = day.sunrise, let sunset = day.sunset, sunset > sunrise else { return 0 }
    return min(1, max(0, date.timeIntervalSince(sunrise) / sunset.timeIntervalSince(sunrise)))
}
