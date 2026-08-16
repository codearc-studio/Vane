import CoreLocation
import Foundation

nonisolated protocol AirQualityProviding: Sendable {
    func currentAirQuality(latitude: Double, longitude: Double) async throws -> AirQualitySnapshot
}

nonisolated struct OpenMeteoAirQualityProvider: AirQualityProviding {
    private struct Response: Decodable {
        struct Current: Decodable {
            let time: TimeInterval
            let usAQI: Double
            let pm25: Double
            let pm10: Double
            let ozone: Double
            let nitrogenDioxide: Double

            enum CodingKeys: String, CodingKey {
                case time
                case usAQI = "us_aqi"
                case pm25 = "pm2_5"
                case pm10
                case ozone
                case nitrogenDioxide = "nitrogen_dioxide"
            }
        }

        let current: Current
    }

    func currentAirQuality(latitude: Double, longitude: Double) async throws -> AirQualitySnapshot {
        var components = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: latitude.formatted(.number.precision(.fractionLength(5)))),
            URLQueryItem(name: "longitude", value: longitude.formatted(.number.precision(.fractionLength(5)))),
            URLQueryItem(name: "current", value: "us_aqi,pm2_5,pm10,ozone,nitrogen_dioxide"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "timeformat", value: "unixtime")
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw URLError(.badServerResponse) }
        let current = try JSONDecoder().decode(Response.self, from: data).current
        return AirQualitySnapshot(
            index: Int(current.usAQI.rounded()),
            pm25: current.pm25,
            pm10: current.pm10,
            ozone: current.ozone,
            nitrogenDioxide: current.nitrogenDioxide,
            updatedAt: Date(timeIntervalSince1970: current.time)
        )
    }
}
