import SwiftUI
import WidgetKit

@main
struct VaneWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        VaneWatchNowComplication()
        VaneWatchConditionsComplication()
        VaneWatchSunComplication()
        VaneWatchSenseComplication()
    }
}
