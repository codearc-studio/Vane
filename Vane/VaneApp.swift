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
    private let modelContainer: ModelContainer = {
        let schema = Schema([
            WeatherProfile.self,
            WeatherCheckIn.self,
            SavedPlace.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Unable to open Vane's private weather model: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
