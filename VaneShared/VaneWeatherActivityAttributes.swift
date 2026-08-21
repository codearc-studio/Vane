import ActivityKit
import Foundation

nonisolated enum VaneWeatherActivityKind: String, Codable, Hashable, Sendable {
    case severeAlert
    case storm
    case precipitation
    case outdoorWindow
}

nonisolated struct VaneWeatherActivityAttributes: ActivityAttributes, Sendable {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        let kind: VaneWeatherActivityKind
        let title: String
        let detail: String
        let symbolName: String
        let temperatureText: String
        let eventDate: Date?
        let showsCountdown: Bool
        let updatedAt: Date
        let destinationURLString: String
    }

    let locationName: String
    let sourceID: String
    let isTravelLocation: Bool
}
