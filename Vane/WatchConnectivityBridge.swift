import Foundation
@preconcurrency import WatchConnectivity

@MainActor
final class WatchConnectivityBridge: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityBridge()

    private let session: WCSession?

    private override init() {
        session = WCSession.isSupported() ? .default : nil
        super.init()
    }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    func publish(_ snapshot: VaneWidgetSnapshot) {
        guard let session, let data = try? snapshot.encoded() else { return }
        if session.delegate == nil {
            activate()
        }
        try? session.updateApplicationContext([
            VaneWidgetConstants.watchSnapshotKey: data
        ])
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) { }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) { }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard message[VaneWidgetConstants.watchSnapshotRequestKey] as? Bool == true,
              let snapshot = VaneWidgetDataStore.load(),
              let data = try? snapshot.encoded() else {
            replyHandler(["error": "No forecast is available yet."])
            return
        }
        replyHandler([VaneWidgetConstants.watchSnapshotKey: data])
    }
}
