import CloudKit
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("appearance") private var appearanceRawValue = AppAppearance.system.rawValue
    @AppStorage(AutomaticSunAppearance.enabledKey) private var automaticSunAppearance = false
    @AppStorage("temperatureUnit") private var temperatureUnitRaw = TemperatureUnitPreference.localizedDefault.rawValue
    @AppStorage("windUnit") private var windUnitRaw = WindUnitPreference.localizedDefault.rawValue
    @AppStorage("pressureUnit") private var pressureUnitRaw = PressureUnitPreference.localizedDefault.rawValue
    @AppStorage("precipitationUnit") private var precipitationUnitRaw = PrecipitationUnitPreference.localizedDefault.rawValue
    @AppStorage(WeatherLiveActivityManager.enabledKey) private var liveActivitiesEnabled = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Query private var profiles: [WeatherProfile]
    @Query private var checkIns: [WeatherCheckIn]
    @Query private var places: [SavedPlace]
    @Bindable var store: WeatherStore
    @Bindable var notifications: NotificationManager
    @State private var resetAction: ResetAction?
    @State private var pendingNotification: NotificationCategory?
    @State private var errorMessage: String?
    @State private var cloudSyncStatus = CloudSyncStatus()

    var body: some View {
        ZStack {
            AtmosphericBackground(condition: store.snapshot.isPlaceholder ? nil : store.snapshot.current)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) { VaneMark(size: 34); Text("Vane").font(.title2.bold()) }
                        Text("Make it yours")
                            .font(.largeTitle.bold())
                        Text("Weather, Sense and privacy controls in one place.")
                            .foregroundStyle(VaneTheme.muted)
                    }

                    settingsCard("Appearance", symbol: "paintpalette.fill") { appearancePicker }
                    settingsCard("Weather units", symbol: "ruler.fill") {
                        unitPicker("Temperature", selection: $temperatureUnitRaw, values: TemperatureUnitPreference.allCases.map { ($0.rawValue, $0.title) })
                        unitPicker("Wind", selection: $windUnitRaw, values: WindUnitPreference.allCases.map { ($0.rawValue, $0.title) })
                        unitPicker("Pressure", selection: $pressureUnitRaw, values: PressureUnitPreference.allCases.map { ($0.rawValue, $0.title) })
                        unitPicker("Precipitation", selection: $precipitationUnitRaw, values: PrecipitationUnitPreference.allCases.map { ($0.rawValue, $0.title) })
                    }
                    settingsCard("Sense", brandMark: true) {
                        unitPicker("Check-in frequency", selection: frequencyBinding, values: CheckInFrequency.allCases.map { ($0.rawValue, $0.title) })
                        Text("Choose how often useful moments appear—never streaks or daily obligations.").font(.caption).foregroundStyle(VaneTheme.muted)
                        NavigationLink { CheckInHistoryView() } label: { settingsLink("Check-in history", value: checkIns.isEmpty ? "Empty" : "\(checkIns.count)", symbol: "clock.arrow.circlepath") }
                    }
                    settingsCard("Live Activities", symbol: "waveform.path.ecg") {
                        Toggle(isOn: liveActivitiesBinding) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Weather moments").font(.subheadline.weight(.medium))
                                Text("Rain countdowns, storm alerts and strong outdoor windows")
                                    .font(.caption)
                                    .foregroundStyle(VaneTheme.muted)
                            }
                        }
                        .tint(VaneTheme.blue)
                        Text("When something useful is approaching, Vane can keep it visible on the Lock Screen and Dynamic Island. Activities update with Vane’s latest forecast and end when the moment passes.")
                            .font(.caption)
                            .foregroundStyle(VaneTheme.muted)
                        if liveActivitiesEnabled && !WeatherLiveActivityManager.shared.systemActivitiesEnabled {
                            Text("Live Activities are currently disabled for Vane in iPhone Settings.")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(VaneTheme.muted)
                        }
                    }
                    settingsCard("Useful alerts", symbol: "bell.badge.fill") {
                        notificationToggle(.severe, "Official weather alerts", "When a Vane refresh finds a new alert")
                        notificationToggle(.rain, "Rain", "When rain becomes likely")
                        notificationToggle(.snow, "Snow", "A distinct snow heads-up")
                        notificationToggle(.uv, "Strong UV", "Objective sun safety")
                        notificationToggle(.preparation, "Temperature changes", "Large forecast shifts")
                        notificationToggle(.morning, "Morning forecast", "A daily forecast, when enabled")
                        notificationToggle(.tomorrow, "Tomorrow preview", "An evening look ahead")
                        notificationToggle(.smartCheckIn, "Smart check-ins", "Only useful learning moments")
                        Text(notificationNote).font(.caption).foregroundStyle(VaneTheme.muted)
                        Text("Vane’s alert heads-ups depend on background refresh and are not a replacement for government emergency alerts.")
                            .font(.caption)
                            .foregroundStyle(VaneTheme.muted)
                        if notifications.authorizationStatus == .denied { Button("Open iPhone Settings") { notifications.openSettings() }.font(.subheadline.bold()) }
                    }
                    settingsCard("Location & data", symbol: "location.fill") {
                        Button { if store.authorizationStatus == .denied || store.authorizationStatus == .restricted { store.openLocationSettings() } else { store.requestCurrentLocation() } } label: {
                            settingsLink(store.authorizationStatus == .denied || store.authorizationStatus == .restricted ? "Open location settings" : "Refresh current location", value: nil, symbol: "location.circle")
                        }
                        Text("Forecasts come from Apple Weather. Vane does not request a separate air-quality model.").font(.caption).foregroundStyle(VaneTheme.muted)
                        if let attribution = store.attribution { Link(destination: attribution.legalPageURL) { settingsLink("Apple Weather attribution", value: nil, symbol: "apple.logo") } }
                    }
                    settingsCard("iCloud sync", symbol: "icloud.fill") {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: cloudSyncStatus.availability.symbol)
                                .foregroundStyle(VaneTheme.blue)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(cloudSyncStatus.availability.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(cloudSyncStatus.availability.detail)
                                    .font(.caption)
                                    .foregroundStyle(VaneTheme.muted)
                            }
                        }
                        Button("Check iCloud again") {
                            Task { await cloudSyncStatus.refresh() }
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    settingsCard("Privacy & resets", symbol: "hand.raised.fill") {
                        Text("Your profile, check-ins and saved places use your private iCloud database so they can follow you across Vane apps. Vane does not require a separate account.").font(.caption).foregroundStyle(VaneTheme.muted)
                        Link(destination: URL(string: "https://vane.codearc.studio/privacy/")!) { settingsLink("Privacy policy", value: nil, symbol: "lock.shield") }
                        Link(destination: URL(string: "https://vane.codearc.studio/terms/")!) { settingsLink("Terms", value: nil, symbol: "doc.text") }
                        destructiveButton("Delete check-in history", action: .history)
                        destructiveButton("Reset Sense and start over", action: .sense)
                        destructiveButton("Delete all Vane data", action: .all)
                    }
                    settingsCard("About", symbol: "info.circle.fill") {
                        Link(destination: URL(string: "https://vane.codearc.studio")!) { settingsLink("Vane on the web", value: nil, symbol: "safari") }
                        Link(destination: URL(string: "https://vane.codearc.studio/contact/")!) { settingsLink("Contact Vane", value: nil, symbol: "envelope") }
                        Link(destination: URL(string: "https://codearc.studio")!) { settingsLink("Made by CodeArc.studio", value: nil, symbol: "hammer") }
                        settingsLink("Version", value: version, symbol: "number")
                    }
                }
                .padding(18)
                .padding(.bottom, 70)
                .containerRelativeFrame(.horizontal)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(resetAction?.title ?? "Delete data?", isPresented: Binding(get: { resetAction != nil }, set: { if !$0 { resetAction = nil } }), titleVisibility: .visible) {
            if let resetAction { Button(resetAction.buttonTitle, role: .destructive) { perform(resetAction) } }
            Button("Cancel", role: .cancel) { resetAction = nil }
        } message: { if let resetAction { Text(resetAction.message) } }
        .alert("Allow useful alerts?", isPresented: Binding(get: { pendingNotification != nil }, set: { if !$0 { pendingNotification = nil } })) {
            Button("Not now", role: .cancel) { pendingNotification = nil }
            Button("Continue") { if let pendingNotification { Task { await setNotification(pendingNotification, enabled: true) } }; pendingNotification = nil }
        } message: { Text("Vane will ask iOS for permission so it can send the category you chose. It will not send engagement nudges.") }
        .alert("Vane couldn’t finish that deletion", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK") {} } message: { Text(errorMessage ?? "Please try again.") }
        .task { await cloudSyncStatus.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .CKAccountChanged)) { _ in
            Task { await cloudSyncStatus.refresh() }
        }
    }

    private var appearancePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(AppAppearance.allCases) { appearance in
                    let selected = appearanceRawValue == appearance.rawValue

                    Button {
                        withAnimation(.spring(duration: 0.32, bounce: 0.08)) {
                            automaticSunAppearance = false
                            appearanceRawValue = appearance.rawValue
                        }
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            VStack(spacing: 8) {
                                Image(systemName: appearance.symbol)
                                    .font(.system(size: 20, weight: .semibold))
                                    .symbolRenderingMode(.hierarchical)

                                Text(appearance.title)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, minHeight: 70)

                            if selected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .white.opacity(0.24))
                                    .padding(8)
                            }
                        }
                        .foregroundStyle(selected ? Color.white : VaneTheme.ink)
                        .background {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(selected ? VaneTheme.blue : VaneTheme.ink.opacity(0.055))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(selected ? Color.white.opacity(0.28) : VaneTheme.hairline, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(appearance.title) appearance")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }

            Toggle(isOn: automaticSunAppearanceBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dark after sunset")
                        .font(.subheadline.weight(.medium))
                    Text("Switches to true Dark at sunset and back to Light at sunrise for the forecast location.")
                        .font(.caption)
                        .foregroundStyle(VaneTheme.muted)
                }
            }
            .tint(VaneTheme.blue)

            Text(automaticSunAppearance
                 ? "Following \(store.snapshot.locationName)’s daylight. Vane is currently \(currentAppearance.title). Choosing a mode above turns this off."
                 : "System follows your iPhone. Light and Dark keep Vane in that appearance.")
                .font(.caption)
                .foregroundStyle(VaneTheme.muted)
        }
    }

    private var currentAppearance: AppAppearance {
        AppAppearance(rawValue: appearanceRawValue) ?? .system
    }

    private var automaticSunAppearanceBinding: Binding<Bool> {
        Binding(
            get: { automaticSunAppearance },
            set: { enabled in
                automaticSunAppearance = enabled
                guard enabled,
                      let appearance = AutomaticSunAppearance.appearance(for: store.snapshot) else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    appearanceRawValue = appearance.rawValue
                }
            }
        )
    }

    private func settingsCard<Content: View>(
        _ title: String,
        symbol: String? = nil,
        brandMark: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GlassCard(radius: 26) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 9) {
                    if brandMark {
                        Image("Vane")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 27, height: 16)
                            .foregroundStyle(VaneTheme.blue)
                    } else if let symbol {
                        Image(systemName: symbol)
                            .foregroundStyle(VaneTheme.blue)
                    }

                    Text(title)
                        .font(.headline)
                        .foregroundStyle(VaneTheme.blue)
                }

                content()
            }
            .padding(18)
        }
    }

    private func unitPicker(_ title: String, selection: Binding<String>, values: [(String, String)]) -> some View {
        HStack {
            Text(title).font(.subheadline.weight(.medium))
            Spacer()
            Menu {
                ForEach(values, id: \.0) { value in
                    Button {
                        selection.wrappedValue = value.0
                    } label: {
                        if selection.wrappedValue == value.0 {
                            Label(value.1, systemImage: "checkmark")
                        } else {
                            Text(value.1)
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(values.first(where: { $0.0 == selection.wrappedValue })?.1 ?? "Choose")
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.bold())
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(VaneTheme.blue)
            }
        }.frame(minHeight: 42)
    }

    private func settingsLink(_ title: String, value: String?, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(VaneTheme.blue).frame(width: 24)
            Text(title).font(.subheadline.weight(.medium))
            Spacer()
            if let value { Text(value).font(.caption).foregroundStyle(VaneTheme.muted) }
            if value == nil { Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(VaneTheme.muted) }
        }.foregroundStyle(VaneTheme.ink).frame(minHeight: 42).contentShape(Rectangle())
    }

    private func destructiveButton(_ title: String, action: ResetAction) -> some View {
        Button(role: .destructive) { resetAction = action } label: { Label(title, systemImage: action.symbol).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 42) }
    }

    @ViewBuilder private func notificationToggle(_ category: NotificationCategory, _ title: String, _ detail: String) -> some View {
        Toggle(isOn: Binding(get: { category.value(in: notifications) }, set: { enabled in
            if enabled && notifications.authorizationStatus == .notDetermined { pendingNotification = category }
            else { Task { await setNotification(category, enabled: enabled) } }
        })) { VStack(alignment: .leading, spacing: 2) { Text(title).font(.subheadline.weight(.medium)); Text(detail).font(.caption).foregroundStyle(VaneTheme.muted) } }
            .tint(VaneTheme.blue)
    }

    private func setNotification(_ category: NotificationCategory, enabled: Bool) async {
        switch category {
        case .rain: await notifications.set(enabled, keyPath: \.rainEnabled, snapshot: store.snapshot, samples: guidanceSamples, checkInFrequency: profiles.first?.checkInFrequency ?? .recommended)
        case .preparation: await notifications.set(enabled, keyPath: \.preparationEnabled, snapshot: store.snapshot, samples: guidanceSamples, checkInFrequency: profiles.first?.checkInFrequency ?? .recommended)
        case .snow: await notifications.set(enabled, keyPath: \.snowEnabled, snapshot: store.snapshot, samples: guidanceSamples, checkInFrequency: profiles.first?.checkInFrequency ?? .recommended)
        case .severe: await notifications.set(enabled, keyPath: \.severeEnabled, snapshot: store.snapshot, samples: guidanceSamples, checkInFrequency: profiles.first?.checkInFrequency ?? .recommended)
        case .uv: await notifications.set(enabled, keyPath: \.uvEnabled, snapshot: store.snapshot, samples: guidanceSamples, checkInFrequency: profiles.first?.checkInFrequency ?? .recommended)
        case .morning: await notifications.set(enabled, keyPath: \.morningEnabled, snapshot: store.snapshot, samples: guidanceSamples, checkInFrequency: profiles.first?.checkInFrequency ?? .recommended)
        case .tomorrow: await notifications.set(enabled, keyPath: \.tomorrowEnabled, snapshot: store.snapshot, samples: guidanceSamples, checkInFrequency: profiles.first?.checkInFrequency ?? .recommended)
        case .smartCheckIn: await notifications.set(enabled, keyPath: \.smartCheckInEnabled, snapshot: store.snapshot, samples: guidanceSamples, checkInFrequency: profiles.first?.checkInFrequency ?? .recommended)
        }
    }

    private var notificationNote: String {
        if notifications.authorizationStatus == .denied { return "Notifications are off in iPhone Settings." }
        if notifications.pendingCount > 0 { return "\(notifications.pendingCount) useful reminder\(notifications.pendingCount == 1 ? "" : "s") scheduled from the latest forecast." }
        return "Local reminders are rebuilt for the active forecast location. Morning and evening times follow that location’s local clock."
    }
    private var liveActivitiesBinding: Binding<Bool> {
        Binding(
            get: { liveActivitiesEnabled },
            set: { enabled in
                liveActivitiesEnabled = enabled
                Task {
                    if enabled {
                        await WeatherLiveActivityManager.shared.synchronize(snapshot: store.snapshot)
                    } else {
                        await WeatherLiveActivityManager.shared.endAll()
                    }
                }
            }
        )
    }
    private var frequencyBinding: Binding<String> { Binding(get: { profiles.first?.checkInFrequencyRaw ?? CheckInFrequency.recommended.rawValue }, set: { value in profiles.first?.checkInFrequencyRaw = value; try? modelContext.save() }) }
    private var guidanceSamples: [GuidanceSample] { checkIns.compactMap { $0.guidanceSample() } }
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—" }

    private func perform(_ action: ResetAction) {
        do {
            switch action {
            case .history: try modelContext.delete(model: WeatherCheckIn.self)
            case .sense:
                try modelContext.delete(model: WeatherCheckIn.self); try modelContext.delete(model: WeatherProfile.self); modelContext.insert(WeatherProfile())
            case .all:
                try modelContext.delete(model: WeatherCheckIn.self); try modelContext.delete(model: WeatherProfile.self); try modelContext.delete(model: SavedPlace.self); modelContext.insert(WeatherProfile()); store.resetSelection()
            }
            try modelContext.save()
            if action == .sense || action == .all {
                hasCompletedOnboarding = false
            }
            if case .all = action {
                notifications.resetPreferences()
                ["appearance", "temperatureUnit", "windUnit", "pressureUnit", "precipitationUnit"].forEach(UserDefaults.standard.removeObject(forKey:))
                Task { await notifications.cancelAllVaneNotifications() }
            }
        } catch { errorMessage = "Your data could not be removed right now. Please try again." }
        resetAction = nil
    }
}

private enum NotificationCategory {
    case severe, rain, snow, uv, preparation, morning, tomorrow, smartCheckIn
    func value(in manager: NotificationManager) -> Bool {
        switch self { case .severe: manager.severeEnabled; case .rain: manager.rainEnabled; case .snow: manager.snowEnabled; case .uv: manager.uvEnabled; case .preparation: manager.preparationEnabled; case .morning: manager.morningEnabled; case .tomorrow: manager.tomorrowEnabled; case .smartCheckIn: manager.smartCheckInEnabled }
    }
}

private enum ResetAction: Equatable {
    case history, sense, all
    var title: String { self == .history ? "Delete check-in history?" : self == .sense ? "Reset what Sense has learned?" : "Delete all Vane data?" }
    var buttonTitle: String { self == .history ? "Delete history" : self == .sense ? "Reset Sense" : "Delete all data" }
    var symbol: String { self == .history ? "trash" : self == .sense ? "arrow.counterclockwise" : "exclamationmark.triangle" }
    var message: String {
        switch self {
        case .history: "This removes each weather moment from Vane on your iCloud devices. Your starting preference and saved places remain."
        case .sense: "This removes what Sense has learned from Vane on your iCloud devices and reopens onboarding so you can choose a fresh starting preference. Saved places remain."
        case .all: "This removes check-ins, your Sense profile and saved places from Vane on your iCloud devices. App preferences and pending notifications are also cleared on this iPhone. Onboarding will begin again."
        }
    }
}
