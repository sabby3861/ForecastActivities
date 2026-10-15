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

    /// Builds a `Forecast` from the forecast response and, if we got one, the marine response.
    ///
    /// Policy for `null` entries:
    /// - date, max/min temperature, weather code → required; the day is dropped without them.
    /// - everything else → passed through as `nil`, and the scoring leaves it out.
    ///
    /// Throws `AppError.noForecastAvailable` if no day survives, and `AppError.invalidResponse`
    /// if the forecast arrays have different lengths.
    static func forecast(from dto: ForecastResponseDTO, marine: MarineResponseDTO?, for city: City) throws -> Forecast {
        let timeZone = TimeZone(identifier: dto.timezone) ?? .gmt
        let series = dto.daily
        let count = series.time.count

        let lengths = [
            series.weatherCode.count, series.temperatureMax.count, series.temperatureMin.count,
            series.precipitationSum.count, series.snowfallSum.count,
            series.precipitationProbabilityMax.count, series.windSpeedMax.count, series.snowDepthMax.count,
        ]
        guard lengths.allSatisfy({ $0 == count }) else {
            throw AppError.invalidResponse
        }

        let parser = DayParser(timeZone: timeZone)
        let sea = SeaLookup(marine)

        let days: [DailyWeather] = (0..<count).compactMap { index in
            let day = series.time[index]
            guard
                let date = parser.date(from: day),
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
                snowDepthM: series.snowDepthMax[index],
                precipitationProbability: series.precipitationProbabilityMax[index],
                maxWindSpeedKmh: series.windSpeedMax[index],
                sea: sea.state(on: day)
            )
        }

        guard !days.isEmpty else {
            throw AppError.noForecastAvailable
        }
        return Forecast(city: city, timeZone: timeZone, days: days)
    }
}

/// Turns the marine response into a `SeaState` per forecast day, matched on the date string.
///
/// - No response (the request failed) or a malformed one → `.unknown` for every day.
/// - Every wave value `null` → the point is inland → `.noSea` for every day.
/// - Otherwise → `.waves` where there's a value, `.unknown` where there isn't.
private struct SeaLookup {
    private enum Kind {
        case unknown
        case inland
        case coastal([String: Double])
    }

    private let kind: Kind

    init(_ dto: MarineResponseDTO?) {
        guard let series = dto?.daily, series.time.count == series.waveHeightMax.count else {
            kind = .unknown
            return
        }
        var heights: [String: Double] = [:]
        for (day, height) in zip(series.time, series.waveHeightMax) {
            if let height { heights[day] = height }
        }
        kind = heights.isEmpty ? .inland : .coastal(heights)
    }

    func state(on day: String) -> SeaState {
        switch kind {
        case .unknown: return .unknown
        case .inland: return .noSea
        case .coastal(let heights): return heights[day].map { .waves(heightM: $0) } ?? .unknown
        }
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
