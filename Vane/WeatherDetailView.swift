import MapKit
import SwiftUI

enum WeatherDetailKind: String, Identifiable, Hashable {
    case map, airQuality, wind, moon, sun, visibility, pressure
    var id: String { rawValue }
    var title: String {
        switch self {
        case .map: "Conditions Map"
        case .airQuality: "Air Quality"
        case .wind: "Wind"
        case .moon: "Moon"
        case .sun: "Sun"
        case .visibility: "Visibility"
        case .pressure: "Pressure"
        }
    }
}

struct WeatherDetailView: View {
    let kind: WeatherDetailKind
    let snapshot: ForecastSnapshot
    let formatting: WeatherFormatting

    var body: some View {
        ZStack {
            AtmosphericBackground(condition: snapshot.current)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    detailHeader
                    content
                }
                .padding(18)
                .padding(.bottom, 60)
                .containerRelativeFrame(.horizontal)
            }.scrollIndicators(.hidden)
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            SectionKicker(title: snapshot.locationName)
            Text(kind.title).font(.largeTitle.bold())
            Text("Updated \(formatting.shortTime(snapshot.updatedAt))").font(.caption).foregroundStyle(VaneTheme.muted)
        }
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .map: ConditionsMap(snapshot: snapshot, formatting: formatting)
        case .airQuality: airQuality
        case .wind: wind
        case .moon: moon
        case .sun: sun
        case .visibility: visibility
        case .pressure: pressure
        }
    }

    private var wind: some View {
        VStack(spacing: 18) {
            GlassCard { WindCompass(speed: snapshot.current.windSpeed, gust: snapshot.current.windGust, direction: snapshot.current.windDirection, degrees: snapshot.current.windDirectionDegrees, formatting: formatting).padding(20) }
            GlassCard { VStack(alignment: .leading, spacing: 14) {
                detailLine("Sustained wind", formatting.windSpeed(snapshot.current.windSpeed))
                Divider()
                detailLine("Gusts", formatting.windSpeed(snapshot.current.windGust))
                Divider()
                detailLine("Direction", "\(snapshot.current.windDirection) · \(Int(snapshot.current.windDirectionDegrees.rounded()))°")
                Text(windDescription).font(.subheadline).foregroundStyle(VaneTheme.muted)
            }.padding(20) }
        }
    }

    @ViewBuilder private var airQuality: some View {
        if let air = snapshot.airQuality {
            GlassCard { VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) { Text("\(air.index)").font(.system(size: 72, weight: .medium, design: .rounded)); Text(air.category).font(.title3.bold()).foregroundStyle(aqiColor(air.index)) }
                AQIBar(value: air.index)
                Text(air.guidance).font(.headline)
                Divider()
                detailLine("Fine particles (PM₂.₅)", air.pm25.formatted(.number.precision(.fractionLength(1))) + " μg/m³")
                detailLine("Particles (PM₁₀)", air.pm10.formatted(.number.precision(.fractionLength(1))) + " μg/m³")
                detailLine("Ozone", air.ozone.formatted(.number.precision(.fractionLength(1))) + " μg/m³")
                detailLine("Nitrogen dioxide", air.nitrogenDioxide.formatted(.number.precision(.fractionLength(1))) + " μg/m³")
            }.padding(20) }
            Text("Modeled U.S. AQI from CAMS atmospheric forecasts via Open-Meteo. It can differ from Apple Weather or a nearby monitoring station.").font(.caption).foregroundStyle(VaneTheme.muted)
            HStack { Link("Open-Meteo", destination: URL(string: "https://open-meteo.com/en/docs/air-quality-api")!); Text("·"); Link("CAMS", destination: URL(string: "https://atmosphere.copernicus.eu/")!) }.font(.caption.bold())
        } else {
            ContentUnavailableView("AQI unavailable", systemImage: "aqi.medium", description: Text("Vane couldn’t load the separately sourced air-quality model for this location."))
        }
    }

    private var moon: some View {
        let day = snapshot.daily.first
        return GlassCard { VStack(alignment: .leading, spacing: 18) {
            HStack { Image(systemName: moonSymbol(day?.moonPhase ?? "")).font(.system(size: 72)).symbolRenderingMode(.hierarchical).foregroundStyle(VaneTheme.blue); Spacer(); Text(day?.moonPhase.isEmpty == false ? day!.moonPhase : "Phase unavailable").font(.title2.bold()).multilineTextAlignment(.trailing) }
            Divider()
            detailLine("Moonrise", day?.moonrise.map(formatting.shortTime) ?? "Not during this day")
            detailLine("Moonset", day?.moonset.map(formatting.shortTime) ?? "Not during this day")
            Text("Moonrise and moonset can fall outside a calendar day, so one of these may not occur today.").font(.caption).foregroundStyle(VaneTheme.muted)
        }.padding(20) }
    }

    private var sun: some View {
        let day = snapshot.daily.first
        return VStack(spacing: 18) {
            GlassCard { SunArc(day: day, formatting: formatting).padding(20) }
            GlassCard { VStack(alignment: .leading, spacing: 13) {
                detailLine("First light", day?.civilDawn.map(formatting.shortTime) ?? "—")
                detailLine("Sunrise", day?.sunrise.map(formatting.shortTime) ?? "—")
                detailLine("Solar noon", day?.solarNoon.map(formatting.shortTime) ?? "—")
                detailLine("Sunset", day?.sunset.map(formatting.shortTime) ?? "—")
                detailLine("Last light", day?.civilDusk.map(formatting.shortTime) ?? "—")
                Divider()
                detailLine("UV index", "\(snapshot.current.uvIndex)")
            }.padding(20) }
        }
    }

    private var visibility: some View {
        GlassCard { VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "eye.fill").font(.system(size: 44)).foregroundStyle(VaneTheme.blue)
            Text(formatting.visibility(snapshot.current.visibility)).font(.system(size: 60, weight: .medium, design: .rounded))
            Text(visibilityDescription).font(.title3.bold())
            Text("Visibility is the estimated horizontal distance at which prominent objects can be seen. Fog, haze, precipitation and smoke can reduce it.").foregroundStyle(VaneTheme.muted)
        }.padding(20) }
    }

    private var pressure: some View {
        VStack(spacing: 18) {
            GlassCard { PressureGauge(pressure: snapshot.current.pressure, trend: snapshot.current.pressureTrend, formatting: formatting).padding(20) }
            GlassCard { VStack(alignment: .leading, spacing: 10) {
                Text("What it means").font(.headline)
                Text("Pressure is adjusted to sea level so locations can be compared. The trend is usually more useful than a single reading: falling pressure can accompany an approaching weather system, while rising pressure often follows one.").font(.subheadline).foregroundStyle(VaneTheme.muted)
            }.padding(20) }
        }
    }

    private func detailLine(_ title: String, _ value: String) -> some View { HStack(alignment: .firstTextBaseline) { Text(title).foregroundStyle(VaneTheme.muted); Spacer(); Text(value).fontWeight(.semibold).multilineTextAlignment(.trailing) } }
    private var windDescription: String { snapshot.current.windSpeed < 5 ? "Light air with little sustained movement." : snapshot.current.windSpeed < 15 ? "A noticeable breeze, with stronger periods shown by the gust value." : "Wind is strong enough to noticeably affect outdoor comfort." }
    private var visibilityDescription: String { snapshot.current.visibility >= 10 ? "Very clear" : snapshot.current.visibility >= 6 ? "Generally clear" : snapshot.current.visibility >= 3 ? "Reduced visibility" : "Poor visibility" }
    private func moonSymbol(_ phase: String) -> String { phase.lowercased().contains("full") ? "moonphase.full.moon" : phase.lowercased().contains("new") ? "moonphase.new.moon" : phase.lowercased().contains("waning") ? "moonphase.waning.crescent" : "moonphase.waxing.crescent" }
    private func aqiColor(_ value: Int) -> Color { value <= 50 ? .green : value <= 100 ? .yellow : value <= 150 ? .orange : .red }
}

private struct ConditionsMap: View {
    enum Layer: String, CaseIterable, Identifiable { case precipitation, temperature, airQuality; var id: String { rawValue }; var title: String { self == .airQuality ? "AQI" : rawValue.capitalized } }
    let snapshot: ForecastSnapshot
    let formatting: WeatherFormatting
    @State private var layer: Layer = .precipitation

    var body: some View {
        VStack(spacing: 16) {
            Picker("Map information", selection: $layer) { ForEach(Layer.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
            Map(initialPosition: .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: snapshot.latitude, longitude: snapshot.longitude), latitudinalMeters: 180_000, longitudinalMeters: 180_000))) {
                Annotation(snapshot.locationName, coordinate: CLLocationCoordinate2D(latitude: snapshot.latitude, longitude: snapshot.longitude)) {
                    VStack(spacing: 3) { Image(systemName: layerSymbol).font(.title2); Text(layerValue).font(.headline) }.padding(12).foregroundStyle(.white).background(VaneTheme.blue, in: RoundedRectangle(cornerRadius: 16)).shadow(radius: 5)
                }
            }
            .frame(height: 390).clipShape(RoundedRectangle(cornerRadius: 26))
            Text(layerNote).font(.caption).foregroundStyle(VaneTheme.muted)
        }
    }

    private var layerSymbol: String { layer == .precipitation ? "drop.fill" : layer == .temperature ? snapshot.current.symbolName : "aqi.medium" }
    private var layerValue: String { layer == .precipitation ? snapshot.current.precipitationChance.formatted(.percent.precision(.fractionLength(0))) : layer == .temperature ? formatting.degrees(snapshot.current.temperature) : snapshot.airQuality.map { "\($0.index)" } ?? "—" }
    private var layerNote: String { layer == .precipitation ? "Forecast chance at the selected location. Apple’s animated radar layer is not available through WeatherKit." : layer == .temperature ? "Current Apple Weather temperature at the selected location." : "Modeled AQI at the selected location from CAMS via Open-Meteo; this is not Apple’s AQI layer." }
}

private struct WindCompass: View {
    let speed: Int; let gust: Int; let direction: String; let degrees: Double; let formatting: WeatherFormatting
    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().stroke(VaneTheme.blue.opacity(0.22), lineWidth: 18)
                ForEach(0..<36, id: \.self) { tick in Capsule().fill(VaneTheme.muted.opacity(tick % 9 == 0 ? 0.9 : 0.28)).frame(width: 2, height: tick % 9 == 0 ? 12 : 7).offset(y: -105).rotationEffect(.degrees(Double(tick) * 10)) }
                VStack { Text(direction).font(.headline).foregroundStyle(VaneTheme.blue); Text(formatting.windSpeed(speed)).font(.title.bold()); Text("gusts \(formatting.windSpeed(gust))").font(.caption).foregroundStyle(VaneTheme.muted) }
                Image(systemName: "location.north.fill").font(.system(size: 34)).foregroundStyle(VaneTheme.blue).offset(y: -75).rotationEffect(.degrees(degrees))
            }.frame(width: 230, height: 230)
        }
    }
}

private struct PressureGauge: View {
    let pressure: Int; let trend: String; let formatting: WeatherFormatting
    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().trim(from: 0.12, to: 0.88).stroke(VaneTheme.blue.opacity(0.18), style: StrokeStyle(lineWidth: 18, lineCap: .round)).rotationEffect(.degrees(90))
                Circle().trim(from: 0.12, to: 0.12 + 0.76 * min(1, max(0, Double(pressure - 970) / 80))).stroke(VaneTheme.blue, style: StrokeStyle(lineWidth: 18, lineCap: .round)).rotationEffect(.degrees(90))
                VStack { Image(systemName: trend.lowercased().contains("fall") ? "arrow.down" : trend.lowercased().contains("ris") ? "arrow.up" : "arrow.right"); Text(formatting.pressure.formatted(pressure)).font(.title.bold()).minimumScaleFactor(0.7); Text(trend).foregroundStyle(VaneTheme.muted) }
            }.frame(width: 240, height: 240)
            HStack { Text("Low"); Spacer(); Text("Typical sea-level range"); Spacer(); Text("High") }.font(.caption).foregroundStyle(VaneTheme.muted)
        }
    }
}

private struct AQIBar: View {
    let value: Int
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                LinearGradient(colors: [.green, .yellow, .orange, .red, .purple], startPoint: .leading, endPoint: .trailing).frame(height: 10).clipShape(Capsule())
                Circle().fill(.white).stroke(.black.opacity(0.3), lineWidth: 1).frame(width: 18, height: 18).offset(x: min(proxy.size.width - 18, max(0, proxy.size.width * CGFloat(min(value, 300)) / 300 - 9)))
            }
        }.frame(height: 18)
    }
}

private struct SunArc: View {
    let day: DailyConditions?; let formatting: WeatherFormatting
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "sun.max.fill").font(.system(size: 58)).symbolRenderingMode(.multicolor)
            Text(day?.sunset.map { "Sunset \(formatting.shortTime($0))" } ?? "Sun times unavailable").font(.title2.bold())
            HStack { Text(day?.sunrise.map(formatting.shortTime) ?? "—"); Spacer(); Text("Solar noon"); Spacer(); Text(day?.sunset.map(formatting.shortTime) ?? "—") }.font(.caption).foregroundStyle(VaneTheme.muted)
        }
    }
}
