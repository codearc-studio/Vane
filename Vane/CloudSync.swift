import CloudKit
import Observation
import SwiftData

enum VaneCloudKit {
    /// Keep this identifier shared by every future Vane ecosystem target.
    static let containerIdentifier = "iCloud.com.codearc.vane"

    static func cloudBackedConfiguration(schema: Schema) -> ModelConfiguration {
        ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            groupContainer: .none,
            cloudKitDatabase: .private(containerIdentifier)
        )
    }

    static func appConfiguration(schema: Schema) -> ModelConfiguration {
#if targetEnvironment(simulator)
        // Xcode's simulator code-signing context strips iCloud entitlements.
        // Keep previews and tests on the identical local schema; signed devices
        // use the private CloudKit configuration above.
        ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            groupContainer: .none,
            cloudKitDatabase: .none
        )
#else
        cloudBackedConfiguration(schema: schema)
#endif
    }
}

enum CloudSyncAvailability: Equatable {
    case checking
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine

    var title: String {
        switch self {
        case .checking: "Checking iCloud…"
        case .available: "iCloud is available"
        case .noAccount: "Sign in to iCloud"
        case .restricted: "iCloud is restricted"
        case .temporarilyUnavailable: "iCloud is temporarily unavailable"
        case .couldNotDetermine: "iCloud status unavailable"
        }
    }

    var detail: String {
        switch self {
        case .checking:
            "Vane is checking whether this device can use your private iCloud database."
        case .available:
            "Your Sense profile, check-ins and saved places sync privately between Vane apps signed in to this Apple Account."
        case .noAccount:
            "Vane will keep changes on this device and begin syncing after you sign in to iCloud in Settings."
        case .restricted:
            "This device does not currently allow iCloud data. Vane will keep changes locally until access is restored."
        case .temporarilyUnavailable:
            "Vane will keep changes locally and resume syncing automatically when iCloud is ready."
        case .couldNotDetermine:
            "Vane could not check iCloud right now. Your data remains available locally and sync will retry automatically."
        }
    }

    var symbol: String {
        switch self {
        case .checking: "arrow.triangle.2.circlepath.icloud"
        case .available: "checkmark.icloud.fill"
        case .noAccount: "person.crop.circle.badge.exclamationmark"
        case .restricted: "lock.icloud.fill"
        case .temporarilyUnavailable, .couldNotDetermine: "exclamationmark.icloud.fill"
        }
    }
}

@MainActor
@Observable
final class CloudSyncStatus {
    private(set) var availability: CloudSyncAvailability = .checking

    func refresh() async {
        availability = .checking
#if targetEnvironment(simulator)
        availability = .couldNotDetermine
#else
        do {
            let status = try await CKContainer(identifier: VaneCloudKit.containerIdentifier).accountStatus()
            availability = switch status {
            case .available: .available
            case .noAccount: .noAccount
            case .restricted: .restricted
            case .temporarilyUnavailable: .temporarilyUnavailable
            case .couldNotDetermine: .couldNotDetermine
            @unknown default: .couldNotDetermine
            }
        } catch {
            availability = .couldNotDetermine
        }
#endif
    }
}
