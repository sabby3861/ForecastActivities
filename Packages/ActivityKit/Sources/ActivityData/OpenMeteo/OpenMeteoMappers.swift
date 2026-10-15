import ActivityDomain
import Foundation

/// Converts Open-Meteo DTOs into domain models.
///
/// Mapping lives in its own type (not inside the DTOs or repositories) so it can be tested
/// with hand-written fixtures and so the DTOs stay dumb mirrors of the wire format.
enum OpenMeteoMapper {
    static func city(from dto: GeocodingResultDTO) -> City {
        City(
            id: dto.id,
            name: dto.name,
            region: dto.admin1,
            country: dto.country,
            coordinate: Coordinate(latitude: dto.latitude, longitude: dto.longitude)
        )
    }

    /// Builds a `Forecast`, dropping any day whose essential fields are missing.
    ///
    /// Policy for `null` entries:
    /// - date, max/min temperature, weather code → required; the day is dropped without them.
    /// - everything else → passed through as `nil`, and the scoring leaves it out.
    ///
    /// Throws `AppError.noForecastAvailable` if no day survives, and `AppError.invalidResponse`
    /// if the arrays are not the same length (a broken contract rather than missing data).
    static func forecast(from dto: ForecastResponseDTO, for city: City) throws -> Forecast {
        let timeZone = TimeZone(identifier: dto.timezone) ?? .gmt
        let series = dto.daily
        let count = series.time.count

        let lengths = [
            series.weatherCode.count, series.temperatureMax.count, series.temperatureMin.count,
            series.precipitationSum.count, series.snowfallSum.count,
            series.precipitationProbabilityMax.count, series.windSpeedMax.count,
        ]
        guard lengths.allSatisfy({ $0 == count }) else {
            throw AppError.invalidResponse
        }

        let parser = DayParser(timeZone: timeZone)

        let days: [DailyWeather] = (0..<count).compactMap { index in
            guard
                let date = parser.date(from: series.time[index]),
                let maxTemp = series.temperatureMax[index],
                let minTemp = series.temperatureMin[index],
                let code = series.weatherCode[index]
            else {
                return nil
            }
            return DailyWeather(
                date: date,
                maxTemperatureC: maxTemp,
                minTemperatureC: minTemp,
                condition: WeatherCondition(wmoCode: code),
                precipitationMM: series.precipitationSum[index],
                snowfallCM: series.snowfallSum[index],
                precipitationProbability: series.precipitationProbabilityMax[index],
                maxWindSpeedKmh: series.windSpeedMax[index]
            )
        }

        guard !days.isEmpty else {
            throw AppError.noForecastAvailable
        }
        return Forecast(city: city, timeZone: timeZone, days: days)
    }
}

/// Parses Open-Meteo's `yyyy-MM-dd` day strings as local midnight in the given zone.
///
/// A struct wrapping `DateFormatter` (which is not `Sendable`) so the formatter is created
/// once per mapping call and never shared across threads.
private struct DayParser {
    private let formatter: DateFormatter

    init(timeZone: TimeZone) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        self.formatter = formatter
    }

    func date(from string: String) -> Date? {
        formatter.date(from: string)
    }
}
