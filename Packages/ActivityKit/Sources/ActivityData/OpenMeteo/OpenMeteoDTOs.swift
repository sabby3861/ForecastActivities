import Foundation

// MARK: - Geocoding API

/// Shape of `GET geocoding-api.open-meteo.com/v1/search`.
///
/// `results` is absent (not an empty array) when nothing matches, hence optional.
struct GeocodingResponseDTO: Decodable, Sendable {
    let results: [GeocodingResultDTO]?
}

struct GeocodingResultDTO: Decodable, Sendable {
    let id: Int
    let name: String
    let latitude: Double
    let longitude: Double
    let country: String?
    let admin1: String?
}

// MARK: - Forecast API

/// Shape of `GET api.open-meteo.com/v1/forecast` with the daily variables we request.
///
/// Open-Meteo returns **parallel arrays** (one entry per day) and individual entries can be
/// `null` when a model has no value, so every series is `[T?]`. The mapper is responsible
/// for turning this into one `DailyWeather` per day.
struct ForecastResponseDTO: Decodable, Sendable {
    let timezone: String
    let daily: DailySeriesDTO
}

struct DailySeriesDTO: Decodable, Sendable {
    let time: [String]
    let weatherCode: [Int?]
    let temperatureMax: [Double?]
    let temperatureMin: [Double?]
    let precipitationSum: [Double?]
    let snowfallSum: [Double?]
    let precipitationProbabilityMax: [Int?]
    let windSpeedMax: [Double?]

    /// `CaseIterable` so a test can assert the request's `daily=` list covers every key here.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case time
        case weatherCode = "weather_code"
        case temperatureMax = "temperature_2m_max"
        case temperatureMin = "temperature_2m_min"
        case precipitationSum = "precipitation_sum"
        case snowfallSum = "snowfall_sum"
        case precipitationProbabilityMax = "precipitation_probability_max"
        case windSpeedMax = "wind_speed_10m_max"
    }
}
