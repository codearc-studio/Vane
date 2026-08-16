import Foundation

struct WeatherFormatting: Sendable {
    let temperature: TemperatureUnitPreference
    let wind: WindUnitPreference
    let pressure: PressureUnitPreference
    let precipitation: PrecipitationUnitPreference
    let timeZone: TimeZone

    init(
        temperature: TemperatureUnitPreference = TemperatureUnitPreference(rawValue: UserDefaults.standard.string(forKey: "temperatureUnit") ?? "") ?? .fahrenheit,
        wind: WindUnitPreference = WindUnitPreference(rawValue: UserDefaults.standard.string(forKey: "windUnit") ?? "") ?? .milesPerHour,
        pressure: PressureUnitPreference = PressureUnitPreference(rawValue: UserDefaults.standard.string(forKey: "pressureUnit") ?? "") ?? .hectopascals,
        precipitation: PrecipitationUnitPreference = PrecipitationUnitPreference(rawValue: UserDefaults.standard.string(forKey: "precipitationUnit") ?? "") ?? .inches,
        timeZone: TimeZone = .current
    ) {
        self.temperature = temperature
        self.wind = wind
        self.pressure = pressure
        self.precipitation = precipitation
        self.timeZone = timeZone
    }

    func degrees(_ fahrenheit: Int, includeUnit: Bool = false) -> String {
        "\(temperature.value(fahrenheit))°\(includeUnit ? String(temperature.symbol.dropFirst()) : "")"
    }

    func degrees(_ fahrenheit: Double, includeUnit: Bool = false) -> String {
        degrees(Int(fahrenheit.rounded()), includeUnit: includeUnit)
    }

    func temperatureRange(low: Double, high: Double, includeUnit: Bool = true) -> String {
        "\(degrees(low))–\(degrees(high, includeUnit: includeUnit))"
    }

    func windSpeed(_ mph: Int) -> String { "\(wind.value(mph)) \(wind.title)" }
    func windRange(_ first: Int, _ second: Int) -> String { "\(wind.value(first)) / \(wind.value(second)) \(wind.title)" }
    func visibility(_ miles: Int) -> String { wind == .milesPerHour ? "\(miles) mi" : "\(Int((Double(miles) * 1.60934).rounded())) km" }
    func pressureValue(_ hPa: Int) -> String { pressure.formatted(hPa) }
    func precipitationAmount(_ inches: Double) -> String { precipitation.formatted(inches) }

    func hour(_ date: Date) -> String { formatted(date, template: "j") }
    func weekday(_ date: Date, wide: Bool = true) -> String { formatted(date, template: wide ? "EEEE" : "EEE") }
    func dayHeading(_ date: Date) -> String { formatted(date, template: "EEEEMMMMd") }
    func shortTime(_ date: Date) -> String { formatted(date, template: "jm") }
    func shortDateTime(_ date: Date) -> String { formatted(date, template: "MMMdhm") }

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private func formatted(_ date: Date, template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}
