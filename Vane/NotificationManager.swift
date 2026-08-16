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
    static func plan(
        snapshot: ForecastSnapshot,
        now: Date = .now,
        rainEnabled: Bool,
        preparationEnabled: Bool,
        snowEnabled: Bool = true,
        severeEnabled: Bool = false,
        uvEnabled: Bool = true,
        morningEnabled: Bool = false,
        tomorrowEnabled: Bool = false,
        smartCheckInEnabled: Bool = false,
        samples: [GuidanceSample] = [],
        checkInFrequency: CheckInFrequency = .recommended,
        formatting: WeatherFormatting? = nil
    ) -> [PlannedNotification] {
        guard !snapshot.isSample, !snapshot.isPlaceholder else { return [] }
        let formatting = formatting ?? WeatherFormatting(timeZone: snapshot.timeZone)
        let calendar = formatting.calendar
        let place = snapshot.sourceID == "current" ? "" : " in \(snapshot.locationName)"
        var events: [PlannedNotification] = []

        // This remains off by default and hidden in Settings until Vane has a dependable push pipeline.
        if severeEnabled, let alert = highestPriorityAlert(snapshot.alerts) {
            events.append(.init(id: "vane.severe.\(stableIdentifier(alert.id))", title: "Official weather alert\(place)", body: "\(alert.severity): \(alert.summary)", date: now.addingTimeInterval(60)))
        }

        if let start = precipitationStart(snapshot: snapshot, now: now), (start.kind == .snow || start.kind == .mixed ? snowEnabled : rainEnabled) {
            let title: String
            let bodyKind: String
            switch start.kind {
            case .snow: title = "Snow may start soon\(place)"; bodyKind = "Snow"
            case .mixed: title = "Mixed precipitation may start soon\(place)"; bodyKind = "A wintry mix"
            default: title = "Rain may start soon\(place)"; bodyKind = "Rain"
            }
            events.append(.init(id: "vane.precipitation.\(start.kind.rawValue).\(Int(start.hour.date.timeIntervalSince1970))", title: title, body: "\(bodyKind) is likely around \(formatting.hour(start.hour.date)).", date: max(start.hour.date.addingTimeInterval(-1_800), now.addingTimeInterval(60))))
        }

        if preparationEnabled, let shift = snapshot.hourly.prefix(16).first(where: { abs($0.temperature - snapshot.current.temperature) >= 12 && $0.date > now.addingTimeInterval(3_600) }) {
            let direction = shift.temperature > snapshot.current.temperature ? "A warmer change is coming" : "A cooler change is coming"
            events.append(.init(id: "vane.shift.\(Int(shift.date.timeIntervalSince1970))", title: "\(direction)\(place)", body: "The temperature moves toward \(formatting.degrees(shift.temperature, includeUnit: true)) by \(formatting.hour(shift.date)).", date: max(shift.date.addingTimeInterval(-3_600), now.addingTimeInterval(60))))
        }

        if uvEnabled, snapshot.current.uvIndex >= 6, calendar.component(.hour, from: now) < 16 {
            events.append(.init(id: "vane.uv.\(Int(calendar.startOfDay(for: now).timeIntervalSince1970))", title: "Strong sun today\(place)", body: "UV is \(snapshot.current.uvIndex). Sun protection will help if you are outside.", date: now.addingTimeInterval(120)))
        }

        if morningEnabled,
           let morning = calendar.nextDate(after: now, matching: DateComponents(hour: 7, minute: 30), matchingPolicy: .nextTime),
           let forecast = snapshot.daily.first(where: { calendar.isDate($0.date, inSameDayAs: morning) }) {
            events.append(.init(id: "vane.morning.\(Int(morning.timeIntervalSince1970))", title: "Today’s weather\(place)", body: "\(forecast.condition), with a high of \(formatting.degrees(forecast.high, includeUnit: true)) and low of \(formatting.degrees(forecast.low, includeUnit: true)).", date: morning))
        }

        if tomorrowEnabled,
           let evening = calendar.nextDate(after: now, matching: DateComponents(hour: 19), matchingPolicy: .nextTime),
           let targetDate = calendar.date(byAdding: .day, value: 1, to: evening),
           let forecast = snapshot.daily.first(where: { calendar.isDate($0.date, inSameDayAs: targetDate) }) {
            events.append(.init(id: "vane.tomorrow.\(Int(evening.timeIntervalSince1970))", title: "Tomorrow at a glance\(place)", body: "\(forecast.condition), \(formatting.temperatureRange(low: Double(forecast.low), high: Double(forecast.high))).", date: evening))
        }

        if smartCheckInEnabled, GuidanceEngine.shouldPrompt(snapshot: snapshot, samples: samples, frequency: checkInFrequency, now: now) {
            events.append(.init(id: "vane.smart-check-in.\(Int(now.timeIntervalSince1970 / 21_600))", title: "A useful weather moment\(place)", body: "These conditions are less familiar. A quick check-in would help Sense learn them.", date: now.addingTimeInterval(1_800)))
        }

        return Array(events.filter { $0.date > now }.sorted { lhs, rhs in
            if lhs.id.contains("severe") != rhs.id.contains("severe") { return lhs.id.contains("severe") }
            return lhs.date < rhs.date
        }.prefix(5))
    }

    private static func precipitationStart(snapshot: ForecastSnapshot, now: Date) -> (hour: HourlyConditions, kind: PrecipitationKind)? {
        var previousKind = snapshot.current.precipitationChance >= 0.55 ? snapshot.current.precipitationKind : .none
        for hour in snapshot.hourly.sorted(by: { $0.date < $1.date }) where hour.date > now {
            let kind = hour.precipitationChance >= 0.55 ? hour.precipitationKind : .none
            defer { previousKind = kind }
            guard hour.date > now.addingTimeInterval(1_200), previousKind == .none, kind != .none else { continue }
            return (hour, kind)
        }
        return nil
    }

    private static func highestPriorityAlert(_ alerts: [WeatherAlertSnapshot]) -> WeatherAlertSnapshot? {
        let rank = ["extreme": 4, "severe": 3, "moderate": 2, "minor": 1]
        return alerts.max { rank[$0.severity.lowercased(), default: 0] < rank[$1.severity.lowercased(), default: 0] }
    }

    private static func stableIdentifier(_ value: String) -> String {
        value.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }.description
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
    var severeEnabled: Bool { get { false } set { defaults.set(false, forKey: "severeNotificationsEnabled") } }
    var uvEnabled: Bool { get { defaults.object(forKey: "uvNotificationsEnabled") == nil || defaults.bool(forKey: "uvNotificationsEnabled") } set { defaults.set(newValue, forKey: "uvNotificationsEnabled") } }
    var morningEnabled: Bool { get { defaults.bool(forKey: "morningNotificationsEnabled") } set { defaults.set(newValue, forKey: "morningNotificationsEnabled") } }
    var tomorrowEnabled: Bool { get { defaults.bool(forKey: "tomorrowNotificationsEnabled") } set { defaults.set(newValue, forKey: "tomorrowNotificationsEnabled") } }
    var smartCheckInEnabled: Bool { get { defaults.bool(forKey: "smartCheckInNotificationsEnabled") } set { defaults.set(newValue, forKey: "smartCheckInNotificationsEnabled") } }

    func refreshStatus() async {
        authorizationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        pendingCount = await UNUserNotificationCenter.current().pendingNotificationRequests().filter { $0.identifier.hasPrefix("vane.") }.count
    }

    @discardableResult func requestUsefulAlerts() async -> Bool {
        await refreshStatus()
        if authorizationStatus == .denied { return false }
        if authorizationStatus == .notDetermined { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
        await refreshStatus()
        return authorizationStatus == .authorized || authorizationStatus == .provisional
    }

    func set(_ enabled: Bool, keyPath: ReferenceWritableKeyPath<NotificationManager, Bool>, snapshot: ForecastSnapshot, samples: [GuidanceSample] = [], checkInFrequency: CheckInFrequency = .recommended) async {
        if enabled, !(await requestUsefulAlerts()) { self[keyPath: keyPath] = false; return }
        self[keyPath: keyPath] = enabled
        await schedule(snapshot: snapshot, samples: samples, checkInFrequency: checkInFrequency)
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func schedule(snapshot: ForecastSnapshot, samples: [GuidanceSample] = [], checkInFrequency: CheckInFrequency = .recommended) async {
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix("vane.") }
        center.removePendingNotificationRequests(withIdentifiers: old.map(\.identifier))
        await refreshStatus()
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else { pendingCount = 0; return }
        let events = NotificationPlanner.plan(snapshot: snapshot, rainEnabled: rainEnabled, preparationEnabled: preparationEnabled, snowEnabled: snowEnabled, severeEnabled: severeEnabled, uvEnabled: uvEnabled, morningEnabled: morningEnabled, tomorrowEnabled: tomorrowEnabled, smartCheckInEnabled: smartCheckInEnabled, samples: samples, checkInFrequency: checkInFrequency)
        for event in events {
            let content = UNMutableNotificationContent(); content.title = event.title; content.body = event.body; content.sound = .default
            let request = UNNotificationRequest(identifier: event.id, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, event.date.timeIntervalSinceNow), repeats: false))
            try? await center.add(request)
        }
        await refreshStatus()
    }

    func cancelAllVaneNotifications() async {
        let center = UNUserNotificationCenter.current()
        let identifiers = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("vane.") }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        await refreshStatus()
    }

    func resetPreferences() {
        ["rainNotificationsEnabled", "preparationNotificationsEnabled", "snowNotificationsEnabled", "severeNotificationsEnabled", "uvNotificationsEnabled", "morningNotificationsEnabled", "tomorrowNotificationsEnabled", "smartCheckInNotificationsEnabled"].forEach(defaults.removeObject(forKey:))
    }
}
