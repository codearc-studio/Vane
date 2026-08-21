import AppIntents

enum VaneWidgetFocus: String, AppEnum {
    case automatic
    case precipitation
    case feelsLike
    case wind
    case humidity
    case uvIndex

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Focus" }
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] {
        [
            .automatic: "Automatic",
            .precipitation: "Precipitation",
            .feelsLike: "Feels Like",
            .wind: "Wind",
            .humidity: "Humidity",
            .uvIndex: "UV Index"
        ]
    }

    var metric: VaneWidgetMetric { VaneWidgetMetric(rawValue: rawValue) ?? .automatic }
}

struct VaneWidgetConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Vane Widget" }
    static var description: IntentDescription { "Choose the condition Vane should emphasize." }

    @Parameter(title: "Focus", default: .automatic)
    var focus: VaneWidgetFocus
}

extension VaneWidgetConfiguration {
    static var automatic: VaneWidgetConfiguration {
        let intent = VaneWidgetConfiguration()
        intent.focus = .automatic
        return intent
    }

    static var rain: VaneWidgetConfiguration {
        let intent = VaneWidgetConfiguration()
        intent.focus = .precipitation
        return intent
    }
}
