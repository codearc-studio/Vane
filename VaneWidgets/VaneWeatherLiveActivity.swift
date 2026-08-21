import ActivityKit
import SwiftUI
import WidgetKit

struct VaneWeatherLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VaneWeatherActivityAttributes.self) { context in
            VaneWeatherLiveActivityLockScreen(context: context)
                .activityBackgroundTint(backgroundColor(for: context.state.kind))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: context.state.destinationURLString))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        Image(systemName: context.state.symbolName)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(accentColor(for: context.state.kind))
                        Text(context.state.temperatureText)
                            .font(.headline.monospacedDigit())
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VaneWeatherActivityTiming(state: context.state, compact: false)
                        .foregroundStyle(accentColor(for: context.state.kind))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Text("VANE")
                                .font(.system(size: 9, weight: .heavy))
                                .tracking(1)
                            Circle()
                                .fill(.secondary)
                                .frame(width: 3, height: 3)
                            if context.attributes.isTravelLocation {
                                Image(systemName: "airplane")
                            }
                            Text(context.attributes.locationName)
                        }
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        Text(context.state.title)
                            .font(.headline)
                        Text(context.state.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: context.state.symbolName)
                    .foregroundStyle(accentColor(for: context.state.kind))
            } compactTrailing: {
                VaneWeatherActivityTiming(state: context.state, compact: true)
                    .foregroundStyle(accentColor(for: context.state.kind))
            } minimal: {
                Image(systemName: context.state.symbolName)
                    .foregroundStyle(accentColor(for: context.state.kind))
            }
            .keylineTint(accentColor(for: context.state.kind))
            .widgetURL(URL(string: context.state.destinationURLString))
        }
    }

    private func accentColor(for kind: VaneWeatherActivityKind) -> Color {
        switch kind {
        case .severeAlert: Color(red: 1.0, green: 0.32, blue: 0.22)
        case .storm: Color(red: 0.72, green: 0.48, blue: 1.0)
        case .precipitation: Color(red: 0.26, green: 0.70, blue: 1.0)
        case .outdoorWindow: Color(red: 1.0, green: 0.72, blue: 0.28)
        }
    }

    private func backgroundColor(for kind: VaneWeatherActivityKind) -> Color {
        switch kind {
        case .severeAlert: Color(red: 0.18, green: 0.035, blue: 0.04)
        case .storm: Color(red: 0.06, green: 0.04, blue: 0.15)
        case .precipitation: Color(red: 0.025, green: 0.09, blue: 0.18)
        case .outdoorWindow: Color(red: 0.055, green: 0.11, blue: 0.16)
        }
    }
}

private struct VaneWeatherLiveActivityLockScreen: View {
    let context: ActivityViewContext<VaneWeatherActivityAttributes>

    var body: some View {
        HStack(spacing: 15) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.11))
                Image(systemName: context.state.symbolName)
                    .font(.title2.weight(.semibold))
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(context.state.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(context.state.detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(2)
                HStack(spacing: 5) {
                    Text("VANE")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1)
                    Circle()
                        .fill(.white.opacity(0.45))
                        .frame(width: 3, height: 3)
                    if context.attributes.isTravelLocation {
                        Image(systemName: "airplane")
                    }
                    Text(context.attributes.locationName)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.62))
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                Text(context.state.temperatureText)
                    .font(.title3.bold().monospacedDigit())
                VaneWeatherActivityTiming(state: context.state, compact: false)
                    .font(.caption.weight(.semibold))
            }
        }
        .foregroundStyle(.white)
        .padding(16)
    }
}

private struct VaneWeatherActivityTiming: View {
    let state: VaneWeatherActivityAttributes.ContentState
    let compact: Bool

    var body: some View {
        if state.showsCountdown, let eventDate = state.eventDate, eventDate > .now {
            Text(timerInterval: Date.now...eventDate, countsDown: true)
                .monospacedDigit()
                .frame(minWidth: compact ? 34 : nil)
        } else if !compact, let eventDate = state.eventDate {
            Text(eventDate, style: .time)
                .monospacedDigit()
        } else if compact {
            Text(state.temperatureText)
                .monospacedDigit()
        } else {
            Text("Live")
        }
    }
}

#Preview("Rain Live Activity", as: .content, using: VaneWeatherActivityAttributes(locationName: "New York", sourceID: "current", isTravelLocation: false)) {
    VaneWeatherLiveActivity()
} contentStates: {
    VaneWeatherActivityAttributes.ContentState(
        kind: .precipitation,
        title: "Rain arriving",
        detail: "Forecast around 6:20 PM · 76% chance",
        symbolName: "cloud.rain.fill",
        temperatureText: "72°",
        eventDate: .now.addingTimeInterval(18 * 60),
        showsCountdown: true,
        updatedAt: .now,
        destinationURLString: "vane://weather"
    )
}
