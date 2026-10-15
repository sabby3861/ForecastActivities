import ActivityDomain
import Foundation
@testable import ActivityData

/// Real-shaped Open-Meteo payloads, kept as string literals so tests have zero resource
/// bundling concerns and the JSON is readable right next to the assertions.
enum Fixtures {
    static let city = City(
        id: 2643743,
        name: "London",
        region: "England",
        country: "United Kingdom",
        coordinate: Coordinate(latitude: 51.50853, longitude: -0.12574)
    )

    static let geocodingLondon = Data("""
    {
      "results": [
        {
          "id": 2643743, "name": "London", "latitude": 51.50853, "longitude": -0.12574,
          "elevation": 25.0, "feature_code": "PPLC", "country_code": "GB",
          "timezone": "Europe/London", "population": 8961989,
          "country": "United Kingdom", "admin1": "England"
        },
        {
          "id": 6058560, "name": "London", "latitude": 42.98339, "longitude": -81.23304,
          "country": "Canada", "admin1": "Ontario"
        }
      ],
      "generationtime_ms": 0.8
    }
    """.utf8)

    /// Open-Meteo omits `results` entirely when there are no matches.
    static let geocodingNoResults = Data("""
    { "generationtime_ms": 0.4 }
    """.utf8)

    static let forecastSevenDays = Data("""
    {
      "latitude": 51.5, "longitude": -0.12, "generationtime_ms": 0.3, "utc_offset_seconds": 3600,
      "timezone": "Europe/London", "timezone_abbreviation": "BST", "elevation": 23.0,
      "daily_units": {
        "time": "iso8601", "weather_code": "wmo code", "temperature_2m_max": "°C",
        "temperature_2m_min": "°C", "precipitation_sum": "mm", "snowfall_sum": "cm",
        "precipitation_probability_max": "%", "wind_speed_10m_max": "km/h", "snow_depth_max": "m"
      },
      "daily": {
        "time": ["2026-10-13","2026-10-14","2026-10-15","2026-10-16","2026-10-17","2026-10-18","2026-10-19"],
        "weather_code": [3, 61, 80, 1, 0, 2, 95],
        "temperature_2m_max": [15.2, 13.8, 14.1, 16.5, 17.9, 18.3, 12.0],
        "temperature_2m_min": [8.1, 9.4, 7.7, 6.9, 8.8, 10.2, 7.5],
        "precipitation_sum": [0.0, 6.4, 2.1, 0.0, 0.0, 0.2, 11.8],
        "snowfall_sum": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
        "precipitation_probability_max": [10, 85, 60, 15, 5, 20, 95],
        "wind_speed_10m_max": [18.4, 27.0, 31.3, 14.8, 11.2, 16.6, 42.1],
        "snow_depth_max": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
      }
    }
    """.utf8)

    /// Day 2 is missing its max temperature and day 4 its weather code; both must be dropped.
    /// Day 3 has null precipitation, which should default to zero and be kept.
    static let forecastWithNulls = Data("""
    {
      "timezone": "America/New_York",
      "daily": {
        "time": ["2026-10-13","2026-10-14","2026-10-15","2026-10-16"],
        "weather_code": [0, 1, 2, null],
        "temperature_2m_max": [20.0, null, 22.0, 23.0],
        "temperature_2m_min": [10.0, 11.0, 12.0, 13.0],
        "precipitation_sum": [0.0, 0.0, null, 0.0],
        "snowfall_sum": [0.0, 0.0, 0.0, 0.0],
        "precipitation_probability_max": [5, 10, null, 20],
        "wind_speed_10m_max": [10.0, 11.0, null, 13.0],
        "snow_depth_max": [0.0, 0.0, null, 0.0]
      }
    }
    """.utf8)

    static let forecastAllNull = Data("""
    {
      "timezone": "UTC",
      "daily": {
        "time": ["2026-10-13"],
        "weather_code": [null],
        "temperature_2m_max": [null],
        "temperature_2m_min": [null],
        "precipitation_sum": [null],
        "snowfall_sum": [null],
        "precipitation_probability_max": [null],
        "wind_speed_10m_max": [null],
        "snow_depth_max": [null]
      }
    }
    """.utf8)

    static let forecastMismatchedLengths = Data("""
    {
      "timezone": "UTC",
      "daily": {
        "time": ["2026-10-13","2026-10-14"],
        "weather_code": [0],
        "temperature_2m_max": [20.0, 21.0],
        "temperature_2m_min": [10.0, 11.0],
        "precipitation_sum": [0.0, 0.0],
        "snowfall_sum": [0.0, 0.0],
        "precipitation_probability_max": [5, 5],
        "wind_speed_10m_max": [10.0, 10.0],
        "snow_depth_max": [0.0, 0.0]
      }
    }
    """.utf8)

    // MARK: - Marine

    /// Same days as `forecastSevenDays`. Day 3 has no value, which should come out as unknown.
    static let marineCoastal = Data("""
    {
      "timezone": "Europe/London",
      "daily": {
        "time": ["2026-10-13","2026-10-14","2026-10-15","2026-10-16","2026-10-17","2026-10-18","2026-10-19"],
        "wave_height_max": [1.2, 1.6, null, 0.8, 0.6, 1.0, 2.4]
      }
    }
    """.utf8)

    /// What the Marine API returns for an inland point: the days, but every value null.
    static let marineInland = Data("""
    {
      "timezone": "Europe/London",
      "daily": {
        "time": ["2026-10-13","2026-10-14","2026-10-15","2026-10-16","2026-10-17","2026-10-18","2026-10-19"],
        "wave_height_max": [null, null, null, null, null, null, null]
      }
    }
    """.utf8)
}
