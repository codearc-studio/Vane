import CoreLocation
import Foundation
import Observation
import WeatherKit

@MainActor
@Observable
final class WeatherStore: NSObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var hasStarted = false
    private let isScreenshotMode = ProcessInfo.processInfo.environment["VANE_SCREENSHOT_MODE"] == "1"

    var snapshot: ForecastSnapshot = .sample
    var isLoading = false
    var errorMessage: String?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var isUsingCurrentLocation = true

    override init() {
        super.init()
        if isScreenshotMode { snapshot = .screenshotPreview }
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        authorizationStatus = locationManager.authorizationStatus
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        guard !isScreenshotMode else { return }
        authorizationStatus = locationManager.authorizationStatus
        if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            requestCurrentLocation()
        } else {
            errorMessage = "Choose a location to bring in live weather."
        }
    }

    func requestCurrentLocation() {
        isUsingCurrentLocation = true
        authorizationStatus = locationManager.authorizationStatus
        switch authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            isLoading = true
            errorMessage = nil
            locationManager.requestLocation()
        case .denied, .restricted:
            isLoading = false
            errorMessage = "Location is off. Turn it on in Settings to see live weather."
        @unknown default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            isLoading = true
            manager.requestLocation()
        } else if authorizationStatus == .denied || authorizationStatus == .restricted {
            isLoading = false
            errorMessage = "Location is off. Turn it on in Settings to see live weather."
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { await loadWeather(for: location, preferredName: nil) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isLoading = false
        errorMessage = "Live weather is unavailable right now."
    }

    func loadSavedPlace(_ place: SavedPlace) async {
        isUsingCurrentLocation = false
        isLoading = true
        errorMessage = nil
        let location = CLLocation(latitude: place.latitude, longitude: place.longitude)
        await loadWeather(for: location, preferredName: place.name)
    }

    func loadCoordinate(name: String, latitude: Double, longitude: Double) async {
        isUsingCurrentLocation = false
        isLoading = true
        errorMessage = nil
        await loadWeather(for: CLLocation(latitude: latitude, longitude: longitude), preferredName: name)
    }

    private func loadWeather(for location: CLLocation, preferredName: String?) async {
        do {
            async let weatherRequest = WeatherService.shared.weather(for: location)
            async let nameRequest = locationName(for: location)
            let (weather, name) = try await (weatherRequest, nameRequest)
            let hourly = Array(weather.hourlyForecast.forecast.prefix(24)).map {
                HourlyConditions(
                    date: $0.date,
                    temperature: Int($0.temperature.converted(to: .fahrenheit).value.rounded()),
                    apparentTemperature: Int($0.apparentTemperature.converted(to: .fahrenheit).value.rounded()),
                    symbolName: $0.symbolName,
                    precipitationChance: $0.precipitationChance,
                    humidity: $0.humidity,
                    windSpeed: Int($0.wind.speed.converted(to: .milesPerHour).value.rounded())
                )
            }
            let daily = Array(weather.dailyForecast.forecast.prefix(10)).map {
                DailyConditions(
                    date: $0.date,
                    low: Int($0.lowTemperature.converted(to: .fahrenheit).value.rounded()),
                    high: Int($0.highTemperature.converted(to: .fahrenheit).value.rounded()),
                    symbolName: $0.symbolName,
                    precipitationChance: $0.precipitationChance
                )
            }
            let current = weather.currentWeather
            snapshot = ForecastSnapshot(
                locationName: preferredName ?? name,
                isSample: false,
                updatedAt: .now,
                current: CurrentConditions(
                    temperature: Int(current.temperature.converted(to: .fahrenheit).value.rounded()),
                    apparentTemperature: Int(current.apparentTemperature.converted(to: .fahrenheit).value.rounded()),
                    condition: current.condition.description,
                    symbolName: current.symbolName,
                    precipitationChance: hourly.first?.precipitationChance ?? 0,
                    humidity: current.humidity,
                    windSpeed: Int(current.wind.speed.converted(to: .milesPerHour).value.rounded()),
                    windDirection: Self.cardinalDirection(degrees: current.wind.direction.converted(to: .degrees).value),
                    uvIndex: current.uvIndex.value,
                    visibility: Int(current.visibility.converted(to: .miles).value.rounded()),
                    pressure: Int(current.pressure.converted(to: .hectopascals).value.rounded())
                ),
                hourly: hourly,
                daily: daily
            )
            isLoading = false
            errorMessage = nil
        } catch {
            isLoading = false
            errorMessage = "Live weather is unavailable right now."
        }
    }

    private func locationName(for location: CLLocation) async -> String {
        do {
            let marks = try await CLGeocoder().reverseGeocodeLocation(location)
            return marks.first?.locality ?? marks.first?.name ?? "Current Location"
        } catch {
            return "Current Location"
        }
    }

    private static func cardinalDirection(degrees: Double) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let normalized = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return directions[Int((normalized + 22.5) / 45) % 8]
    }
}
