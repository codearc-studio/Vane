//
//  ContentView.swift
//  Vane
//
//  Created by Makai O'Neill on 8/13/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("appearance") private var appearanceRawValue = AppAppearance.system.rawValue
    @AppStorage(AutomaticSunAppearance.enabledKey) private var automaticSunAppearance = false
    @State private var weatherStore = WeatherStore.shared
    @State private var notificationManager = NotificationManager()
    @State private var router = VaneRouter()
    @State private var showStorageRecovery = false
    var storageRecoveryMessage: String?

    init(storageRecoveryMessage: String? = nil) {
        self.storageRecoveryMessage = storageRecoveryMessage
    }

    var body: some View {
        rootContent
        .preferredColorScheme((AppAppearance(rawValue: appearanceRawValue) ?? .system).colorScheme)
        .onOpenURL { router.open($0) }
        .onReceive(NotificationCenter.default.publisher(for: .vaneNotificationRoute)) { notification in
            if let url = notification.object as? URL {
                _ = VaneNotificationDelegate.takePendingRoute()
                router.open(url)
            }
        }
        .task {
            if let url = VaneNotificationDelegate.takePendingRoute() { router.open(url) }
        }
        .task { DataCoordinator.prepare(context: modelContext) }
        .task(id: automaticAppearanceUpdateID) { updateAutomaticAppearance() }
        .task(id: nextAutomaticAppearanceTransition) {
            guard automaticSunAppearance, let transition = nextAutomaticAppearanceTransition else { return }
            try? await Task.sleep(until: .now + .seconds(max(0, transition.timeIntervalSinceNow + 1)), clock: .continuous)
            guard !Task.isCancelled else { return }
            updateAutomaticAppearance()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { updateAutomaticAppearance() }
        }
        .onAppear { showStorageRecovery = storageRecoveryMessage != nil }
        .alert("Saved data needs attention", isPresented: $showStorageRecovery) {
            Button("Continue temporarily") { }
        } message: { Text(storageRecoveryMessage ?? "") }
    }

    private var automaticAppearanceUpdateID: String {
        "\(automaticSunAppearance)|\(weatherStore.snapshot.updatedAt.timeIntervalSinceReferenceDate)"
    }

    private var nextAutomaticAppearanceTransition: Date? {
        guard automaticSunAppearance else { return nil }
        return AutomaticSunAppearance.nextTransition(for: weatherStore.snapshot)
    }

    private func updateAutomaticAppearance() {
        guard automaticSunAppearance,
              let appearance = AutomaticSunAppearance.appearance(for: weatherStore.snapshot) else { return }
        appearanceRawValue = appearance.rawValue
    }

    @ViewBuilder
    private var rootContent: some View {
#if DEBUG
        if ProcessInfo.processInfo.environment["VANE_SCREENSHOT_WIDGETS"] == "1" {
            WidgetGalleryView()
        } else {
            appContent
        }
#else
        appContent
#endif
    }

    @ViewBuilder
    private var appContent: some View {
        if hasCompletedOnboarding {
            MainTabView(weatherStore: weatherStore, notificationManager: notificationManager, router: router)
        } else {
            OnboardingView(store: weatherStore, notifications: notificationManager) {
                withAnimation(.easeInOut(duration: 0.45)) {
                    hasCompletedOnboarding = true
                }
            }
        }
    }
}

struct MainTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \WeatherCheckIn.createdAt, order: .reverse) private var checkIns: [WeatherCheckIn]
    @Query private var profiles: [WeatherProfile]
    @AppStorage("temperatureUnit") private var temperatureUnitRaw = TemperatureUnitPreference.localizedDefault.rawValue
    @AppStorage("windUnit") private var windUnitRaw = WindUnitPreference.localizedDefault.rawValue
    @AppStorage("pressureUnit") private var pressureUnitRaw = PressureUnitPreference.localizedDefault.rawValue
    @AppStorage("precipitationUnit") private var precipitationUnitRaw = PrecipitationUnitPreference.localizedDefault.rawValue
    @Bindable var weatherStore: WeatherStore
    @Bindable var notificationManager: NotificationManager
    @Bindable var router: VaneRouter
    @State private var selectedTab = ProcessInfo.processInfo.environment["VANE_SCREENSHOT_TAB"] == "sense" || ProcessInfo.processInfo.environment["VANE_SCREENSHOT_TAB"] == "settings" ? 1 : 0
    @State private var showSenseFromWidget = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { WeatherHomeView(store: weatherStore, router: router) }
                .tabItem { Label("Weather", systemImage: "cloud.sun.fill") }
                .tag(0)
            NavigationStack {
                Group {
                    if ProcessInfo.processInfo.environment["VANE_SCREENSHOT_TAB"] == "settings" {
                        SettingsView(store: weatherStore, notifications: notificationManager)
                    } else if ProcessInfo.processInfo.environment["VANE_SCREENSHOT_TAB"] == "sense" {
                        SenseView(snapshot: weatherStore.snapshot)
                    } else {
                        YouView(store: weatherStore, notifications: notificationManager)
                    }
                }
                .navigationDestination(isPresented: $showSenseFromWidget) {
                    SenseView(snapshot: weatherStore.snapshot)
                }
            }
                .tabItem {
                    Label("Sense", image: "VaneTab")
                }
                .tag(1)
        }
        .tint(VaneTheme.blue)
        .task { await weatherStore.start() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(600))
                guard !Task.isCancelled else { return }
                await weatherStore.refreshIfNeeded()
            }
        }
        .task { await notificationManager.refreshStatus() }
        .task(id: widgetRefreshID) {
            let guidance = PersonalGuidance(snapshot: weatherStore.snapshot, profile: profiles.first, checkIns: checkIns)
            WidgetBridge.publish(snapshot: weatherStore.snapshot, guidance: guidance)
        }
        .task(id: router.sequence) {
            if router.sequence == 0,
               let screenshotTab = ProcessInfo.processInfo.environment["VANE_SCREENSHOT_TAB"],
               screenshotTab == "sense" || screenshotTab == "settings" {
                selectedTab = 1
                return
            }
            if router.destination == .sense {
                selectedTab = 1
                showSenseFromWidget = true
            } else {
                selectedTab = 0
                showSenseFromWidget = false
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await weatherStore.refreshIfNeeded(maxAge: 5 * 60) }
        }
        .onChange(of: weatherStore.snapshot.updatedAt) { _, _ in
            let samples = checkIns.compactMap { $0.guidanceSample(usesFeelsLikeTemperature: profiles.first?.usesFeelsLikeTemperature ?? true) }
            Task { await notificationManager.schedule(snapshot: weatherStore.snapshot, samples: samples, checkInFrequency: profiles.first?.checkInFrequency ?? .recommended) }
        }
    }

    private var widgetRefreshID: String {
        let profile = profiles.first
        let latestCheckIn = checkIns.first?.createdAt.timeIntervalSinceReferenceDate ?? 0
        return [
            String(weatherStore.snapshot.updatedAt.timeIntervalSinceReferenceDate),
            temperatureUnitRaw,
            windUnitRaw,
            pressureUnitRaw,
            precipitationUnitRaw,
            String(checkIns.count),
            String(latestCheckIn),
            String(profile?.temperaturePreference ?? 0),
            String(profile?.windSensitivity ?? 0.5),
            String(profile?.humiditySensitivity ?? 0.5),
            String(profile?.usesFeelsLikeTemperature ?? true)
        ].joined(separator: "|")
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [WeatherProfile.self, WeatherCheckIn.self, SavedPlace.self], inMemory: true)
}
