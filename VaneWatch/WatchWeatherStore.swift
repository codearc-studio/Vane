import Foundation
import SwiftUI
import Combine
import WidgetKit
@preconcurrency import WatchConnectivity

@MainActor
final class WatchWeatherStore: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var snapshot: VaneWidgetSnapshot?
    @Published private(set) var isRequestingRefresh = false
    @Published private(set) var syncMessage: String?

    private let session: WCSession?
    private static let cacheKey = "vane.watch.snapshot"

    override init() {
#if DEBUG
        if ProcessInfo.processInfo.environment["VANE_WATCH_SAMPLE"] == "1" {
            snapshot = .sample
        } else {
            snapshot = VaneWidgetDataStore.load() ?? Self.loadCachedSnapshot()
        }
#else
        snapshot = VaneWidgetDataStore.load() ?? Self.loadCachedSnapshot()
#endif
        session = WCSession.isSupported() ? .default : nil
        super.init()
        if let snapshot {
            try? VaneWidgetDataStore.save(snapshot)
            WidgetCenter.shared.reloadAllTimelines()
        }
        session?.delegate = self
        session?.activate()
    }

    func requestRefresh() {
        guard let session else {
            syncMessage = "Sync is unavailable on this watch."
            return
        }

        let receivedContext: Bool
        if let data = session.receivedApplicationContext[VaneWidgetConstants.watchSnapshotKey] as? Data {
            accept(data)
            receivedContext = true
        } else {
            receivedContext = false
        }

        guard session.isReachable else {
            if !receivedContext {
                syncMessage = "Open Vane on your iPhone. Its next update will sync here automatically."
            }
            return
        }

        isRequestingRefresh = true
        syncMessage = nil
        session.sendMessage(
            [VaneWidgetConstants.watchSnapshotRequestKey: true],
            replyHandler: { [weak self] reply in
                guard let data = reply[VaneWidgetConstants.watchSnapshotKey] as? Data else {
                    let message = reply["error"] as? String ?? "The iPhone did not return weather."
                    Task { @MainActor in
                        self?.isRequestingRefresh = false
                        self?.syncMessage = message
                    }
                    return
                }
                Task { @MainActor in
                    self?.accept(data)
                    self?.isRequestingRefresh = false
                }
            },
            errorHandler: { [weak self] _ in
                Task { @MainActor in
                    self?.isRequestingRefresh = false
                    self?.syncMessage = "Could not reach the iPhone. The last forecast is still shown."
                }
            }
        )
    }

    private func accept(_ data: Data) {
        guard let value = try? VaneWidgetSnapshot.decoded(from: data) else {
            syncMessage = "The latest forecast could not be read."
            return
        }
        snapshot = value
        syncMessage = nil
        UserDefaults.standard.set(data, forKey: Self.cacheKey)
        try? VaneWidgetDataStore.save(value)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func loadCachedSnapshot() -> VaneWidgetSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? VaneWidgetSnapshot.decoded(from: data)
    }

#if DEBUG
    static func preview(snapshot: VaneWidgetSnapshot?) -> WatchWeatherStore {
        let store = WatchWeatherStore()
        store.snapshot = snapshot
        return store
    }
#endif

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        guard let data = session.receivedApplicationContext[VaneWidgetConstants.watchSnapshotKey] as? Data else { return }
        Task { @MainActor [weak self] in self?.accept(data) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[VaneWidgetConstants.watchSnapshotKey] as? Data else { return }
        Task { @MainActor [weak self] in self?.accept(data) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let data = message[VaneWidgetConstants.watchSnapshotKey] as? Data else { return }
        Task { @MainActor [weak self] in self?.accept(data) }
    }
}
