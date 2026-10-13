import Foundation

/// Finds cities matching a free-text query.
///
/// Declared in the domain so that view models and use cases depend on an abstraction;
/// the Open-Meteo implementation lives in `ActivityData`, test doubles live in test targets.
public protocol CitySearchRepository: Sendable {
    /// Returns matches for `query`, best match first. An empty array is a valid result
    /// ("no cities called that"), not an error.
    func search(query: String) async throws -> [City]
}

/// Fetches the daily forecast for a city.
public protocol ForecastRepository: Sendable {
    /// Returns the forecast for the next 7 days starting today (in the city's time zone).
    func forecast(for city: City) async throws -> Forecast
}
