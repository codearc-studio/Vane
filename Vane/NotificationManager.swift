import Foundation
import Observation
import UIKit
import UserNotifications

struct PlannedNotification: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let body: String
    let date: Date
}

enum NotificationPlanner {
    static func plan(snapshot: ForecastSnapshot, now: Date = .now, rainEnabled: Bool, preparationEnabled: Bool, snowEnabled: Bool = true, severeEnabled: Bool = true, uvEnabled: Bool = true, morningEnabled: Bool = false, tomorrowEnabled: Bool = false) -> [PlannedNotification] {
        guard !snapshot.isSample, !snapshot.isPlaceholder else { return [] }
        var events: [PlannedNotification] = []
        if severeEnabled, let alert = snapshot.alerts.first {
            events.append(.init(id: "vane.severe.\(alert.id.hashValue)", title: "Official weather alert", body: "\(alert.severity): \(alert.summary)", date: now.addingTimeInterval(60)))
        }
        if snowEnabled, let snow = snapshot.hourly.first(where: { $0.date > now.addingTimeInterval(1_200) && $0.symbolName.contains("snow") }) {
            events.append(.init(id: "vane.snow.\(Int(snow.date.timeIntervalSince1970))", title: "Snow may start soon", body: "Snow is possible around \(snow.date.formatted(.dateTime.hour())).", date: max(snow.date.addingTimeInterval(-1_800), now.addingTimeInterval(60))))
        } else if rainEnabled, let rain = snapshot.hourly.first(where: { $0.date > now.addingTimeInterval(1_200) && $0.precipitationChance >= 0.55 }) {
            events.append(.init(id: "vane.rain.\(Int(rain.date.timeIntervalSince1970))", title: "Rain may start soon", body: "Rain is likely around \(rain.date.formatted(.dateTime.hour())). You may want a rain layer.", date: max(rain.date.addingTimeInterval(-1_800), now.addingTimeInterval(60))))
        }
        if preparationEnabled, let shift = snapshot.hourly.prefix(16).first(where: { abs($0.temperature - snapshot.current.temperature) >= 12 && $0.date > now.addingTimeInterval(3_600) }) {
            events.append(.init(id: "vane.shift.\(Int(shift.date.timeIntervalSince1970))", title: shift.temperature > snapshot.current.temperature ? "It will feel different later" : "A cooler change is coming", body: "Temperatures move toward \(shift.temperature.degrees) by \(shift.date.formatted(.dateTime.hour())).", date: max(shift.date.addingTimeInterval(-3_600), now.addingTimeInterval(60))))
        }
        if uvEnabled, snapshot.current.uvIndex >= 6, Calendar.current.component(.hour, from: now) < 16 {
            events.append(.init(id: "vane.uv.\(Int(Calendar.current.startOfDay(for: now).timeIntervalSince1970))", title: "Strong sun today", body: "UV is \(snapshot.current.uvIndex). Sun protection will help if you are outside.", date: now.addingTimeInterval(120)))
        }
        if morningEnabled, let tomorrowMorning = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 7, minute: 30), matchingPolicy: .nextTime), let today = snapshot.daily.first {
            events.append(.init(id: "vane.morning.\(Int(tomorrowMorning.timeIntervalSince1970))", title: "Today’s weather", body: "\(today.condition), with a high of \(today.high.degrees) and low of \(today.low.degrees).", date: tomorrowMorning))
        }
        if tomorrowEnabled, let evening = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 19), matchingPolicy: .nextTime), snapshot.daily.count > 1 {
            let tomorrow = snapshot.daily[1]
            events.append(.init(id: "vane.tomorrow.\(Int(evening.timeIntervalSince1970))", title: "Tomorrow at a glance", body: "\(tomorrow.condition), \(tomorrow.low.degrees) to \(tomorrow.high.degrees).", date: evening))
        }
        return Array(events.filter { $0.date > now }.sorted { lhs, rhs in
            if lhs.id.contains("severe") != rhs.id.contains("severe") { return lhs.id.contains("severe") }
            return lhs.date < rhs.date
        }.prefix(5))
    }
}

@MainActor
@Observable
final class NotificationManager {
    var authorizationStatus: UNAuthorizationStatus = .notDetermined
    var pendingCount = 0
    private let defaults = UserDefaults.standard

    var rainEnabled: Bool { get { defaults.bool(forKey: "rainNotificationsEnabled") } set { defaults.set(newValue, forKey: "rainNotificationsEnabled") } }
    var preparationEnabled: Bool { get { defaults.bool(forKey: "preparationNotificationsEnabled") } set { defaults.set(newValue, forKey: "preparationNotificationsEnabled") } }
    var snowEnabled: Bool { get { defaults.object(forKey: "snowNotificationsEnabled") == nil || defaults.bool(forKey: "snowNotificationsEnabled") } set { defaults.set(newValue, forKey: "snowNotificationsEnabled") } }
    var severeEnabled: Bool { get { defaults.object(forKey: "severeNotificationsEnabled") == nil || defaults.bool(forKey: "severeNotificationsEnabled") } set { defaults.set(newValue, forKey: "severeNotificationsEnabled") } }
    var uvEnabled: Bool { get { defaults.object(forKey: "uvNotificationsEnabled") == nil || defaults.bool(forKey: "uvNotificationsEnabled") } set { defaults.set(newValue, forKey: "uvNotificationsEnabled") } }
    var morningEnabled: Bool { get { defaults.bool(forKey: "morningNotificationsEnabled") } set { defaults.set(newValue, forKey: "morningNotificationsEnabled") } }
    var tomorrowEnabled: Bool { get { defaults.bool(forKey: "tomorrowNotificationsEnabled") } set { defaults.set(newValue, forKey: "tomorrowNotificationsEnabled") } }
    var smartCheckInEnabled: Bool { get { defaults.bool(forKey: "smartCheckInNotificationsEnabled") } set { defaults.set(newValue, forKey: "smartCheckInNotificationsEnabled") } }

    func refreshStatus() async {
        authorizationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        pendingCount = await UNUserNotificationCenter.current().pendingNotificationRequests().filter { $0.identifier.hasPrefix("vane.") }.count
    }

    @discardableResult
    func requestUsefulAlerts() async -> Bool {
        await refreshStatus()
        if authorizationStatus == .denied { return false }
        if authorizationStatus == .notDetermined { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
        await refreshStatus()
        return authorizationStatus == .authorized || authorizationStatus == .provisional
    }

    func setRainEnabled(_ enabled: Bool, snapshot: ForecastSnapshot) async { await set(enabled, keyPath: \.rainEnabled, snapshot: snapshot) }
    func setPreparationEnabled(_ enabled: Bool, snapshot: ForecastSnapshot) async { await set(enabled, keyPath: \.preparationEnabled, snapshot: snapshot) }

    func set(_ enabled: Bool, keyPath: ReferenceWritableKeyPath<NotificationManager, Bool>, snapshot: ForecastSnapshot) async {
        if enabled, !(await requestUsefulAlerts()) { self[keyPath: keyPath] = false; return }
        self[keyPath: keyPath] = enabled
        await schedule(snapshot: snapshot)
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func schedule(snapshot: ForecastSnapshot) async {
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix("vane.") }
        center.removePendingNotificationRequests(withIdentifiers: old.map(\.identifier))
        await refreshStatus()
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else { pendingCount = 0; return }
        let events = NotificationPlanner.plan(snapshot: snapshot, rainEnabled: rainEnabled, preparationEnabled: preparationEnabled, snowEnabled: snowEnabled, severeEnabled: severeEnabled, uvEnabled: uvEnabled, morningEnabled: morningEnabled, tomorrowEnabled: tomorrowEnabled)
        for event in events {
            let content = UNMutableNotificationContent(); content.title = event.title; content.body = event.body; content.sound = .default
            let request = UNNotificationRequest(identifier: event.id, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, event.date.timeIntervalSinceNow), repeats: false))
            try? await center.add(request)
        }
        await refreshStatus()
    }
}
