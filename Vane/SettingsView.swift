import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @AppStorage("appearance") private var appearanceRawValue = AppAppearance.system.rawValue
    @Query private var profiles: [WeatherProfile]
    @Query private var checkIns: [WeatherCheckIn]
    @Bindable var store: WeatherStore
    @Bindable var notifications: NotificationManager
    @State private var showResetConfirmation = false

    var body: some View {
        ZStack {
            AtmosphericBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    header
                    SettingsGroup(title: "Appearance") {
                        Picker("Appearance", selection: $appearanceRawValue) {
                            ForEach(AppAppearance.allCases) { appearance in
                                Label(appearance.title, systemImage: appearance.symbol)
                                    .tag(appearance.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel("App appearance")
                        Text("System follows your iPhone automatically.")
                            .font(.caption)
                            .foregroundStyle(VaneTheme.muted)
                    }
                    SettingsGroup(title: "Weather") {
                        Button { store.requestCurrentLocation() } label: {
                            SettingsRow(symbol: "location.fill", title: "Current location", detail: locationDetail)
                        }
                        Divider().opacity(0.38)
                        Link(destination: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!) {
                            SettingsRow(symbol: "cloud.sun.fill", title: "Weather data", detail: "Apple Weather")
                        }
                    }

                    SettingsGroup(title: "Sense temperature") {
                        SettingsRow(
                            symbol: temperatureBasisBinding.wrappedValue ? "thermometer.variable" : "thermometer.medium",
                            title: "Temperature used by Sense",
                            detail: temperatureBasisBinding.wrappedValue ? "Feels Like temperature" : "Actual air temperature"
                        )
                        Picker("Temperature used by Sense", selection: temperatureBasisBinding) {
                            Text("Feels Like").tag(true)
                            Text("Actual").tag(false)
                        }
                        .pickerStyle(.segmented)
                        Text("This changes personal guidance, your learned comfort range and Best Fit. Hourly forecasts still show the actual temperature.")
                            .font(.caption)
                            .foregroundStyle(VaneTheme.muted)
                            .lineSpacing(2)
                    }

                    SettingsGroup(title: "Your Sense") {
                        SettingsRow(symbol: "sparkles", title: "Calibration", detail: calibrationDetail)
                        Divider().opacity(0.38)
                        SettingsRow(symbol: "checkmark.bubble.fill", title: "Weather moments", detail: checkIns.isEmpty ? "None yet" : "\(checkIns.count) kept on this iPhone")
                        Divider().opacity(0.38)
                        Button { hasCompletedOnboarding = false } label: {
                            SettingsRow(symbol: "arrow.counterclockwise", title: "Restart introduction", detail: "Revisit the starting questions")
                        }
                    }

                    SettingsGroup(title: "Quiet reminders") {
                        Toggle(isOn: rainBinding) {
                            SettingsRow(symbol: "cloud.rain.fill", title: "Rain", detail: "Only when rain becomes likely")
                        }
                        Divider().opacity(0.38)
                        Toggle(isOn: preparationBinding) {
                            SettingsRow(symbol: "bell.badge.fill", title: "Preparation", detail: "Temperature shifts and strong UV")
                        }
                        Text(notificationNote)
                            .font(.caption)
                            .foregroundStyle(VaneTheme.muted)
                            .lineSpacing(2)
                            .padding(.top, 3)
                    }

                    SettingsGroup(title: "Privacy") {
                        SettingsRow(symbol: "iphone", title: "Personal learning", detail: "Stored on this iPhone")
                        Divider().opacity(0.38)
                        Link(destination: URL(string: "https://vane.codearc.studio/privacy/")!) {
                            SettingsRow(symbol: "hand.raised.fill", title: "Privacy policy", detail: "How Vane handles your data", showsArrow: true)
                        }
                        Divider().opacity(0.38)
                        Button(role: .destructive) { showResetConfirmation = true } label: {
                            SettingsRow(symbol: "trash", title: "Reset what Vane knows", detail: "Remove calibration and moments", tint: .red)
                        }
                    }

                    SettingsGroup(title: "About") {
                        Link(destination: URL(string: "https://vane.codearc.studio")!) {
                            SettingsRow(symbol: "safari", title: "Vane on the web", detail: "vane.codearc.studio", showsArrow: true)
                        }
                        Divider().opacity(0.38)
                        Link(destination: URL(string: "https://vane.codearc.studio/contact/")!) {
                            SettingsRow(symbol: "envelope", title: "Contact CodeArc", detail: "Questions and feedback", showsArrow: true)
                        }
                        Divider().opacity(0.38)
                        HStack {
                            Text("Version")
                            Spacer()
                            Text("1.0").foregroundStyle(VaneTheme.muted)
                        }
                        .font(.subheadline)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 110)
                .containerRelativeFrame(.horizontal)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("Reset what Vane knows?", isPresented: $showResetConfirmation, titleVisibility: .visible) {
            Button("Reset calibration and moments", role: .destructive) { resetModel() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently removes your personal weather model from this iPhone. Your forecast will still work.")
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            VaneMark(size: 54)
                .frame(width: 72, height: 52)
            VStack(alignment: .leading, spacing: 4) {
                SectionKicker(title: "Vane")
                Text("Make it yours.")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .tracking(-1.2)
                Text("Forecast, learning and reminders.")
                    .font(.caption).foregroundStyle(VaneTheme.muted)
            }
        }
        .foregroundStyle(VaneTheme.ink)
        .padding(.vertical, 8)
    }

    private var locationDetail: String {
        switch store.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: store.snapshot.locationName
        case .denied, .restricted: "Permission off"
        case .notDetermined: "Not requested"
        @unknown default: "Unavailable"
        }
    }

    private var calibrationDetail: String {
        switch checkIns.count {
        case 0: "Your starting comfort range"
        case 1...3: "Finding the edges"
        case 4...9: "A clearer pattern"
        default: "Distinctly personal"
        }
    }

    private var notificationNote: String {
        if notifications.authorizationStatus == .denied {
            return "Notifications are off in iPhone Settings."
        }
        if notifications.authorizationStatus == .notDetermined {
            return "Restart the introduction to choose whether Vane may send useful alerts."
        }
        if notifications.pendingCount > 0 {
            return "\(notifications.pendingCount) useful reminder\(notifications.pendingCount == 1 ? "" : "s") scheduled from this forecast."
        }
        return "Vane only schedules useful changes from the latest forecast. No engagement nudges."
    }

    private var rainBinding: Binding<Bool> {
        Binding(
            get: { notifications.rainEnabled },
            set: { enabled in Task { await notifications.setRainEnabled(enabled, snapshot: store.snapshot) } }
        )
    }

    private var preparationBinding: Binding<Bool> {
        Binding(
            get: { notifications.preparationEnabled },
            set: { enabled in Task { await notifications.setPreparationEnabled(enabled, snapshot: store.snapshot) } }
        )
    }

    private var temperatureBasisBinding: Binding<Bool> {
        Binding(
            get: { profiles.first?.usesFeelsLikeTemperature ?? true },
            set: { usesFeelsLike in
                if let profile = profiles.first {
                    profile.usesFeelsLikeTemperature = usesFeelsLike
                } else {
                    modelContext.insert(WeatherProfile(usesFeelsLikeTemperature: usesFeelsLike))
                }
            }
        )
    }

    private func resetModel() {
        try? modelContext.delete(model: WeatherCheckIn.self)
        try? modelContext.delete(model: WeatherProfile.self)
        modelContext.insert(WeatherProfile())
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionKicker(title: title)
                .padding(.leading, 4)
            VStack(spacing: 13) {
                content
            }
            .padding(17)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
    }
}

private struct SettingsRow: View {
    let symbol: String
    let title: String
    let detail: String
    var showsArrow = false
    var tint = VaneTheme.blue

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.subheadline)
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(VaneTheme.muted)
            }
            Spacer()
            if showsArrow {
                Image(systemName: "arrow.up.right").font(.caption.bold()).foregroundStyle(VaneTheme.muted.opacity(0.6))
            }
        }
        .foregroundStyle(VaneTheme.ink)
        .contentShape(Rectangle())
    }
}
