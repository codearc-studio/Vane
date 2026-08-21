import SwiftUI

@main
struct VaneWatchApp: App {
    @StateObject private var store = WatchWeatherStore()

    var body: some Scene {
        WindowGroup {
            WatchContentView(store: store)
        }
    }
}
