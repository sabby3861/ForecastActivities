import ActivityDomain
import Foundation

/// Builds the three Open-Meteo requests the app needs: city search, forecast and marine.
///
/// Base URLs are injectable so tests (and a future staging/proxy setup) can point elsewhere
/// without touching the request-building logic.
public struct OpenMeteoEndpoints: Sendable {
    public static let productionGeocodingBase = URL(string: "https://geocoding-api.open-meteo.com")!
    public static let productionForecastBase = URL(string: "https://api.open-meteo.com")!
    public static let productionMarineBase = URL(string: "https://marine-api.open-meteo.com")!

    /// The daily variables the scoring rules consume. Declared once so the request and the
    /// DTO cannot drift apart silently.
    public static let dailyVariables = [
        "weather_code",
        "temperature_2m_max",
        "temperature_2m_min",
        "precipitation_sum",
        "snowfall_sum",
        "precipitation_probability_max",
        "wind_speed_10m_max",
        "snow_depth_max",
    ]

    public static let marineDailyVariables = ["wave_height_max"]

    public static let forecastDays = 7

    private let geocodingBase: URL
    private let forecastBase: URL
    private let marineBase: URL

    public init(
        geocodingBase: URL = OpenMeteoEndpoints.productionGeocodingBase,
        forecastBase: URL = OpenMeteoEndpoints.productionForecastBase,
        marineBase: URL = OpenMeteoEndpoints.productionMarineBase
    ) {
        self.geocodingBase = geocodingBase
        self.forecastBase = forecastBase
        self.marineBase = marineBase
    }

    /// `GET /v1/search?name=…&count=10&language=en&format=json`
    public func citySearch(query: String, limit: Int = 10) -> URLRequest {
        Self.request(base: geocodingBase, path: "v1/search", queryItems: [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: String(limit)),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json"),
        ])
    }

    /// `GET /v1/forecast?latitude=…&longitude=…&daily=…&timezone=auto&forecast_days=7`
    ///
    /// `timezone=auto` makes Open-Meteo return day boundaries in the location's own zone,
    /// which is what a traveller expects ("Tuesday in Tokyo", not "Tuesday in London").
    public func forecast(for coordinate: Coordinate) -> URLRequest {
        Self.request(base: forecastBase, path: "v1/forecast", queryItems: [
            URLQueryItem(name: "latitude", value: Self.format(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: Self.format(coordinate.longitude)),
            URLQueryItem(name: "daily", value: Self.dailyVariables.joined(separator: ",")),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: String(Self.forecastDays)),
            URLQueryItem(name: "wind_speed_unit", value: "kmh"),
            URLQueryItem(name: "temperature_unit", value: "celsius"),
            URLQueryItem(name: "precipitation_unit", value: "mm"),
        ])
    }

    /// `GET /v1/marine?latitude=…&longitude=…&daily=wave_height_max&timezone=auto&forecast_days=7`
    ///
    /// Same coordinate, zone and window as the forecast, so the days line up by date string.
    public func marine(for coordinate: Coordinate) -> URLRequest {
        Self.request(base: marineBase, path: "v1/marine", queryItems: [
            URLQueryItem(name: "latitude", value: Self.format(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: Self.format(coordinate.longitude)),
            URLQueryItem(name: "daily", value: Self.marineDailyVariables.joined(separator: ",")),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: String(Self.forecastDays)),
        ])
    }

    /// Assembles a GET request. Every input is a compile-time constant or a `URLQueryItem`
    /// (which `URLComponents` percent-encodes), so a `nil` URL here is a programmer error —
    /// hence a `preconditionFailure` with a message rather than a bare `!`.
    private static func request(base: URL, path: String, queryItems: [URLQueryItem]) -> URLRequest {
        guard var components = URLComponents(url: base.appending(path: path), resolvingAgainstBaseURL: false) else {
            preconditionFailure("Base URL \(base) is not a valid URLComponents source")
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            preconditionFailure("Could not build URL from \(components)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        return request
    }

    /// Locale-independent decimal formatting: a device set to a comma-decimal locale must
    /// still send `51.5` and not `51,5`.
    private static func format(_ value: Double) -> String {
        String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
