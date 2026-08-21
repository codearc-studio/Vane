import SwiftData
import SwiftUI

struct YouView: View {
    @AppStorage("temperatureUnit") private var temperatureUnitRaw = TemperatureUnitPreference.localizedDefault.rawValue
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \WeatherCheckIn.createdAt, order: .reverse) private var checkIns: [WeatherCheckIn]
    @Query private var profiles: [WeatherProfile]
    @Bindable var store: WeatherStore
    @Bindable var notifications: NotificationManager
    @State private var showCheckIn = false
    @State private var checkInPresenceWarning: CheckInPresence?
    @State private var showSettings = false
    @State private var showSense = false

    private var profile: WeatherProfile? { profiles.first }
    private var samples: [GuidanceSample] {
        checkIns.compactMap { $0.guidanceSample(usesFeelsLikeTemperature: profile?.usesFeelsLikeTemperature ?? true) }
    }
    private var summary: SenseProfileSummary { GuidanceEngine.profileSummary(temperaturePreference: profile?.temperaturePreference ?? 0, windSensitivity: profile?.windSensitivity ?? 0.5, humiditySensitivity: profile?.humiditySensitivity ?? 0.5, samples: samples) }
    private var formatting: WeatherFormatting { WeatherFormatting(temperature: TemperatureUnitPreference(rawValue: temperatureUnitRaw) ?? .fahrenheit, timeZone: store.snapshot.timeZone) }

    var body: some View {
        ZStack {
            AtmosphericBackground(condition: store.snapshot.current)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            VaneMark(size: 42)
                            Text("Sense").font(.title2.bold())
                        }
                        Text("Your weather profile")
                            .font(.largeTitle.bold())
                        Text("Sense learns from optional check-ins and stays honest about what it has not seen yet.")
                            .foregroundStyle(VaneTheme.muted)
                    }

                    Button { beginCheckIn() } label: {
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
                            ProfileLine(title: "Comfortable range", value: summary.canPersonalize ? formatting.temperatureRange(low: summary.comfortLow, high: summary.comfortHigh) : "Still learning")
                            ProfileLine(title: "Cold threshold", value: summary.canPersonalize ? "Below \(formatting.degrees(summary.comfortLow, includeUnit: true))" : "Still learning")
                            ProfileLine(title: "Warm threshold", value: summary.canPersonalize ? "Above \(formatting.degrees(summary.comfortHigh, includeUnit: true))" : "Still learning")
                            ProfileLine(title: "Humidity sensitivity", value: summary.humiditySummary)
                            ProfileLine(title: "Wind sensitivity", value: summary.windSummary)
                            ProfileLine(title: "Sun sensitivity", value: summary.sunSummary)
                            ProfileLine(title: "Rain & dampness", value: summary.dampnessSummary)
                        }.padding(20)
                    }

                    Button { showSense = true } label: {
                        SenseDetailRow(
                            title: "Sense detail",
                            detail: "Familiar conditions and seasonal learning"
                        )
                    }
                    .vaneLiquidGlassButton()
                    NavigationLink { CheckInHistoryView() } label: { YouRow(symbol: "clock.arrow.circlepath", title: "Check-in history", detail: checkIns.isEmpty ? "No moments yet" : "\(checkIns.count) weather moments") }.vaneLiquidGlassButton()
                    NavigationLink { SettingsView(store: store, notifications: notifications) } label: { YouRow(symbol: "gearshape.fill", title: "Settings", detail: "Units, alerts, appearance and privacy") }.vaneLiquidGlassButton()
                }
                .padding(18)
                .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? 210 : 110)
                .containerRelativeFrame(.horizontal)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showCheckIn) { CheckInView(snapshot: store.snapshot) }
        .confirmationDialog(checkInWarningTitle, isPresented: Binding(get: { checkInPresenceWarning != nil }, set: { if !$0 { checkInPresenceWarning = nil } }), titleVisibility: .visible) {
            Button("I’m here — continue") { checkInPresenceWarning = nil; showCheckIn = true }
            Button("Cancel", role: .cancel) { checkInPresenceWarning = nil }
        } message: { Text(checkInWarningMessage) }
        .navigationDestination(isPresented: $showSettings) { SettingsView(store: store, notifications: notifications) }
        .navigationDestination(isPresented: $showSense) { SenseView(snapshot: store.snapshot) }
        .task {
            if ProcessInfo.processInfo.environment["VANE_SCREENSHOT_TAB"] == "settings" {
                try? await Task.sleep(for: .milliseconds(350))
                showSettings = true
            } else if ProcessInfo.processInfo.environment["VANE_SCREENSHOT_TAB"] == "sense" {
                try? await Task.sleep(for: .milliseconds(350))
                showSense = true
            }
        }
    }

    private func beginCheckIn() {
        let presence = store.checkInPresence(for: store.snapshot)
        if presence == .verified { showCheckIn = true } else { checkInPresenceWarning = presence }
    }

    private var checkInWarningTitle: String {
        if case .away = checkInPresenceWarning { return "Are you in \(store.snapshot.locationName)?" }
        return "Can’t verify this location"
    }

    private var checkInWarningMessage: String {
        switch checkInPresenceWarning {
        case .away(let miles): "Your iPhone appears to be about \(miles) miles away. Continue only if you are actually experiencing this weather."
        case .unavailable: "Location access is off or unavailable. You can still check in, but only if you are currently in \(store.snapshot.locationName)."
        default: ""
        }
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


private struct SenseDetailRow: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image("Vane")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 18)
                .foregroundStyle(VaneTheme.blue)
                .frame(width: 32, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(VaneTheme.muted)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(VaneTheme.muted)
        }
        .padding(.horizontal, 17)
        .frame(minHeight: 66)
        .foregroundStyle(VaneTheme.ink)
    }
}

private struct YouRow: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).foregroundStyle(VaneTheme.blue).frame(width: 32, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(VaneTheme.muted).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(); Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(VaneTheme.muted)
        }.padding(.horizontal, 17).frame(minHeight: 66).foregroundStyle(VaneTheme.ink)
    }
}
