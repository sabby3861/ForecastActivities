import ActivityDomain
import Foundation

/// Builders that keep test bodies focused on the one or two fields under test.
enum Fixture {
    static func day(
        offset: Int = 0,
        maxTemp: Double = 18,
        minTemp: Double = 10,
        precipitationMM: Double? = 0,
        snowfallCM: Double? = 0,
        precipitationProbability: Int? = 10,
        wind: Double? = 12,
        condition: WeatherCondition = .clear
    ) -> DailyWeather {
        DailyWeather(
            date: date(offset: offset),
            maxTemperatureC: maxTemp,
            minTemperatureC: minTemp,
            condition: condition,
            precipitationMM: precipitationMM,
            snowfallCM: snowfallCM,
            precipitationProbability: precipitationProbability,
            maxWindSpeedKmh: wind
        )
    }

    /// Deterministic dates: 2026-10-13 + offset days, at UTC midnight.
    static func date(offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_791_849_600 + Double(offset) * 86_400)
    }

    static let city = City(
        id: 1,
        name: "Testville",
        region: "Region",
        country: "Country",
        coordinate: Coordinate(latitude: 1, longitude: 2)
    )
}
