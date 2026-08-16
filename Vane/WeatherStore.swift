import CoreLocation
import Foundation
import MapKit
import Observation
import UIKit
import WeatherKit

nonisolated protocol WeatherProviding: Sendable {
    func weather(for location: CLLocation) async throws -> Weather
}

nonisolated struct AppleWeatherProvider: WeatherProviding {
    func weather(for location: CLLocation) async throws -> Weather { try await WeatherService.shared.weather(for: location) }
}

enum WeatherDisplayState: Equatable {
    case needsLocation
    case permissionUnavailable
    case loading
    case live
    case stale(String)
    case unavailable(String)
}

enum CheckInPresence: Equatable {
    case verified
    case unavailable
    case away(miles: Int)
}

struct WeatherRequestGate {
    private(set) var token = UUID()
    private(set) var sourceID = "current"

    mutating func begin(sourceID: String) -> UUID {
        token = UUID()
        self.sourceID = sourceID
        return token
    }

    func accepts(token: UUID, sourceID: String) -> Bool { token == self.token && sourceID == self.sourceID }
}

@MainActor
@Observable
final class WeatherStore: NSObject, CLLocationManagerDelegate {
    private enum Key {
        static let sourceID = "weather.selectedSourceID"
        static let sourceName = "weather.selectedSourceName"
        static let latitude = "weather.selectedLatitude"
        static let longitude = "weather.selectedLongitude"
        static let timeZone = "weather.selectedTimeZone"
        static let isTravel = "weather.selectedIsTravel"
    }

    private let locationManager = CLLocationManager()
    private let defaults = UserDefaults.standard
    private let weatherProvider: any WeatherProviding
    private let airQualityProvider: any AirQualityProviding
    private var hasStarted = false
    private var requestGate = WeatherRequestGate()
    private let isScreenshotMode = ProcessInfo.processInfo.environment["VANE_SCREENSHOT_MODE"] == "1"

    var snapshot: ForecastSnapshot = .empty
    var displayState: WeatherDisplayState = .needsLocation
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var isUsingCurrentLocation = true
    var selectedSourceID = "current"
    var attribution: WeatherAttributionInfo?

    var isLoading: Bool { displayState == .loading }
    var errorMessage: String? {
        switch displayState {
        case .stale(let message), .unavailable(let message): message
        case .permissionUnavailable: "Location is off. Choose a saved place or enable access in Settings."
        default: nil
        }
    }

    override convenience init() { self.init(weatherProvider: AppleWeatherProvider(), airQualityProvider: OpenMeteoAirQualityProvider()) }

    init(weatherProvider: any WeatherProviding, airQualityProvider: any AirQualityProviding = OpenMeteoAirQualityProvider()) {
        self.weatherProvider = weatherProvider
        self.airQualityProvider = airQualityProvider
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 50
        authorizationStatus = locationManager.authorizationStatus
        if isScreenshotMode {
            snapshot = .screenshotPreview
            displayState = .live
        }
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        guard !isScreenshotMode else { return }
        await loadAttribution()
        authorizationStatus = locationManager.authorizationStatus
        let restoredID = defaults.string(forKey: Key.sourceID) ?? "current"
        if restoredID != "current",
           let name = defaults.string(forKey: Key.sourceName),
           defaults.object(forKey: Key.latitude) != nil,
           defaults.object(forKey: Key.longitude) != nil {
            isUsingCurrentLocation = false
            selectedSourceID = restoredID
            await loadWeather(for: CLLocation(latitude: defaults.double(forKey: Key.latitude), longitude: defaults.double(forKey: Key.longitude)), preferredName: name, sourceID: restoredID, preferredTimeZoneIdentifier: defaults.string(forKey: Key.timeZone), isTravel: defaults.bool(forKey: Key.isTravel))
        } else if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            requestCurrentLocation()
        } else if authorizationStatus == .denied || authorizationStatus == .restricted {
            displayState = .permissionUnavailable
        } else {
            displayState = .needsLocation
        }
    }

    func requestCurrentLocation() {
        isUsingCurrentLocation = true
        selectedSourceID = "current"
        _ = requestGate.begin(sourceID: "current")
        persistCurrentSource()
        authorizationStatus = locationManager.authorizationStatus
        switch authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            displayState = .loading
            locationManager.requestLocation()
        case .denied, .restricted:
            displayState = snapshot.isPlaceholder ? .permissionUnavailable : .stale("Location permission is off. The last forecast remains visible.")
        @unknown default:
            displayState = .unavailable("Location is unavailable right now.")
        }
    }

    func openLocationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func refreshSelectedSource() async {
        if isUsingCurrentLocation {
            requestCurrentLocation()
        } else if let name = defaults.string(forKey: Key.sourceName), defaults.object(forKey: Key.latitude) != nil, defaults.object(forKey: Key.longitude) != nil {
            await loadWeather(for: CLLocation(latitude: defaults.double(forKey: Key.latitude), longitude: defaults.double(forKey: Key.longitude)), preferredName: name, sourceID: selectedSourceID, preferredTimeZoneIdentifier: defaults.string(forKey: Key.timeZone), isTravel: defaults.bool(forKey: Key.isTravel))
        } else {
            resetSelection()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            isUsingCurrentLocation = true
            selectedSourceID = "current"
            _ = requestGate.begin(sourceID: "current")
            persistCurrentSource()
            displayState = .loading
            manager.requestLocation()
        } else if authorizationStatus == .denied || authorizationStatus == .restricted {
            displayState = snapshot.isPlaceholder ? .permissionUnavailable : .stale("Location permission is off. The last forecast remains visible.")
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let fresh = locations.filter { $0.horizontalAccuracy >= 0 && Date().timeIntervalSince($0.timestamp) < 300 }
        guard let location = fresh.min(by: { $0.horizontalAccuracy < $1.horizontalAccuracy }) else {
            displayState = snapshot.isPlaceholder ? .unavailable("A fresh location could not be found. Try again.") : .stale(Self.staleRefreshMessage(snapshot: snapshot))
            return
        }
        Task { await loadWeather(for: location, preferredName: nil, sourceID: "current", isTravel: false) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        displayState = snapshot.isPlaceholder ? .unavailable("Current location could not be found. Choose a place and try again.") : .stale(Self.staleRefreshMessage(snapshot: snapshot))
    }

    static func staleRefreshMessage(snapshot: ForecastSnapshot) -> String {
        "Refresh failed. Showing weather updated \(snapshot.updatedAt.formatted(.relative(presentation: .named)))."
    }

    func loadSavedPlace(_ place: SavedPlace) async {
        await select(name: place.name, latitude: place.latitude, longitude: place.longitude, sourceID: "place:\(place.id.uuidString)", timeZoneIdentifier: place.timeZoneIdentifier, isTravel: !place.isHome)
        if place.timeZoneIdentifier == nil, snapshot.sourceID == "place:\(place.id.uuidString)" { place.timeZoneIdentifier = snapshot.timeZoneIdentifier }
    }

    func loadCoordinate(name: String, latitude: Double, longitude: Double) async {
        await select(name: name, latitude: latitude, longitude: longitude, sourceID: "coordinate:\(latitude),\(longitude)", timeZoneIdentifier: nil, isTravel: false)
    }

    func resetSelection() {
        defaults.removeObject(forKey: Key.sourceName)
        defaults.removeObject(forKey: Key.latitude)
        defaults.removeObject(forKey: Key.longitude)
        defaults.removeObject(forKey: Key.timeZone)
        defaults.removeObject(forKey: Key.isTravel)
        _ = requestGate.begin(sourceID: "current")
        isUsingCurrentLocation = true
        selectedSourceID = "current"
        persistCurrentSource()
        snapshot = .empty
        displayState = authorizationStatus == .denied || authorizationStatus == .restricted ? .permissionUnavailable : .needsLocation
    }

    func isSelected(_ place: SavedPlace) -> Bool { selectedSourceID == "place:\(place.id.uuidString)" }

    func checkInPresence(for snapshot: ForecastSnapshot) -> CheckInPresence {
        if isUsingCurrentLocation { return .verified }
        guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse,
              let deviceLocation = locationManager.location,
              deviceLocation.horizontalAccuracy >= 0,
              Date().timeIntervalSince(deviceLocation.timestamp) < 900 else { return .unavailable }
        let forecastLocation = CLLocation(latitude: snapshot.latitude, longitude: snapshot.longitude)
        let miles = deviceLocation.distance(from: forecastLocation) / 1_609.344
        return miles <= 25 ? .verified : .away(miles: Int(miles.rounded()))
    }

    private func select(name: String, latitude: Double, longitude: Double, sourceID: String, timeZoneIdentifier: String?, isTravel: Bool) async {
        isUsingCurrentLocation = false
        selectedSourceID = sourceID
        defaults.set(sourceID, forKey: Key.sourceID)
        defaults.set(name, forKey: Key.sourceName)
        defaults.set(latitude, forKey: Key.latitude)
        defaults.set(longitude, forKey: Key.longitude)
        defaults.set(timeZoneIdentifier, forKey: Key.timeZone)
        defaults.set(isTravel, forKey: Key.isTravel)
        await loadWeather(for: CLLocation(latitude: latitude, longitude: longitude), preferredName: name, sourceID: sourceID, preferredTimeZoneIdentifier: timeZoneIdentifier, isTravel: isTravel)
    }

    private func loadWeather(for location: CLLocation, preferredName: String?, sourceID: String, preferredTimeZoneIdentifier: String? = nil, isTravel: Bool = false) async {
        let requestID = requestGate.begin(sourceID: sourceID)
        displayState = .loading
        do {
            async let weatherRequest = weatherProvider.weather(for: location)
            let details: (name: String, timeZoneIdentifier: String)
            if let preferredName, let preferredTimeZoneIdentifier {
                details = (preferredName, preferredTimeZoneIdentifier)
            } else {
                details = await locationDetails(for: location)
            }
            let name = preferredName ?? details.name
            let timeZoneIdentifier = preferredTimeZoneIdentifier ?? details.timeZoneIdentifier
            let weather = try await weatherRequest
            let hourly = Array(weather.hourlyForecast.forecast.prefix(48)).map {
                HourlyConditions(
                    date: $0.date,
                    temperature: fahrenheit($0.temperature),
                    apparentTemperature: fahrenheit($0.apparentTemperature),
                    symbolName: $0.symbolName,
                    condition: $0.condition.description,
                    precipitationChance: $0.precipitationChance,
                    humidity: $0.humidity,
                    windSpeed: mph($0.wind.speed),
                    windGust: $0.wind.gust.map(mph) ?? mph($0.wind.speed),
                    dewPoint: fahrenheit($0.dewPoint),
                    cloudCover: $0.cloudCover,
                    isDaylight: $0.isDaylight,
                    precipitationKind: Self.precipitationKind($0.precipitation)
                )
            }
            let daily = Array(weather.dailyForecast.forecast.prefix(10)).map {
                DailyConditions(
                    date: $0.date,
                    low: fahrenheit($0.lowTemperature),
                    high: fahrenheit($0.highTemperature),
                    symbolName: $0.symbolName,
                    condition: $0.condition.description,
                    precipitationChance: $0.precipitationChance,
                    sunrise: $0.sun.sunrise,
                    sunset: $0.sun.sunset,
                    uvIndex: $0.uvIndex.value,
                    windSpeed: mph($0.wind.speed),
                    windGust: $0.wind.gust.map(mph) ?? mph($0.wind.speed),
                    precipitationAmount: $0.precipitationAmountByType.precipitation.converted(to: .inches).value,
                    civilDawn: $0.sun.civilDawn,
                    solarNoon: $0.sun.solarNoon,
                    civilDusk: $0.sun.civilDusk,
                    moonPhase: $0.moon.phase.description.capitalized,
                    moonrise: $0.moon.moonrise,
                    moonset: $0.moon.moonset
                )
            }
            let alerts = (weather.weatherAlerts ?? []).map {
                WeatherAlertSnapshot(id: $0.detailsURL.absoluteString, summary: $0.summary, severity: $0.severity.description.capitalized, region: $0.region, source: $0.source, detailsURL: $0.detailsURL)
            }
            let current = weather.currentWeather
            guard requestGate.accepts(token: requestID, sourceID: sourceID), sourceID == selectedSourceID else { return }
            let previousAirQuality = snapshot.sourceID == sourceID ? snapshot.airQuality : nil
            snapshot = ForecastSnapshot(
                locationName: name,
                sourceID: sourceID,
                isSample: false,
                updatedAt: current.date,
                current: CurrentConditions(
                    temperature: fahrenheit(current.temperature), apparentTemperature: fahrenheit(current.apparentTemperature), condition: current.condition.description, symbolName: current.symbolName,
                    precipitationChance: hourly.first?.precipitationChance ?? 0, humidity: current.humidity, windSpeed: mph(current.wind.speed), windDirection: Self.cardinalDirection(degrees: current.wind.direction.converted(to: .degrees).value), windDirectionDegrees: current.wind.direction.converted(to: .degrees).value, uvIndex: current.uvIndex.value, visibility: Int(current.visibility.converted(to: .miles).value.rounded()), pressure: Int(current.pressure.converted(to: .hectopascals).value.rounded()), pressureTrend: current.pressureTrend.description.capitalized, dewPoint: fahrenheit(current.dewPoint), windGust: current.wind.gust.map(mph) ?? mph(current.wind.speed), precipitationKind: hourly.first?.precipitationKind ?? .none, cloudCover: current.cloudCover, isDaylight: current.isDaylight
                ),
                hourly: hourly,
                daily: daily,
                alerts: alerts,
                timeZoneIdentifier: timeZoneIdentifier,
                isTravelLocation: isTravel,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                locationAccuracy: sourceID == "current" && location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil,
                airQuality: previousAirQuality
            )
            if sourceID != "current" { defaults.set(timeZoneIdentifier, forKey: Key.timeZone) }
            displayState = .live
            Task { await updateAirQuality(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, sourceID: sourceID, requestID: requestID) }
            if attribution == nil { await loadAttribution() }
        } catch {
            guard requestGate.accepts(token: requestID, sourceID: sourceID), sourceID == selectedSourceID else { return }
            let offline = (error as? URLError)?.code == .notConnectedToInternet
            if snapshot.isPlaceholder {
                displayState = .unavailable(offline ? "You’re offline. Connect to load a forecast." : "Apple Weather is temporarily unavailable. Try again shortly.")
            } else {
                let updated = WeatherFormatting(timeZone: snapshot.timeZone).shortTime(snapshot.updatedAt)
                displayState = .stale(offline ? "You’re offline — showing weather updated at \(updated)." : "Refresh failed — showing weather updated at \(updated).")
            }
        }
    }

    private func updateAirQuality(latitude: Double, longitude: Double, sourceID: String, requestID: UUID) async {
        guard let airQuality = try? await airQualityProvider.currentAirQuality(latitude: latitude, longitude: longitude),
              requestGate.accepts(token: requestID, sourceID: sourceID),
              selectedSourceID == sourceID else { return }
        snapshot = snapshot.replacingAirQuality(airQuality)
    }

    private func loadAttribution() async {
        if attribution == nil,
           let serviceName = defaults.string(forKey: "weather.attribution.serviceName"),
           let legal = defaults.url(forKey: "weather.attribution.legal"),
           let light = defaults.url(forKey: "weather.attribution.light"),
           let dark = defaults.url(forKey: "weather.attribution.dark") {
            attribution = WeatherAttributionInfo(serviceName: serviceName, legalPageURL: legal, combinedMarkLightURL: light, combinedMarkDarkURL: dark)
        }
        guard let value = try? await WeatherService.shared.attribution else { return }
        let current = WeatherAttributionInfo(serviceName: value.serviceName, legalPageURL: value.legalPageURL, combinedMarkLightURL: value.combinedMarkLightURL, combinedMarkDarkURL: value.combinedMarkDarkURL)
        attribution = current
        defaults.set(current.serviceName, forKey: "weather.attribution.serviceName")
        defaults.set(current.legalPageURL, forKey: "weather.attribution.legal")
        defaults.set(current.combinedMarkLightURL, forKey: "weather.attribution.light")
        defaults.set(current.combinedMarkDarkURL, forKey: "weather.attribution.dark")
    }

    private func locationDetails(for location: CLLocation) async -> (name: String, timeZoneIdentifier: String) {
        do {
            guard let request = MKReverseGeocodingRequest(location: location) else { return ("Current Location", TimeZone.current.identifier) }
            let item = try await request.mapItems.first
            return (item?.addressRepresentations?.cityName ?? item?.name ?? "Current Location", item?.timeZone?.identifier ?? TimeZone.current.identifier)
        } catch { return ("Current Location", TimeZone.current.identifier) }
    }

    private func persistCurrentSource() { defaults.set("current", forKey: Key.sourceID) }
    private func fahrenheit(_ measurement: Measurement<UnitTemperature>) -> Int { Int(measurement.converted(to: .fahrenheit).value.rounded()) }
    private func mph(_ measurement: Measurement<UnitSpeed>) -> Int { Int(measurement.converted(to: .milesPerHour).value.rounded()) }

    private static func cardinalDirection(degrees: Double) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let normalized = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return directions[Int((normalized + 22.5) / 45) % 8]
    }

    private static func precipitationKind(_ value: WeatherKit.Precipitation) -> PrecipitationKind {
        switch value {
        case .rain: .rain
        case .snow: .snow
        case .mixed, .sleet, .hail: .mixed
        case .none: .none
        @unknown default: .none
        }
    }
}
