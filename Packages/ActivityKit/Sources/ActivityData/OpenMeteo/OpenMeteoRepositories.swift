import ActivityDomain
import Foundation

/// `CitySearchRepository` backed by the Open-Meteo Geocoding API.
public struct OpenMeteoCitySearchRepository: CitySearchRepository {
    private let client: APIClient
    private let endpoints: OpenMeteoEndpoints

    public init(client: APIClient, endpoints: OpenMeteoEndpoints = OpenMeteoEndpoints()) {
        self.client = client
        self.endpoints = endpoints
    }

    public func search(query: String) async throws -> [City] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // The API rejects queries shorter than 2 characters; short-circuit rather than
        // pay for a round trip that will 400.
        guard trimmed.count >= 2 else { return [] }

        let response: GeocodingResponseDTO = try await client.get(endpoints.citySearch(query: trimmed))
        return (response.results ?? []).map(OpenMeteoMapper.city(from:))
    }
}

/// `ForecastRepository` backed by the Open-Meteo Forecast API.
public struct OpenMeteoForecastRepository: ForecastRepository {
    private let client: APIClient
    private let endpoints: OpenMeteoEndpoints

    public init(client: APIClient, endpoints: OpenMeteoEndpoints = OpenMeteoEndpoints()) {
        self.client = client
        self.endpoints = endpoints
    }

    public func forecast(for city: City) async throws -> Forecast {
        let response: ForecastResponseDTO = try await client.get(endpoints.forecast(for: city.coordinate))
        return try OpenMeteoMapper.forecast(from: response, for: city)
    }
}
