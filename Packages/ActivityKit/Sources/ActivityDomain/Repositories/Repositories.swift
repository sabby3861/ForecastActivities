import Foundation

/// Finds cities matching a free-text query.
public protocol CitySearchRepository: Sendable {
    /// Best match first. No matches is an empty array, not an error.
    func search(query: String) async throws -> [City]
}

/// Fetches the daily forecast for a city.
public protocol ForecastRepository: Sendable {
    /// Returns the forecast for the next 7 days starting today (in the city's time zone).
    func forecast(for city: City) async throws -> Forecast
}
