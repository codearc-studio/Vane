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
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("appearance") private var appearanceRawValue = AppAppearance.system.rawValue
    @State private var weatherStore = WeatherStore()
    @State private var notificationManager = NotificationManager()
    @State private var showStorageRecovery = false
    var storageRecoveryMessage: String?

    init(storageRecoveryMessage: String? = nil) {
        self.storageRecoveryMessage = storageRecoveryMessage
    }

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                MainTabView(weatherStore: weatherStore, notificationManager: notificationManager)
            } else {
                OnboardingView(store: weatherStore, notifications: notificationManager) {
                    withAnimation(.easeInOut(duration: 0.45)) {
                        hasCompletedOnboarding = true
                    }
                }
            }
        }
        .preferredColorScheme((AppAppearance(rawValue: appearanceRawValue) ?? .system).colorScheme)
        .task { DataCoordinator.prepare(context: modelContext) }
        .onAppear { showStorageRecovery = storageRecoveryMessage != nil }
        .alert("Saved data needs attention", isPresented: $showStorageRecovery) {
            Button("Continue temporarily") { }
        } message: { Text(storageRecoveryMessage ?? "") }
    }
}

struct MainTabView: View {
    @Query(sort: \WeatherCheckIn.createdAt, order: .reverse) private var checkIns: [WeatherCheckIn]
    @Query private var profiles: [WeatherProfile]
    @Bindable var weatherStore: WeatherStore
    @Bindable var notificationManager: NotificationManager
    @State private var selectedTab = ProcessInfo.processInfo.environment["VANE_SCREENSHOT_TAB"] == "sense" || ProcessInfo.processInfo.environment["VANE_SCREENSHOT_TAB"] == "settings" ? 1 : 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { WeatherHomeView(store: weatherStore) }
                .tabItem { Label("Weather", systemImage: "cloud.sun.fill") }
                .tag(0)
            NavigationStack {
                if ProcessInfo.processInfo.environment["VANE_SCREENSHOT_TAB"] == "settings" {
                    SettingsView(store: weatherStore, notifications: notificationManager)
                } else if ProcessInfo.processInfo.environment["VANE_SCREENSHOT_TAB"] == "sense" {
                    SenseView(snapshot: weatherStore.snapshot)
                } else {
                    YouView(store: weatherStore, notifications: notificationManager)
                }
            }
                .tabItem {
                    Label("Sense", image: "VaneTab")
                }
                .tag(1)
        }
        .tint(VaneTheme.blue)
        .task { await weatherStore.start() }
        .task { await notificationManager.refreshStatus() }
        .onChange(of: weatherStore.snapshot.updatedAt) { _, _ in
            let samples = checkIns.compactMap { checkIn -> GuidanceSample? in
                guard let response = checkIn.feelResponse else { return nil }
                return GuidanceSample(date: checkIn.createdAt, apparentTemperature: checkIn.apparentTemperature, humidity: checkIn.humidity, windSpeed: checkIn.windSpeed, response: response, contexts: checkIn.contexts, cloudCover: checkIn.cloudCover ?? 0.5, isTravel: checkIn.isTravel)
            }
            Task { await notificationManager.schedule(snapshot: weatherStore.snapshot, samples: samples, checkInFrequency: profiles.first?.checkInFrequency ?? .recommended) }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [WeatherProfile.self, WeatherCheckIn.self, SavedPlace.self], inMemory: true)
}
