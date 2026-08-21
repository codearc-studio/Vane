import SwiftUI
import WidgetKit

private struct VaneWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let kind: VaneWidgetKind
    let entry: VaneWidgetEntry

    var body: some View {
        VaneWidgetContentView(
            family: family,
            kind: kind,
            snapshot: entry.snapshot,
            metric: entry.configuration.focus.metric,
            date: entry.date
        )
        .containerBackground(for: .widget) {
            if isAccessory {
                Color.clear
            } else if kind == .sense {
                VaneSenseWidgetBackground(snapshot: entry.snapshot)
            } else {
                VaneWidgetBackground(snapshot: entry.snapshot)
            }
        }
        .widgetURL(deepLink)
    }

    private var isAccessory: Bool {
        family == .accessoryInline || family == .accessoryCircular || family == .accessoryRectangular
    }

    private var deepLink: URL? {
        if entry.snapshot?.alertSummary != nil {
            return URL(string: "vane://weather/alerts")
        }
        return switch kind {
        case .now: URL(string: "vane://weather")
        case .forecast: URL(string: "vane://weather/week")
        case .details: URL(string: "vane://weather/conditions")
        case .sun: URL(string: "vane://weather/sun")
        case .sense: URL(string: "vane://sense")
        }
    }
}

private struct VaneSenseWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: VaneSenseWidgetEntry

    var body: some View {
        VaneWidgetContentView(family: family, kind: .sense, snapshot: entry.snapshot, date: entry.date)
            .containerBackground(for: .widget) {
                if isAccessory {
                    Color.clear
                } else {
                    VaneSenseWidgetBackground(snapshot: entry.snapshot)
                }
            }
            .widgetURL(URL(string: "vane://sense"))
    }

    private var isAccessory: Bool {
        family == .accessoryInline || family == .accessoryCircular || family == .accessoryRectangular
    }
}

struct VaneNowWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: VaneWidgetConstants.nowKind, intent: VaneWidgetConfiguration.self, provider: VaneWidgetProvider()) { entry in
            VaneWidgetEntryView(kind: .now, entry: entry)
        }
        .configurationDisplayName("Vane Now")
        .description("Current weather, your Sense read, and the next few hours.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryInline, .accessoryCircular, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

struct VaneForecastWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: VaneWidgetConstants.forecastKind, intent: VaneWidgetConfiguration.self, provider: VaneWidgetProvider()) { entry in
            VaneWidgetEntryView(kind: .forecast, entry: entry)
        }
        .configurationDisplayName("Vane Forecast")
        .description("A polished multi-day forecast with hourly context.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        .contentMarginsDisabled()
    }
}

struct VaneDetailsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: VaneWidgetConstants.detailsKind, intent: VaneWidgetConfiguration.self, provider: VaneWidgetProvider()) { entry in
            VaneWidgetEntryView(kind: .details, entry: entry)
        }
        .configurationDisplayName("Vane Conditions")
        .description("Feels like, rain, wind, humidity, and UV with a configurable focus.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryInline, .accessoryCircular, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

struct VaneSunWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: VaneWidgetConstants.sunKind, intent: VaneWidgetConfiguration.self, provider: VaneWidgetProvider()) { entry in
            VaneWidgetEntryView(kind: .sun, entry: entry)
        }
        .configurationDisplayName("Vane Sun")
        .description("Sunrise, sunset, daylight progress, and UV at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryInline, .accessoryCircular, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

struct VaneSenseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: VaneWidgetConstants.senseKind, provider: VaneSenseWidgetProvider()) { entry in
            VaneSenseWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Vane Sense")
        .description("Your current Sense read, clearly labeled by how much Vane has learned.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge, .accessoryInline, .accessoryCircular, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

#Preview("Now", as: .systemSmall) {
    VaneNowWidget()
} timeline: {
    VaneWidgetEntry(date: .now, snapshot: .sample, configuration: .automatic)
}

#Preview("Forecast", as: .systemLarge) {
    VaneForecastWidget()
} timeline: {
    VaneWidgetEntry(date: .now, snapshot: .sample, configuration: .automatic)
}

#Preview("Lock Screen", as: .accessoryRectangular) {
    VaneNowWidget()
} timeline: {
    VaneWidgetEntry(date: .now, snapshot: .sample, configuration: .automatic)
}

#Preview("Sense", as: .systemMedium) {
    VaneSenseWidget()
} timeline: {
    VaneSenseWidgetEntry(date: .now, snapshot: .sample)
}
