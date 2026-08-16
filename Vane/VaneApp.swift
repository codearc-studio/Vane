//
//  VaneApp.swift
//  Vane
//
//  Created by Makai O'Neill on 8/13/26.
//

import SwiftUI
import SwiftData
import OSLog

@main
struct VaneApp: App {
    private let modelContainer: ModelContainer
    private let storageRecoveryMessage: String?

    init() {
        let schema = Schema(versionedSchema: VaneSchemaV1.self)
        let persistent = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            modelContainer = try ModelContainer(for: schema, migrationPlan: VaneMigrationPlan.self, configurations: [persistent])
            storageRecoveryMessage = nil
        } catch {
            Logger(subsystem: "studio.codearc.Vane", category: "Storage").error("Persistent store failed to open: \(error.localizedDescription, privacy: .public)")
            do {
                modelContainer = try ModelContainer(for: schema, migrationPlan: VaneMigrationPlan.self, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
                storageRecoveryMessage = "Vane could not open its saved private data. A temporary session is available for viewing weather, but new check-ins will not be kept after the app closes. Contact Vane support before making changes to the app or its data."
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
    }
}
