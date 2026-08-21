import SwiftUI

struct WatchContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var store: WatchWeatherStore

    var body: some View {
        Group {
            if let snapshot = store.snapshot {
                TabView {
                    WatchNowView(snapshot: snapshot)
                    WatchForecastView(snapshot: snapshot)
                    WatchSenseView(snapshot: snapshot, store: store)
                }
                .tabViewStyle(.verticalPage)
            } else {
                WatchSetupView(store: store)
            }
        }
        .tint(.cyan)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            store.requestRefresh()
        }
    }
}

private struct WatchNowView: View {
    let snapshot: VaneWidgetSnapshot

    var body: some View {
        ZStack {
            WatchSky(snapshot: snapshot)
            ScrollView {
                VStack(spacing: 10) {
                    VStack(spacing: 1) {
                        Text(snapshot.locationName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        if snapshot.isStale {
                            Label("Forecast may be outdated", systemImage: "clock.badge.exclamationmark")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                        } else {
                            Text(snapshot.updatedAt, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }

                    HStack(spacing: 8) {
                        Image(systemName: snapshot.symbolName)
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 36))
                            .accessibilityHidden(true)
                        Text(snapshot.temperatureText(snapshot.temperature))
                            .font(.system(size: 48, weight: .medium, design: .rounded))
                            .minimumScaleFactor(0.7)
                    }

                    VStack(spacing: 2) {
                        Text(snapshot.condition)
                            .font(.headline)
                            .lineLimit(1)
                        Text("Feels like \(snapshot.temperatureText(snapshot.apparentTemperature))")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.78))
                    }

                    if let alert = snapshot.alertSummary {
                        Label(alert, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2.weight(.semibold))
                            .lineLimit(2)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.orange.opacity(0.22), in: .rect(cornerRadius: 10))
                    }

                    HStack(spacing: 7) {
                        WatchMetric(symbol: "drop.fill", value: snapshot.percentText(snapshot.precipitationChance), label: "Rain")
                        WatchMetric(symbol: "wind", value: snapshot.windText(snapshot.windSpeed), label: "Wind")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
        }
        .containerBackground(.black, for: .navigation)
        .accessibilityElement(children: .contain)
    }
}

private struct WatchForecastView: View {
    let snapshot: VaneWidgetSnapshot

    private var hours: [VaneWidgetSnapshot.Hour] {
        snapshot.hours(after: .now, limit: 5)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Forecast")
                    .font(.headline)

                if !hours.isEmpty {
                    HStack(spacing: 0) {
                        ForEach(hours) { hour in
                            VStack(spacing: 4) {
                                Text(snapshot.hourText(hour.date))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Image(systemName: hour.symbolName)
                                    .symbolRenderingMode(.multicolor)
                                    .font(.caption)
                                Text(snapshot.temperatureText(hour.temperature))
                                    .font(.caption.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(snapshot.hourText(hour.date)), \(hour.condition), \(snapshot.temperatureText(hour.temperature))")
                        }
                    }
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.07), in: .rect(cornerRadius: 12))
                }

                VStack(spacing: 0) {
                    ForEach(Array(snapshot.daily.prefix(5).enumerated()), id: \.element.id) { index, day in
                        HStack(spacing: 6) {
                            Text(index == 0 ? "Now" : snapshot.dayText(day.date))
                                .font(.caption.weight(.semibold))
                                .frame(width: 35, alignment: .leading)
                            Image(systemName: day.symbolName)
                                .symbolRenderingMode(.multicolor)
                                .font(.caption)
                                .frame(width: 22)
                            Spacer(minLength: 2)
                            Text(snapshot.temperatureText(day.low))
                                .foregroundStyle(.secondary)
                            Text(snapshot.temperatureText(day.high))
                                .fontWeight(.semibold)
                        }
                        .font(.caption)
                        .padding(.vertical, 7)
                        if index < min(snapshot.daily.count, 5) - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 9)
                .background(.white.opacity(0.07), in: .rect(cornerRadius: 12))
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
        }
        .containerBackground(Color(red: 0.02, green: 0.07, blue: 0.13), for: .navigation)
    }
}

private struct WatchSenseView: View {
    let snapshot: VaneWidgetSnapshot
    @ObservedObject var store: WatchWeatherStore

    private var status: String {
        if snapshot.guidanceIsPersonalized { return "Personal read" }
        if snapshot.guidanceIsEstimate == true { return "Early estimate" }
        return snapshot.guidanceCalibrationLabel ?? "Still learning"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: snapshot.guidanceSymbol ?? "sparkles")
                        .foregroundStyle(.cyan)
                    Text("Sense")
                        .font(.headline)
                }

                Text(status.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(.cyan)

                Text(snapshot.guidanceHeadline ?? "Sense needs experience")
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                Text(snapshot.guidanceDetail ?? "Check in on your iPhone to teach Sense how weather feels to you.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let action = snapshot.guidanceActionText {
                    Label(action, systemImage: "figure.walk")
                        .font(.caption.weight(.medium))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.cyan.opacity(0.12), in: .rect(cornerRadius: 10))
                }

                Button {
                    store.requestRefresh()
                } label: {
                    if store.isRequestingRefresh {
                        ProgressView()
                    } else {
                        Label("Sync iPhone", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .buttonStyle(.bordered)

                if let message = store.syncMessage {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 9)
            .padding(.bottom, 10)
        }
        .containerBackground(Color(red: 0.02, green: 0.07, blue: 0.13), for: .navigation)
    }
}

private struct WatchSetupView: View {
    @ObservedObject var store: WatchWeatherStore

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "wind")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.cyan)
                Text("Vane is ready")
                    .font(.headline)
                Text("Open Vane on your iPhone once. Your latest weather and Sense read will sync automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    store.requestRefresh()
                } label: {
                    if store.isRequestingRefresh {
                        ProgressView()
                    } else {
                        Label("Try Sync", systemImage: "iphone.and.arrow.forward")
                    }
                }
                if let message = store.syncMessage {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .containerBackground(Color(red: 0.02, green: 0.07, blue: 0.13), for: .navigation)
    }
}

private struct WatchMetric: View {
    let symbol: String
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(label, systemImage: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.68))
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.11), in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value)")
    }
}

private struct WatchSky: View {
    let snapshot: VaneWidgetSnapshot

    private var colors: [Color] {
        if !snapshot.isDaylight {
            return [Color(red: 0.01, green: 0.04, blue: 0.12), Color(red: 0.03, green: 0.15, blue: 0.30)]
        }
        let symbol = snapshot.symbolName.lowercased()
        if symbol.contains("rain") || symbol.contains("thunder") {
            return [Color(red: 0.08, green: 0.18, blue: 0.28), Color(red: 0.24, green: 0.42, blue: 0.56)]
        }
        if symbol.contains("cloud") {
            return [Color(red: 0.10, green: 0.31, blue: 0.52), Color(red: 0.36, green: 0.60, blue: 0.76)]
        }
        return [Color(red: 0.03, green: 0.32, blue: 0.72), Color(red: 0.14, green: 0.64, blue: 0.86)]
    }

    var body: some View {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(.white.opacity(snapshot.isDaylight ? 0.16 : 0.06))
                    .frame(width: 130, height: 130)
                    .blur(radius: 28)
                    .offset(x: -42, y: -55)
            }
            .ignoresSafeArea()
    }
}

#if DEBUG
#Preview("Loaded") {
    WatchContentView(store: .preview(snapshot: .sample))
}
#endif
