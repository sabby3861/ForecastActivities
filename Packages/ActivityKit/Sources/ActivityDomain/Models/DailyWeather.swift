import Foundation

/// Coarse weather condition derived from the WMO weather code Open-Meteo returns.
///
/// We collapse ~30 WMO codes into a handful of buckets because the scoring rules only care
/// about "is it raining / snowing / stormy / clear". Keeping the raw code in `.unknown`
/// means nothing is silently lost if Open-Meteo adds codes.
public enum WeatherCondition: Hashable, Sendable {
    case clear
    case partlyCloudy
    case overcast
    case fog
    case drizzle
    case rain
    case snow
    case showers
    case thunderstorm
    case unknown(code: Int)

    /// Maps a WMO 4677 weather code (as used by Open-Meteo) to a condition bucket.
    public init(wmoCode: Int) {
        switch wmoCode {
        case 0: self = .clear
        case 1, 2: self = .partlyCloudy
        case 3: self = .overcast
        case 45, 48: self = .fog
        case 51, 53, 55, 56, 57: self = .drizzle
        case 61, 63, 65, 66, 67: self = .rain
        case 71, 73, 75, 77, 85, 86: self = .snow
        case 80, 81, 82: self = .showers
        case 95, 96, 99: self = .thunderstorm
        default: self = .unknown(code: wmoCode)
        }
    }

    /// True for any condition where water is falling from the sky.
    public var isWet: Bool {
        switch self {
        case .drizzle, .rain, .showers, .snow, .thunderstorm: return true
        case .clear, .partlyCloudy, .overcast, .fog, .unknown: return false
        }
    }
}

/// What the sea is doing near the location on a given day.
public enum SeaState: Hashable, Sendable {
    /// Coastal, with a wave forecast for the day.
    case waves(heightM: Double)
    /// The marine model has no sea cell here, so the location is inland.
    case noSea
    /// We couldn't get marine data, so we don't know.
    case unknown
}

/// One day of forecast, in the units the scoring rules use.
///
/// Date, temperatures and weather code are required; the mapper drops a day without them.
/// Everything else is optional because the API can return `null` for it, and a missing
/// value is left out of the score rather than guessed.
public struct DailyWeather: Identifiable, Hashable, Sendable {
    /// Local midnight for the forecast day, in the location's time zone.
    public let date: Date
    public let maxTemperatureC: Double
    public let minTemperatureC: Double
    public let condition: WeatherCondition
    /// Total precipitation (rain + snow water equivalent) in millimetres.
    public let precipitationMM: Double?
    /// Fresh snowfall in centimetres.
    public let snowfallCM: Double?
    /// Snow already on the ground, in metres.
    public let snowDepthM: Double?
    /// Maximum precipitation probability for the day, 0–100.
    public let precipitationProbability: Int?
    /// Maximum 10 m wind speed in km/h.
    public let maxWindSpeedKmh: Double?
    public let sea: SeaState

    public var id: Date { date }

    public init(
        date: Date,
        maxTemperatureC: Double,
        minTemperatureC: Double,
        condition: WeatherCondition,
        precipitationMM: Double?,
        snowfallCM: Double?,
        snowDepthM: Double?,
        precipitationProbability: Int?,
        maxWindSpeedKmh: Double?,
        sea: SeaState
    ) {
        self.date = date
        self.maxTemperatureC = maxTemperatureC
        self.minTemperatureC = minTemperatureC
        self.condition = condition
        self.precipitationMM = precipitationMM
        self.snowfallCM = snowfallCM
        self.snowDepthM = snowDepthM
        self.precipitationProbability = precipitationProbability.map { min(max($0, 0), 100) }
        self.maxWindSpeedKmh = maxWindSpeedKmh
        self.sea = sea
    }
}

/// A multi-day forecast for a city.
public struct Forecast: Hashable, Sendable {
    public let city: City
    /// The location's time zone, used to label days (Sydney's Tuesday, not the device's).
    public let timeZone: TimeZone
    public let days: [DailyWeather]

    public init(city: City, timeZone: TimeZone, days: [DailyWeather]) {
        self.city = city
        self.timeZone = timeZone
        self.days = days
    }
}
