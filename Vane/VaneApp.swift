//
//  VaneApp.swift
//  Vane
//
//  Created by Makai O'Neill on 8/13/26.
//

import SwiftUI
import SwiftData

@main
struct VaneApp: App {
    private let modelContainer: ModelContainer
    private let storageRecoveryMessage: String?

    init() {
        let schema = Schema([
            WeatherProfile.self,
            WeatherCheckIn.self,
            SavedPlace.self,
        ])
        let persistent = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [persistent])
            storageRecoveryMessage = nil
        } catch {
            let originalError = error.localizedDescription
            do {
                modelContainer = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
                storageRecoveryMessage = "Vane could not open its saved private data (\(originalError)). A temporary session is running so you can still view weather. Reinstall or contact Vane before relying on new check-ins."
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
