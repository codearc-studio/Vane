import Foundation
import Observation
import UserNotifications

struct PlannedNotification: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let body: String
    let date: Date
}

enum NotificationPlanner {
    static func plan(
        snapshot: ForecastSnapshot,
        now: Date = .now,
        rainEnabled: Bool,
        preparationEnabled: Bool
    ) -> [PlannedNotification] {
        guard !snapshot.isSample else { return [] }
        var events: [PlannedNotification] = []

        if rainEnabled,
           let rain = snapshot.hourly.first(where: { $0.date > now.addingTimeInterval(20 * 60) && $0.precipitationChance >= 0.55 }) {
            let alertDate = max(rain.date.addingTimeInterval(-30 * 60), now.addingTimeInterval(60))
            events.append(PlannedNotification(
                id: "vane.rain.\(Int(rain.date.timeIntervalSince1970))",
                title: "Rain may start soon",
                body: "Rain is likely around \(rain.date.formatted(.dateTime.hour())). You may want a rain layer.",
                date: alertDate
            ))
        }

        if preparationEnabled,
           let shift = snapshot.hourly.prefix(16).first(where: { abs($0.temperature - snapshot.current.temperature) >= 12 && $0.date > now.addingTimeInterval(60 * 60) }) {
            let warming = shift.temperature > snapshot.current.temperature
            events.append(PlannedNotification(
                id: "vane.shift.\(Int(shift.date.timeIntervalSince1970))",
                title: warming ? "It will feel different later" : "A cooler change is coming",
                body: "Temperatures move toward \(shift.temperature.degrees) by \(shift.date.formatted(.dateTime.hour())).",
                date: max(shift.date.addingTimeInterval(-60 * 60), now.addingTimeInterval(60))
            ))
        }

        if preparationEnabled,
           snapshot.current.uvIndex >= 6,
           Calendar.current.component(.hour, from: now) < 16 {
            events.append(PlannedNotification(
                id: "vane.uv.\(Calendar.current.startOfDay(for: now).timeIntervalSince1970)",
                title: "Strong sun today",
                body: "UV is \(snapshot.current.uvIndex). Sun protection will help if you are outside.",
                date: now.addingTimeInterval(2 * 60)
            ))
        }

        return Array(events.sorted { $0.date < $1.date }.prefix(2))
    }
}

@MainActor
@Observable
final class NotificationManager {
    var authorizationStatus: UNAuthorizationStatus = .notDetermined
    var pendingCount = 0

    var rainEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "rainNotificationsEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "rainNotificationsEnabled") }
    }

    var preparationEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "preparationNotificationsEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "preparationNotificationsEnabled") }
    }

    func refreshStatus() async {
        authorizationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        pendingCount = await UNUserNotificationCenter.current().pendingNotificationRequests().filter { $0.identifier.hasPrefix("vane.") }.count
    }

    func requestUsefulAlerts() async {
        await refreshStatus()
        guard authorizationStatus == .notDetermined else { return }
        let allowed = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        if allowed {
            rainEnabled = true
            preparationEnabled = true
        }
        await refreshStatus()
    }

    func setRainEnabled(_ enabled: Bool, snapshot: ForecastSnapshot) async {
        await refreshStatus()
        guard !enabled || authorizationStatus == .authorized || authorizationStatus == .provisional else {
            rainEnabled = false
            return
        }
        rainEnabled = enabled
        await schedule(snapshot: snapshot)
    }

    func setPreparationEnabled(_ enabled: Bool, snapshot: ForecastSnapshot) async {
        await refreshStatus()
        guard !enabled || authorizationStatus == .authorized || authorizationStatus == .provisional else {
            preparationEnabled = false
            return
        }
        preparationEnabled = enabled
        await schedule(snapshot: snapshot)
    }

    func schedule(snapshot: ForecastSnapshot) async {
        let center = UNUserNotificationCenter.current()
        let oldRequests = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix("vane.") }
        center.removePendingNotificationRequests(withIdentifiers: oldRequests.map(\.identifier))

        guard authorizationStatus == .authorized || authorizationStatus == .provisional else {
            pendingCount = 0
            return
        }

        for event in NotificationPlanner.plan(snapshot: snapshot, rainEnabled: rainEnabled, preparationEnabled: preparationEnabled) {
            let content = UNMutableNotificationContent()
            content.title = event.title
            content.body = event.body
            content.sound = .default
            let interval = max(1, event.date.timeIntervalSinceNow)
            let request = UNNotificationRequest(identifier: event.id, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
            try? await center.add(request)
        }
        await refreshStatus()
    }

}
