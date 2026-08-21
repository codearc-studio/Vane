//
//  VaneApp.swift
//  Vane
//
//  Created by Makai O'Neill on 8/13/26.
//

import SwiftUI
import SwiftData
import OSLog
import BackgroundTasks
import UserNotifications

extension Notification.Name {
    static let vaneNotificationRoute = Notification.Name("vane.notification.route")
}

final class VaneNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = VaneNotificationDelegate()
    private static let pendingRouteKey = "vane.notification.pendingRoute"

    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let openAlert = UNNotificationAction(identifier: "VANE_VIEW_ALERT", title: "View in Vane", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: VaneNotificationRoute.officialAlertCategory, actions: [openAlert], intentIdentifiers: [])
        ])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let value = response.notification.request.content.userInfo[VaneNotificationRoute.userInfoKey] as? String,
              let url = URL(string: value) else { return }
        UserDefaults.standard.set(value, forKey: Self.pendingRouteKey)
        await MainActor.run {
            NotificationCenter.default.post(name: .vaneNotificationRoute, object: url)
        }
    }

    static func takePendingRoute() -> URL? {
        let defaults = UserDefaults.standard
        guard let value = defaults.string(forKey: pendingRouteKey) else { return nil }
        defaults.removeObject(forKey: pendingRouteKey)
        return URL(string: value)
    }
}

@main
struct VaneApp: App {
    private let modelContainer: ModelContainer
    private let storageRecoveryMessage: String?

    init() {
        WatchConnectivityBridge.shared.activate()
        VaneNotificationDelegate.shared.configure()
        let schema = Schema(versionedSchema: VaneSchemaV1.self)
        let persistent = VaneCloudKit.appConfiguration(schema: schema)
        do {
            modelContainer = try ModelContainer(for: schema, migrationPlan: VaneMigrationPlan.self, configurations: [persistent])
            storageRecoveryMessage = nil
        } catch {
            Logger(subsystem: "studio.codearc.Vane", category: "Storage").error("Persistent store failed to open: \(error.localizedDescription, privacy: .public)")
            do {
                modelContainer = try ModelContainer(for: schema, migrationPlan: VaneMigrationPlan.self, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
                storageRecoveryMessage = "Vane could not open its private synced data. A temporary session is available for viewing weather, but new check-ins will not be kept after the app closes. Contact Vane support before making changes to the app or its data."
            } catch {
                preconditionFailure("Vane could not create even a temporary data store: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(storageRecoveryMessage: storageRecoveryMessage)
        }
        .modelContainer(modelContainer)
        .backgroundTask(.appRefresh(WeatherStore.backgroundRefreshIdentifier)) {
            await WeatherStore.shared.performBackgroundRefresh()
        }
    }
}
