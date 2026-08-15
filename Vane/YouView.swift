import SwiftData
import SwiftUI

struct YouView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \WeatherCheckIn.createdAt, order: .reverse) private var checkIns: [WeatherCheckIn]
    @Query private var profiles: [WeatherProfile]
    @Bindable var store: WeatherStore
    @Bindable var notifications: NotificationManager
    @State private var showCheckIn = false

    private var profile: WeatherProfile? { profiles.first }
    private var samples: [GuidanceSample] {
        checkIns.compactMap {
            guard let response = $0.feelResponse else { return nil }
            return GuidanceSample(date: $0.createdAt, apparentTemperature: profile?.usesFeelsLikeTemperature == false ? $0.temperature : $0.apparentTemperature, humidity: $0.humidity, windSpeed: $0.windSpeed, response: response, contexts: $0.contexts, cloudCover: $0.cloudCover ?? 0.5, isTravel: $0.isTravel)
        }
    }
    private var summary: SenseProfileSummary { GuidanceEngine.profileSummary(temperaturePreference: profile?.temperaturePreference ?? 0, windSensitivity: profile?.windSensitivity ?? 0.5, humiditySensitivity: profile?.humiditySensitivity ?? 0.5, samples: samples) }

    var body: some View {
        ZStack {
            AtmosphericBackground(condition: store.snapshot.current)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionKicker(title: "You")
                        Text("Your weather profile")
                            .font(.largeTitle.bold())
                        Text("Sense learns from optional check-ins and stays honest about what it has not seen yet.")
                            .foregroundStyle(VaneTheme.muted)
                    }

                    Button { showCheckIn = true } label: {
                        Label("Check In Now", systemImage: "checkmark.bubble.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 54)
                    }
                    .vaneLiquidGlassButton(prominent: true)
                    .disabled(store.snapshot.isPlaceholder)

                    GlassCard {
                        VStack(alignment: .leading, spacing: 14) {
                            if dynamicTypeSize.isAccessibilitySize {
                                VStack(alignment: .leading, spacing: 4) { SectionKicker(title: "Calibration"); Text(summary.status.rawValue).font(.caption.bold()).foregroundStyle(VaneTheme.blue) }
                            } else {
                                HStack { SectionKicker(title: "Calibration"); Spacer(); Text(summary.status.rawValue).font(.caption.bold()).foregroundStyle(VaneTheme.blue) }
                            }
                            Text(summary.statusDetail).font(.subheadline).foregroundStyle(VaneTheme.muted)
                            Divider()
                            ProfileLine(title: "Comfortable range", value: summary.canPersonalize ? "\(Int(summary.comfortLow.rounded()))–\(Int(summary.comfortHigh.rounded()))°" : "Still learning")
                            ProfileLine(title: "Cold threshold", value: summary.canPersonalize ? "Below \(Int(summary.comfortLow.rounded()))°" : "Still learning")
                            ProfileLine(title: "Warm threshold", value: summary.canPersonalize ? "Above \(Int(summary.comfortHigh.rounded()))°" : "Still learning")
                            ProfileLine(title: "Humidity sensitivity", value: summary.humiditySummary)
                            ProfileLine(title: "Wind sensitivity", value: summary.windSummary)
                            ProfileLine(title: "Sun sensitivity", value: summary.sunSummary)
                        }.padding(20)
                    }

                    NavigationLink { SenseView(snapshot: store.snapshot) } label: { YouRow(symbol: "sparkles", title: "Sense detail", detail: "Familiar conditions and seasonal learning") }.vaneLiquidGlassButton()
                    NavigationLink { CheckInHistoryView() } label: { YouRow(symbol: "clock.arrow.circlepath", title: "Check-in history", detail: checkIns.isEmpty ? "No moments yet" : "\(checkIns.count) weather moments") }.vaneLiquidGlassButton()
                    NavigationLink { SettingsView(store: store, notifications: notifications) } label: { YouRow(symbol: "gearshape.fill", title: "Settings", detail: "Units, alerts, appearance and privacy") }.vaneLiquidGlassButton()
                }
                .padding(18)
                .padding(.bottom, 110)
                .containerRelativeFrame(.horizontal)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showCheckIn) { CheckInView(snapshot: store.snapshot) }
    }
}

private struct ProfileLine: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let value: String
    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 3) { Text(title).font(.subheadline); Text(value).font(.caption.weight(.semibold)).foregroundStyle(VaneTheme.muted) }
            } else {
                HStack(alignment: .firstTextBaseline) { Text(title).font(.subheadline); Spacer(); Text(value).font(.caption.weight(.semibold)).foregroundStyle(VaneTheme.muted).multilineTextAlignment(.trailing) }
            }
        }
    }
}

private struct YouRow: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).foregroundStyle(VaneTheme.blue).frame(width: 32, height: 44)
            VStack(alignment: .leading, spacing: 3) { Text(title).font(.headline); Text(detail).font(.caption).foregroundStyle(VaneTheme.muted) }
            Spacer(); Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(VaneTheme.muted)
        }.padding(.horizontal, 17).frame(minHeight: 66).foregroundStyle(VaneTheme.ink)
    }
}
