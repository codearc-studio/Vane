import SwiftUI
import WidgetKit

private struct VaneWatchEntry: TimelineEntry {
    let date: Date
    let snapshot: VaneWidgetSnapshot?
}

private struct VaneWatchProvider: TimelineProvider {
    func placeholder(in context: Context) -> VaneWatchEntry {
        VaneWatchEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (VaneWatchEntry) -> Void) {
        completion(VaneWatchEntry(
            date: .now,
            snapshot: context.isPreview ? .sample : VaneWidgetDataStore.load()
        ))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<VaneWatchEntry>) -> Void) {
        let now = Date.now
        let snapshot = VaneWidgetDataStore.load()
        let entries = (0..<8).compactMap { offset -> VaneWatchEntry? in
            guard let date = Calendar.current.date(byAdding: .hour, value: offset, to: now) else { return nil }
            return VaneWatchEntry(date: date, snapshot: snapshot)
        }
        completion(Timeline(
            entries: entries.isEmpty ? [VaneWatchEntry(date: now, snapshot: snapshot)] : entries,
            policy: .after(now.addingTimeInterval(30 * 60))
        ))
    }
}

private enum VaneWatchComplicationKind {
    case now
    case conditions
    case sun
    case sense
}

private struct VaneWatchComplicationView: View {
    @Environment(\.widgetFamily) private var family

    let kind: VaneWatchComplicationKind
    let entry: VaneWatchEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                content(snapshot)
            } else {
                missingData
            }
        }
        .containerBackground(.clear, for: .widget)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func content(_ snapshot: VaneWidgetSnapshot) -> some View {
        switch family {
        case .accessoryInline:
            inline(snapshot)
        case .accessoryCircular:
            circular(snapshot)
        case .accessoryRectangular:
            rectangular(snapshot)
        case .accessoryCorner:
            corner(snapshot)
        default:
            rectangular(snapshot)
        }
    }

    @ViewBuilder
    private func inline(_ snapshot: VaneWidgetSnapshot) -> some View {
        switch kind {
        case .now:
            Label("\(snapshot.temperatureText(snapshot.temperature)) · \(snapshot.condition)", systemImage: snapshot.symbolName)
        case .conditions:
            Label("Rain \(snapshot.percentText(snapshot.precipitationChance)) · \(snapshot.windText(snapshot.windSpeed))", systemImage: "drop.fill")
        case .sun:
            if let event = nextSunEvent(snapshot) {
                Label("\(event.name) \(snapshot.shortTime(event.date))", systemImage: event.symbol)
            } else {
                Label("Sun times unavailable", systemImage: "sun.max")
            }
        case .sense:
            Label(senseHeadline(snapshot), systemImage: snapshot.guidanceSymbol ?? "sparkles")
        }
    }

    @ViewBuilder
    private func circular(_ snapshot: VaneWidgetSnapshot) -> some View {
        ZStack {
            AccessoryWidgetBackground()
            switch kind {
            case .now:
                VStack(spacing: -2) {
                    Image(systemName: snapshot.symbolName)
                        .font(.caption)
                    Text(snapshot.temperatureText(snapshot.temperature))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                }
            case .conditions:
                VStack(spacing: -2) {
                    Image(systemName: "drop.fill")
                        .font(.caption)
                    Text(snapshot.percentText(snapshot.precipitationChance))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
            case .sun:
                Gauge(value: daylightProgress(snapshot, at: entry.date)) {
                    Image(systemName: "sun.max.fill")
                } currentValueLabel: {
                    Image(systemName: snapshot.isDaylight ? "sun.max.fill" : "moon.stars.fill")
                }
                .gaugeStyle(.accessoryCircular)
            case .sense:
                VStack(spacing: -2) {
                    Image(systemName: snapshot.guidanceSymbol ?? "sparkles")
                        .font(.caption)
                    Text(snapshot.temperatureText(snapshot.apparentTemperature))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
            }
        }
        .widgetAccentable()
    }

    @ViewBuilder
    private func rectangular(_ snapshot: VaneWidgetSnapshot) -> some View {
        HStack(spacing: 7) {
            Image(systemName: rectangularSymbol(snapshot))
                .font(.title3)
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 1) {
                Text(rectangularEyebrow(snapshot))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(rectangularHeadline(snapshot))
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(rectangularDetail(snapshot))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func corner(_ snapshot: VaneWidgetSnapshot) -> some View {
        switch kind {
        case .sun:
            Gauge(value: daylightProgress(snapshot, at: entry.date)) {
                Image(systemName: snapshot.isDaylight ? "sun.max.fill" : "moon.stars.fill")
            } currentValueLabel: {
                Image(systemName: snapshot.isDaylight ? "sun.max.fill" : "moon.stars.fill")
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
        default:
            VStack(spacing: -2) {
                Image(systemName: cornerSymbol(snapshot))
                    .font(.caption)
                Text(cornerValue(snapshot))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.7)
            }
            .widgetAccentable()
        }
    }

    private var missingData: some View {
        Group {
            switch family {
            case .accessoryInline:
                Label("Open Vane to sync", systemImage: "wind")
            case .accessoryRectangular:
                HStack(spacing: 7) {
                    Image(systemName: "wind").widgetAccentable()
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Vane")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("Open the app to sync")
                            .font(.headline)
                            .minimumScaleFactor(0.72)
                    }
                }
            default:
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "wind")
                        .font(.title3)
                        .widgetAccentable()
                }
            }
        }
    }

    private func rectangularSymbol(_ snapshot: VaneWidgetSnapshot) -> String {
        switch kind {
        case .now: snapshot.symbolName
        case .conditions: "drop.fill"
        case .sun: snapshot.isDaylight ? "sun.max.fill" : "moon.stars.fill"
        case .sense: snapshot.guidanceSymbol ?? "sparkles"
        }
    }

    private func rectangularEyebrow(_ snapshot: VaneWidgetSnapshot) -> String {
        switch kind {
        case .now: snapshot.locationName
        case .conditions: "Vane Conditions"
        case .sun: "Vane Sun"
        case .sense: senseStatus(snapshot)
        }
    }

    private func rectangularHeadline(_ snapshot: VaneWidgetSnapshot) -> String {
        switch kind {
        case .now: "\(snapshot.temperatureText(snapshot.temperature)) · \(snapshot.condition)"
        case .conditions: "Rain \(snapshot.percentText(snapshot.precipitationChance))"
        case .sun:
            if let event = nextSunEvent(snapshot) {
                "\(event.name) \(snapshot.shortTime(event.date))"
            } else {
                "Sun times unavailable"
            }
        case .sense: senseHeadline(snapshot)
        }
    }

    private func rectangularDetail(_ snapshot: VaneWidgetSnapshot) -> String {
        switch kind {
        case .now:
            snapshot.isStale ? "Forecast may be outdated" : "Feels like \(snapshot.temperatureText(snapshot.apparentTemperature))"
        case .conditions:
            "Wind \(snapshot.windText(snapshot.windSpeed)) · Humidity \(snapshot.percentText(snapshot.humidity))"
        case .sun:
            "UV \(snapshot.uvIndex) · \(Int((daylightProgress(snapshot, at: entry.date) * 100).rounded()))% daylight"
        case .sense:
            snapshot.guidanceIsPersonalized ? "Personalized for you" : "Check in on iPhone to teach Sense"
        }
    }

    private func cornerSymbol(_ snapshot: VaneWidgetSnapshot) -> String {
        switch kind {
        case .now: snapshot.symbolName
        case .conditions: "drop.fill"
        case .sun: snapshot.isDaylight ? "sun.max.fill" : "moon.stars.fill"
        case .sense: snapshot.guidanceSymbol ?? "sparkles"
        }
    }

    private func cornerValue(_ snapshot: VaneWidgetSnapshot) -> String {
        switch kind {
        case .now: snapshot.temperatureText(snapshot.temperature)
        case .conditions: snapshot.percentText(snapshot.precipitationChance)
        case .sun: "\(Int((daylightProgress(snapshot, at: entry.date) * 100).rounded()))%"
        case .sense: snapshot.temperatureText(snapshot.apparentTemperature)
        }
    }

    private func senseHeadline(_ snapshot: VaneWidgetSnapshot) -> String {
        snapshot.guidanceHeadline ?? "Sense needs experience"
    }

    private func senseStatus(_ snapshot: VaneWidgetSnapshot) -> String {
        if snapshot.guidanceIsPersonalized { return "Vane Sense · Personal read" }
        if snapshot.guidanceIsEstimate == true { return "Vane Sense · Early estimate" }
        return "Vane Sense · \(snapshot.guidanceCalibrationLabel ?? "Still learning")"
    }

    private func nextSunEvent(_ snapshot: VaneWidgetSnapshot) -> (name: String, symbol: String, date: Date)? {
        let candidates = snapshot.daily.prefix(2).flatMap { day -> [(String, String, Date)] in
            var events: [(String, String, Date)] = []
            if let sunrise = day.sunrise { events.append(("Sunrise", "sunrise.fill", sunrise)) }
            if let sunset = day.sunset { events.append(("Sunset", "sunset.fill", sunset)) }
            return events
        }
        return candidates
            .filter { $0.2 >= entry.date }
            .min { $0.2 < $1.2 }
            .map { (name: $0.0, symbol: $0.1, date: $0.2) }
    }

    private func daylightProgress(_ snapshot: VaneWidgetSnapshot, at date: Date) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = snapshot.timeZone
        let day = snapshot.daily.first { calendar.isDate($0.date, inSameDayAs: date) } ?? snapshot.today
        guard let day,
              let sunrise = day.sunrise,
              let sunset = day.sunset,
              sunset > sunrise else { return snapshot.isDaylight ? 0.5 : 0 }
        guard date >= sunrise, date <= sunset else { return 0 }
        return min(max(date.timeIntervalSince(sunrise) / sunset.timeIntervalSince(sunrise), 0), 1)
    }
}

struct VaneWatchNowComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: VaneWidgetConstants.watchNowKind, provider: VaneWatchProvider()) { entry in
            VaneWatchComplicationView(kind: .now, entry: entry)
        }
        .configurationDisplayName("Vane Weather")
        .description("Current temperature and conditions from Vane.")
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular, .accessoryCorner])
    }
}

struct VaneWatchConditionsComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: VaneWidgetConstants.watchConditionsKind, provider: VaneWatchProvider()) { entry in
            VaneWatchComplicationView(kind: .conditions, entry: entry)
        }
        .configurationDisplayName("Vane Conditions")
        .description("Rain chance, wind, and humidity at a glance.")
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular, .accessoryCorner])
    }
}

struct VaneWatchSunComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: VaneWidgetConstants.watchSunKind, provider: VaneWatchProvider()) { entry in
            VaneWatchComplicationView(kind: .sun, entry: entry)
        }
        .configurationDisplayName("Vane Sun")
        .description("The next sunrise or sunset and daylight progress.")
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular, .accessoryCorner])
    }
}

struct VaneWatchSenseComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: VaneWidgetConstants.watchSenseKind, provider: VaneWatchProvider()) { entry in
            VaneWatchComplicationView(kind: .sense, entry: entry)
        }
        .configurationDisplayName("Vane Sense")
        .description("Your current Sense read and feels-like temperature.")
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular, .accessoryCorner])
    }
}

#Preview("Weather", as: .accessoryRectangular) {
    VaneWatchNowComplication()
} timeline: {
    VaneWatchEntry(date: .now, snapshot: .sample)
}

#Preview("Conditions", as: .accessoryCircular) {
    VaneWatchConditionsComplication()
} timeline: {
    VaneWatchEntry(date: .now, snapshot: .sample)
}

#Preview("Sun", as: .accessoryCorner) {
    VaneWatchSunComplication()
} timeline: {
    VaneWatchEntry(date: .now, snapshot: .sample)
}

#Preview("Sense", as: .accessoryInline) {
    VaneWatchSenseComplication()
} timeline: {
    VaneWatchEntry(date: .now, snapshot: .sample)
}
