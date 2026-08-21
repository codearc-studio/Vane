import Foundation
import WidgetKit

@MainActor
enum WidgetBridge {
    static func publish(snapshot: ForecastSnapshot, guidance: PersonalGuidance? = nil) {
        guard !snapshot.isPlaceholder, !snapshot.isSample else { return }

        let cached = VaneWidgetDataStore.load()
        let canReuseGuidance = cached?.sourceID == snapshot.sourceID
        let widgetSnapshot = VaneWidgetSnapshot(
            locationName: snapshot.locationName,
            sourceID: snapshot.sourceID,
            updatedAt: snapshot.updatedAt,
            latitude: snapshot.latitude,
            longitude: snapshot.longitude,
            timeZoneIdentifier: snapshot.timeZoneIdentifier,
            temperature: snapshot.current.temperature,
            apparentTemperature: snapshot.current.apparentTemperature,
            condition: snapshot.current.condition,
            symbolName: snapshot.current.symbolName,
            precipitationChance: snapshot.current.precipitationChance,
            humidity: snapshot.current.humidity,
            windSpeed: snapshot.current.windSpeed,
            windGust: snapshot.current.windGust,
            windDirection: snapshot.current.windDirection,
            uvIndex: snapshot.current.uvIndex,
            visibility: snapshot.current.visibility,
            pressure: snapshot.current.pressure,
            dewPoint: snapshot.current.dewPoint,
            isDaylight: snapshot.current.isDaylight,
            hourly: snapshot.hourly.map {
                VaneWidgetSnapshot.Hour(
                    date: $0.date,
                    temperature: $0.temperature,
                    apparentTemperature: $0.apparentTemperature,
                    symbolName: $0.symbolName,
                    condition: $0.condition,
                    precipitationChance: $0.precipitationChance,
                    humidity: $0.humidity,
                    windSpeed: $0.windSpeed,
                    isDaylight: $0.isDaylight
                )
            },
            daily: snapshot.daily.map {
                VaneWidgetSnapshot.Day(
                    date: $0.date,
                    low: $0.low,
                    high: $0.high,
                    symbolName: $0.symbolName,
                    condition: $0.condition,
                    precipitationChance: $0.precipitationChance,
                    sunrise: $0.sunrise,
                    sunset: $0.sunset,
                    uvIndex: $0.uvIndex,
                    windSpeed: $0.windSpeed
                )
            },
            alertSummary: snapshot.alerts.sorted(by: WeatherAlertSnapshot.priorityOrder).first?.summary,
            guidanceHeadline: guidance?.headline ?? (canReuseGuidance ? cached?.guidanceHeadline : nil),
            guidanceDetail: guidance?.detail ?? (canReuseGuidance ? cached?.guidanceDetail : nil),
            guidanceSymbol: guidance?.action?.symbol ?? (guidance != nil ? "sparkles" : (canReuseGuidance ? cached?.guidanceSymbol : nil)),
            guidanceIsPersonalized: guidance?.isPersonalized ?? (canReuseGuidance ? cached?.guidanceIsPersonalized ?? false : false),
            guidanceIsEstimate: guidance?.isEstimate ?? (canReuseGuidance ? cached?.guidanceIsEstimate : nil),
            guidanceCalibrationLabel: guidance?.calibrationLabel ?? (canReuseGuidance ? cached?.guidanceCalibrationLabel : nil),
            guidanceActionText: guidance?.action?.text ?? (canReuseGuidance ? cached?.guidanceActionText : nil),
            temperatureUnit: UserDefaults.standard.string(forKey: "temperatureUnit") ?? TemperatureUnitPreference.localizedDefault.rawValue,
            windUnit: UserDefaults.standard.string(forKey: "windUnit") ?? WindUnitPreference.localizedDefault.rawValue,
            pressureUnit: UserDefaults.standard.string(forKey: "pressureUnit") ?? PressureUnitPreference.localizedDefault.rawValue,
            precipitationUnit: UserDefaults.standard.string(forKey: "precipitationUnit") ?? PrecipitationUnitPreference.localizedDefault.rawValue
        )

        guard (try? VaneWidgetDataStore.save(widgetSnapshot)) != nil else { return }
        WatchConnectivityBridge.shared.publish(widgetSnapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
