import CoreLocation
import Foundation
import MapKit
import Observation
import UIKit
import WeatherKit

enum WeatherDisplayState: Equatable {
    case needsLocation
    case permissionUnavailable
    case loading
    case live
    case stale(String)
    case sample
    case unavailable(String)
}

@MainActor
@Observable
final class WeatherStore: NSObject, CLLocationManagerDelegate {
    private enum Key {
        static let sourceID = "weather.selectedSourceID"
        static let sourceName = "weather.selectedSourceName"
        static let latitude = "weather.selectedLatitude"
        static let longitude = "weather.selectedLongitude"
    }

    private let locationManager = CLLocationManager()
    private let defaults = UserDefaults.standard
    private var hasStarted = false
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

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
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
            await loadWeather(for: CLLocation(latitude: defaults.double(forKey: Key.latitude), longitude: defaults.double(forKey: Key.longitude)), preferredName: name, sourceID: restoredID)
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
            await loadWeather(for: CLLocation(latitude: defaults.double(forKey: Key.latitude), longitude: defaults.double(forKey: Key.longitude)), preferredName: name, sourceID: selectedSourceID)
        } else {
            resetSelection()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            isUsingCurrentLocation = true
            selectedSourceID = "current"
            persistCurrentSource()
            displayState = .loading
            manager.requestLocation()
        } else if authorizationStatus == .denied || authorizationStatus == .restricted {
            displayState = snapshot.isPlaceholder ? .permissionUnavailable : .stale("Location permission is off. The last forecast remains visible.")
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { await loadWeather(for: location, preferredName: nil, sourceID: "current") }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        displayState = snapshot.isPlaceholder ? .unavailable("Current location could not be found. Choose a place and try again.") : .stale("Refresh failed. Showing weather updated (snapshot.updatedAt.formatted(.relative(presentation: .named))).")
    }

    func loadSavedPlace(_ place: SavedPlace) async {
        await select(name: place.name, latitude: place.latitude, longitude: place.longitude, sourceID: "place:\(place.id.uuidString)")
    }

    func loadCoordinate(name: String, latitude: Double, longitude: Double) async {
        await select(name: name, latitude: latitude, longitude: longitude, sourceID: "coordinate:\(latitude),\(longitude)")
    }

    func resetSelection() {
        defaults.removeObject(forKey: Key.sourceName)
        defaults.removeObject(forKey: Key.latitude)
        defaults.removeObject(forKey: Key.longitude)
        isUsingCurrentLocation = true
        selectedSourceID = "current"
        persistCurrentSource()
        snapshot = .empty
        displayState = authorizationStatus == .denied || authorizationStatus == .restricted ? .permissionUnavailable : .needsLocation
    }

    func isSelected(_ place: SavedPlace) -> Bool { selectedSourceID == "place:\(place.id.uuidString)" }

    private func select(name: String, latitude: Double, longitude: Double, sourceID: String) async {
        isUsingCurrentLocation = false
        selectedSourceID = sourceID
        defaults.set(sourceID, forKey: Key.sourceID)
        defaults.set(name, forKey: Key.sourceName)
        defaults.set(latitude, forKey: Key.latitude)
        defaults.set(longitude, forKey: Key.longitude)
        await loadWeather(for: CLLocation(latitude: latitude, longitude: longitude), preferredName: name, sourceID: sourceID)
    }

    private func loadWeather(for location: CLLocation, preferredName: String?, sourceID: String) async {
        displayState = .loading
        do {
            async let weatherRequest = WeatherService.shared.weather(for: location)
            let name: String
            if let preferredName {
                name = preferredName
            } else {
                name = await locationName(for: location)
            }
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
                    isDaylight: $0.isDaylight
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
                    precipitationAmount: $0.precipitationAmountByType.precipitation.converted(to: .inches).value
                )
            }
            let alerts = (weather.weatherAlerts ?? []).map {
                WeatherAlertSnapshot(id: $0.detailsURL.absoluteString, summary: $0.summary, severity: $0.severity.description.capitalized, region: $0.region, source: $0.source, detailsURL: $0.detailsURL)
            }
            let current = weather.currentWeather
            snapshot = ForecastSnapshot(
                locationName: name,
                sourceID: sourceID,
                isSample: false,
                updatedAt: .now,
                current: CurrentConditions(
                    temperature: fahrenheit(current.temperature), apparentTemperature: fahrenheit(current.apparentTemperature), condition: current.condition.description, symbolName: current.symbolName,
                    precipitationChance: hourly.first?.precipitationChance ?? 0, humidity: current.humidity, windSpeed: mph(current.wind.speed), windDirection: Self.cardinalDirection(degrees: current.wind.direction.converted(to: .degrees).value), uvIndex: current.uvIndex.value, visibility: Int(current.visibility.converted(to: .miles).value.rounded()), pressure: Int(current.pressure.converted(to: .hectopascals).value.rounded()), dewPoint: fahrenheit(current.dewPoint), windGust: current.wind.gust.map(mph) ?? mph(current.wind.speed), precipitationType: hourly.first?.condition ?? "None", cloudCover: current.cloudCover, isDaylight: current.isDaylight
                ),
                hourly: hourly,
                daily: daily,
                alerts: alerts
            )
            displayState = .live
        } catch {
            let offline = (error as? URLError)?.code == .notConnectedToInternet
            if snapshot.isPlaceholder {
                displayState = .unavailable(offline ? "You’re offline. Connect to load a forecast." : "Apple Weather is temporarily unavailable. Try again shortly.")
            } else {
                displayState = .stale(offline ? "You’re offline — showing weather updated at \(snapshot.updatedAt.formatted(date: .omitted, time: .shortened))." : "Refresh failed — showing weather updated at \(snapshot.updatedAt.formatted(date: .omitted, time: .shortened)).")
            }
        }
    }

    private func loadAttribution() async {
        guard let value = try? await WeatherService.shared.attribution else { return }
        attribution = WeatherAttributionInfo(serviceName: value.serviceName, legalPageURL: value.legalPageURL, combinedMarkLightURL: value.combinedMarkLightURL, combinedMarkDarkURL: value.combinedMarkDarkURL)
    }

    private func locationName(for location: CLLocation) async -> String {
        do {
            guard let request = MKReverseGeocodingRequest(location: location) else { return "Current Location" }
            let item = try await request.mapItems.first
            return item?.addressRepresentations?.cityName ?? item?.name ?? "Current Location"
        } catch { return "Current Location" }
    }

    private func persistCurrentSource() { defaults.set("current", forKey: Key.sourceID) }
    private func fahrenheit(_ measurement: Measurement<UnitTemperature>) -> Int { Int(measurement.converted(to: .fahrenheit).value.rounded()) }
    private func mph(_ measurement: Measurement<UnitSpeed>) -> Int { Int(measurement.converted(to: .milesPerHour).value.rounded()) }

    private static func cardinalDirection(degrees: Double) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let normalized = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return directions[Int((normalized + 22.5) / 45) % 8]
    }
}
