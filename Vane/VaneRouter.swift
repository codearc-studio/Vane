import Foundation
import Observation

enum VaneDestination: Equatable {
    case weather
    case alerts
    case forecast
    case conditions
    case sun
    case sense
}

@MainActor
@Observable
final class VaneRouter {
    private(set) var destination: VaneDestination = .weather
    private(set) var sequence = 0

    func open(_ url: URL) {
        guard url.scheme?.lowercased() == "vane" else { return }
        if url.host?.lowercased() == "sense" {
            destination = .sense
            sequence += 1
            return
        }
        guard url.host?.lowercased() == "weather" else { return }
        switch url.path.lowercased() {
        case "/alerts": destination = .alerts
        case "/week", "/forecast": destination = .forecast
        case "/conditions", "/details": destination = .conditions
        case "/sun": destination = .sun
        default: destination = .weather
        }
        sequence += 1
    }
}
