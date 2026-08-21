import SwiftUI
import WidgetKit

@main
struct VaneWidgetsBundle: WidgetBundle {
    var body: some Widget {
        VaneNowWidget()
        VaneForecastWidget()
        VaneDetailsWidget()
        VaneSunWidget()
        VaneSenseWidget()
        VaneWeatherLiveActivity()
    }
}
