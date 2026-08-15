//
//  ContentView.swift
//  Vane
//
//  Created by Makai O'Neill on 8/13/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("appearance") private var appearanceRawValue = AppAppearance.system.rawValue
    @State private var weatherStore = WeatherStore()
    @State private var notificationManager = NotificationManager()

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
    }
}

struct MainTabView: View {
    @Bindable var weatherStore: WeatherStore
    @Bindable var notificationManager: NotificationManager
    @State private var selectedTab = ProcessInfo.processInfo.environment["VANE_SCREENSHOT_TAB"] == "sense" ? 1 : ProcessInfo.processInfo.environment["VANE_SCREENSHOT_TAB"] == "settings" ? 2 : 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { WeatherHomeView(store: weatherStore) }
                .tabItem { Label("Forecast", systemImage: "cloud.sun.fill") }
                .tag(0)
            NavigationStack { SenseView(snapshot: weatherStore.snapshot) }
                .tabItem { Label("Sense", systemImage: "sparkles") }
                .tag(1)
            NavigationStack { SettingsView(store: weatherStore, notifications: notificationManager) }
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(2)
        }
        .tint(VaneTheme.blue)
        .task { await weatherStore.start() }
        .task { await notificationManager.refreshStatus() }
        .onChange(of: weatherStore.snapshot.updatedAt) { _, _ in
            Task { await notificationManager.schedule(snapshot: weatherStore.snapshot) }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [WeatherProfile.self, WeatherCheckIn.self, SavedPlace.self], inMemory: true)
}
