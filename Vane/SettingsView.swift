import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("appearance") private var appearanceRawValue = AppAppearance.system.rawValue
    @AppStorage("temperatureUnit") private var temperatureUnitRaw = TemperatureUnitPreference.fahrenheit.rawValue
    @AppStorage("windUnit") private var windUnitRaw = WindUnitPreference.milesPerHour.rawValue
    @AppStorage("pressureUnit") private var pressureUnitRaw = PressureUnitPreference.hectopascals.rawValue
    @AppStorage("precipitationUnit") private var precipitationUnitRaw = PrecipitationUnitPreference.inches.rawValue
    @Query private var profiles: [WeatherProfile]
    @Query private var checkIns: [WeatherCheckIn]
    @Query private var places: [SavedPlace]
    @Bindable var store: WeatherStore
    @Bindable var notifications: NotificationManager
    @State private var resetAction: ResetAction?
    @State private var pendingNotification: NotificationCategory?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: $appearanceRawValue) { ForEach(AppAppearance.allCases) { Text($0.title).tag($0.rawValue) } }
                    .pickerStyle(.segmented)
            }
            Section("Weather units") {
                Picker("Temperature", selection: $temperatureUnitRaw) { ForEach(TemperatureUnitPreference.allCases) { Text($0.title).tag($0.rawValue) } }
                Picker("Wind", selection: $windUnitRaw) { ForEach(WindUnitPreference.allCases) { Text($0.title).tag($0.rawValue) } }
                Picker("Pressure", selection: $pressureUnitRaw) { ForEach(PressureUnitPreference.allCases) { Text($0.title).tag($0.rawValue) } }
                Picker("Precipitation", selection: $precipitationUnitRaw) { ForEach(PrecipitationUnitPreference.allCases) { Text($0.title).tag($0.rawValue) } }
            }
            Section("Sense") {
                Picker("Temperature used by Sense", selection: temperatureBasisBinding) { Text("Feels Like").tag(true); Text("Actual").tag(false) }
                Picker("Check-in frequency", selection: frequencyBinding) { ForEach(CheckInFrequency.allCases) { Text($0.title).tag($0.rawValue) } }
                Text("Frequency changes how often useful opportunities appear. Vane does not create streaks or daily obligations.").font(.caption).foregroundStyle(VaneTheme.muted)
                NavigationLink("Check-in history (\(checkIns.count))") { CheckInHistoryView() }
            }
            Section("Useful alerts") {
                notificationToggle(.severe, "Severe weather", "Official alerts remain objective")
                notificationToggle(.rain, "Rain", "When rain becomes likely")
                notificationToggle(.snow, "Snow", "A distinct snow heads-up")
                notificationToggle(.uv, "Strong UV", "Objective sun safety")
                notificationToggle(.preparation, "Temperature changes", "Large shifts in the current forecast")
                notificationToggle(.morning, "Morning forecast", "A daily forecast, only if enabled")
                notificationToggle(.tomorrow, "Tomorrow preview", "An evening look ahead")
                notificationToggle(.smartCheckIn, "Smart check-ins", "Only unfamiliar or seasonally useful weather")
                if notifications.authorizationStatus == .denied { Button("Open iPhone Settings") { notifications.openSettings() } }
                Text(notificationNote).font(.caption).foregroundStyle(VaneTheme.muted)
            }
            Section("Location and weather data") {
                Button(store.authorizationStatus == .denied || store.authorizationStatus == .restricted ? "Open location settings" : "Use current location") {
                    if store.authorizationStatus == .denied || store.authorizationStatus == .restricted { store.openLocationSettings() } else { store.requestCurrentLocation() }
                }
                if let attribution = store.attribution { Link("\(attribution.serviceName) attribution", destination: attribution.legalPageURL) }
            }
            Section("Privacy and data") {
                Text("Personal learning is stored privately on this device today. No account is required.").font(.caption).foregroundStyle(VaneTheme.muted)
                Link("Privacy policy", destination: URL(string: "https://vane.codearc.studio/privacy/")!)
                Link("Terms", destination: URL(string: "https://vane.codearc.studio/terms/")!)
                Button("Delete check-in history", role: .destructive) { resetAction = .history }
                Button("Reset what Sense has learned", role: .destructive) { resetAction = .sense }
                Button("Delete all Vane data", role: .destructive) { resetAction = .all }
            }
            Section("About") {
                Link("Vane on the web", destination: URL(string: "https://vane.codearc.studio")!)
                Link("Contact Vane", destination: URL(string: "https://vane.codearc.studio/contact/")!)
                Link("Made by CodeArc.studio", destination: URL(string: "https://codearc.studio")!)
                LabeledContent("Version", value: version)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AtmosphericBackground(condition: store.snapshot.isPlaceholder ? nil : store.snapshot.current))
        .navigationTitle("Settings")
        .confirmationDialog(resetAction?.title ?? "Delete data?", isPresented: Binding(get: { resetAction != nil }, set: { if !$0 { resetAction = nil } }), titleVisibility: .visible) {
            if let resetAction { Button(resetAction.buttonTitle, role: .destructive) { perform(resetAction) } }
            Button("Cancel", role: .cancel) { resetAction = nil }
        } message: { if let resetAction { Text(resetAction.message) } }
        .alert("Allow useful alerts?", isPresented: Binding(get: { pendingNotification != nil }, set: { if !$0 { pendingNotification = nil } })) {
            Button("Not now", role: .cancel) { pendingNotification = nil }
            Button("Continue") { if let pendingNotification { Task { await setNotification(pendingNotification, enabled: true) } }; pendingNotification = nil }
        } message: { Text("Vane will ask iOS for permission so it can send the category you chose. It will not send engagement nudges.") }
        .alert("Vane couldn’t finish that deletion", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK") {} } message: { Text(errorMessage ?? "Please try again.") }
    }

    @ViewBuilder private func notificationToggle(_ category: NotificationCategory, _ title: String, _ detail: String) -> some View {
        Toggle(isOn: Binding(get: { category.value(in: notifications) }, set: { enabled in
            if enabled && notifications.authorizationStatus == .notDetermined { pendingNotification = category }
            else { Task { await setNotification(category, enabled: enabled) } }
        })) { VStack(alignment: .leading) { Text(title); Text(detail).font(.caption).foregroundStyle(VaneTheme.muted) } }
    }

    private func setNotification(_ category: NotificationCategory, enabled: Bool) async {
        switch category {
        case .rain: await notifications.set(enabled, keyPath: \.rainEnabled, snapshot: store.snapshot)
        case .preparation: await notifications.set(enabled, keyPath: \.preparationEnabled, snapshot: store.snapshot)
        case .snow: await notifications.set(enabled, keyPath: \.snowEnabled, snapshot: store.snapshot)
        case .severe: await notifications.set(enabled, keyPath: \.severeEnabled, snapshot: store.snapshot)
        case .uv: await notifications.set(enabled, keyPath: \.uvEnabled, snapshot: store.snapshot)
        case .morning: await notifications.set(enabled, keyPath: \.morningEnabled, snapshot: store.snapshot)
        case .tomorrow: await notifications.set(enabled, keyPath: \.tomorrowEnabled, snapshot: store.snapshot)
        case .smartCheckIn: await notifications.set(enabled, keyPath: \.smartCheckInEnabled, snapshot: store.snapshot)
        }
    }

    private var notificationNote: String {
        if notifications.authorizationStatus == .denied { return "Notifications are off in iPhone Settings." }
        if notifications.pendingCount > 0 { return "\(notifications.pendingCount) useful reminder\(notifications.pendingCount == 1 ? "" : "s") scheduled from the latest forecast." }
        return "Local reminders are recalculated when Vane receives a fresh forecast. Dependable background refresh will need a server-backed weather pipeline before Vane promises it."
    }
    private var temperatureBasisBinding: Binding<Bool> { Binding(get: { profiles.first?.usesFeelsLikeTemperature ?? true }, set: { value in profiles.first?.usesFeelsLikeTemperature = value; try? modelContext.save() }) }
    private var frequencyBinding: Binding<String> { Binding(get: { profiles.first?.checkInFrequencyRaw ?? CheckInFrequency.recommended.rawValue }, set: { value in profiles.first?.checkInFrequencyRaw = value; try? modelContext.save() }) }
    private var version: String { "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"))" }

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
        } catch { errorMessage = error.localizedDescription }
        resetAction = nil
    }
}

private enum NotificationCategory {
    case severe, rain, snow, uv, preparation, morning, tomorrow, smartCheckIn
    func value(in manager: NotificationManager) -> Bool {
        switch self { case .severe: manager.severeEnabled; case .rain: manager.rainEnabled; case .snow: manager.snowEnabled; case .uv: manager.uvEnabled; case .preparation: manager.preparationEnabled; case .morning: manager.morningEnabled; case .tomorrow: manager.tomorrowEnabled; case .smartCheckIn: manager.smartCheckInEnabled }
    }
}

private enum ResetAction {
    case history, sense, all
    var title: String { self == .history ? "Delete check-in history?" : self == .sense ? "Reset what Sense has learned?" : "Delete all Vane data?" }
    var buttonTitle: String { self == .history ? "Delete history" : self == .sense ? "Reset Sense" : "Delete all data" }
    var message: String {
        switch self {
        case .history: "This removes each weather moment from this iPhone. Your starting preference and saved places remain."
        case .sense: "This removes what Sense has learned from your check-ins on this iPhone. Saved places remain."
        case .all: "This removes check-ins, your Sense profile, and all saved places from this iPhone."
        }
    }
}
