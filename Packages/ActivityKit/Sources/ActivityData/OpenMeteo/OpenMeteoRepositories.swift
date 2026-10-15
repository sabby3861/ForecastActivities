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

/// `ForecastRepository` backed by the Open-Meteo Forecast API, plus the Marine API for wave height.
public struct OpenMeteoForecastRepository: ForecastRepository {
    private let client: APIClient
    private let endpoints: OpenMeteoEndpoints

    public init(client: APIClient, endpoints: OpenMeteoEndpoints = OpenMeteoEndpoints()) {
        self.client = client
        self.endpoints = endpoints
    }

    /// Fetches the forecast and the marine data at the same time.
    public func forecast(for city: City) async throws -> Forecast {
        async let marineResponse = marine(for: city.coordinate)
        let response: ForecastResponseDTO = try await client.get(endpoints.forecast(for: city.coordinate))
        return try OpenMeteoMapper.forecast(from: response, marine: await marineResponse, for: city)
    }

    /// Marine data only affects surfing, so if it fails we carry on without it (`nil`)
    /// instead of failing the whole screen. Cancellation still propagates.
    private func marine(for coordinate: Coordinate) async throws -> MarineResponseDTO? {
        do {
            return try await client.get(endpoints.marine(for: coordinate))
        } catch AppError.cancelled {
            throw AppError.cancelled
        } catch {
            return nil
        }
    }
}
