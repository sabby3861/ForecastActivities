import Foundation

/// One rule object per activity. Each is a pure function of a single day's weather,
/// which keeps the rules trivially unit-testable and lets product tweak one activity
/// without touching the others.
///
/// Every scorer declares its thresholds and weights as named constants rather than inline
/// literals, so the "why" of each number is visible at the point it is defined and a
/// reviewer can audit the rule without reading the arithmetic.
public protocol ActivityScoring: Sendable {
    var activity: Activity { get }
    func score(for day: DailyWeather) -> Score
}

// MARK: - Skiing

/// Skiing wants cold air, ideally fresh snow, little rain and manageable wind.
///
/// Known limitation: the Open-Meteo forecast endpoint has no snow-depth or elevation data,
/// so a cold, dry week in a flat city still scores moderately. See README → Assumptions.
public struct SkiingScorer: ActivityScoring {
    enum Rule {
        /// Daytime highs that keep snow firm. Above ~2 °C it starts to slush.
        static let idealMaxTemperature: ClosedRange<Double> = -15...2
        static let temperatureTolerance: Double = 6
        /// 10 cm of fresh snow is a "powder day"; more does not score higher.
        static let snowfallSaturationCM: Double = 10
        /// 10 mm of rain on a ski day writes it off.
        static let rainSaturationMM: Double = 10
        /// Rain (as opposed to snow) is only possible above this temperature.
        static let rainThresholdC: Double = 1
        static let idealWind: ClosedRange<Double> = 0...25
        static let windTolerance: Double = 40

        static let coldWeight: Double = 45
        static let snowWeight: Double = 25
        static let noRainWeight: Double = 15
        static let windWeight: Double = 15
    }

    public let activity = Activity.skiing
    public init() {}

    public func score(for day: DailyWeather) -> Score {
        let isRaining = day.condition.isWet
            && day.condition != .snow
            && day.maxTemperatureC > Rule.rainThresholdC
        let noRainFactor: Double? = isRaining
            ? day.precipitationMM.map { 1 - WeatherCurves.ratio($0, saturatingAt: Rule.rainSaturationMM) }
            : 1

        return WeatherCurves.combine([
            (Rule.coldWeight, WeatherCurves.comfort(day.maxTemperatureC, ideal: Rule.idealMaxTemperature, tolerance: Rule.temperatureTolerance)),
            (Rule.snowWeight, day.snowfallCM.map { WeatherCurves.ratio($0, saturatingAt: Rule.snowfallSaturationCM) }),
            (Rule.noRainWeight, noRainFactor),
            (Rule.windWeight, day.maxWindSpeedKmh.map { WeatherCurves.comfort($0, ideal: Rule.idealWind, tolerance: Rule.windTolerance) }),
        ])
    }
}

// MARK: - Surfing

/// Surfing wants warm air, a steady breeze (wind builds swell; too much blows it out),
/// a dry day and — non-negotiably — no thunderstorms.
///
/// Known limitation: wave height / swell period live in Open-Meteo's separate Marine API,
/// which is out of scope here. Wind speed is used as a proxy. See README → Assumptions.
public struct SurfingScorer: ActivityScoring {
    enum Rule {
        static let idealMaxTemperature: ClosedRange<Double> = 18...30
        static let temperatureTolerance: Double = 10
        /// Enough wind to raise a swell, not so much that the sea is "blown out".
        static let idealWind: ClosedRange<Double> = 12...35
        static let windTolerance: Double = 25

        static let temperatureWeight: Double = 35
        static let windWeight: Double = 35
        static let dryWeight: Double = 30
    }

    public let activity = Activity.surfing
    public init() {}

    public func score(for day: DailyWeather) -> Score {
        // Lightning on open water is a hard no, regardless of everything else.
        guard day.condition != .thunderstorm else { return .min }

        return WeatherCurves.combine([
            (Rule.temperatureWeight, WeatherCurves.comfort(day.maxTemperatureC, ideal: Rule.idealMaxTemperature, tolerance: Rule.temperatureTolerance)),
            (Rule.windWeight, day.maxWindSpeedKmh.map { WeatherCurves.comfort($0, ideal: Rule.idealWind, tolerance: Rule.windTolerance) }),
            (Rule.dryWeight, day.dryness),
        ])
    }
}

// MARK: - Outdoor sightseeing

/// Outdoor sightseeing wants mild temperatures, a low chance of rain, light wind and a clear sky.
public struct OutdoorSightseeingScorer: ActivityScoring {
    enum Rule {
        static let idealMaxTemperature: ClosedRange<Double> = 15...26
        static let temperatureTolerance: Double = 10
        static let idealWind: ClosedRange<Double> = 0...20
        static let windTolerance: Double = 30

        static let temperatureWeight: Double = 40
        static let dryWeight: Double = 30
        static let windWeight: Double = 15
        static let skyWeight: Double = 15
    }

    public let activity = Activity.outdoorSightseeing
    public init() {}

    public func score(for day: DailyWeather) -> Score {
        WeatherCurves.combine([
            (Rule.temperatureWeight, WeatherCurves.comfort(day.maxTemperatureC, ideal: Rule.idealMaxTemperature, tolerance: Rule.temperatureTolerance)),
            (Rule.dryWeight, day.dryness),
            (Rule.windWeight, day.maxWindSpeedKmh.map { WeatherCurves.comfort($0, ideal: Rule.idealWind, tolerance: Rule.windTolerance) }),
            (Rule.skyWeight, day.condition.skyPleasantness),
        ])
    }
}

// MARK: - Indoor sightseeing

/// Indoor sightseeing is the fallback: it is never a *bad* idea, and it becomes the *best*
/// idea precisely when the weather makes everything else unpleasant.
///
/// Score = floor + (1 − floor) × (how unpleasant it is outside). The floor is a deliberate
/// product decision: a museum is always a reasonable plan, so this activity never ranks at zero.
public struct IndoorSightseeingScorer: ActivityScoring {
    enum Rule {
        /// The minimum score, as a 0…1 fraction. 0.5 → never below 50.
        static let floor: Double = 0.5
        /// Wider than the outdoor range: you only *retreat* indoors for genuinely bad weather.
        static let tolerableMaxTemperature: ClosedRange<Double> = 10...28
        static let temperatureTolerance: Double = 12
        static let tolerableWind: ClosedRange<Double> = 0...30
        static let windTolerance: Double = 30
    }

    public let activity = Activity.indoorSightseeing
    public init() {}

    public func score(for day: DailyWeather) -> Score {
        let signals: [Double?] = [
            day.dryness.map { 1 - $0 },
            1 - WeatherCurves.comfort(day.maxTemperatureC, ideal: Rule.tolerableMaxTemperature, tolerance: Rule.temperatureTolerance),
            day.maxWindSpeedKmh.map { 1 - WeatherCurves.comfort($0, ideal: Rule.tolerableWind, tolerance: Rule.windTolerance) },
            1 - day.condition.skyPleasantness,
        ]
        // Use the *worst* signal, not the average: one strong reason to stay in is enough.
        // A missing signal is skipped rather than read as "fine".
        let unpleasantness = signals.compactMap { $0 }.max() ?? 0
        return Score(normalised: Rule.floor + (1 - Rule.floor) * unpleasantness)
    }
}

// MARK: - Shared signals

extension DailyWeather {
    /// 1.0 when rain is impossible, 0.0 when it is certain. `nil` when the probability is missing.
    var dryness: Double? {
        precipitationProbability.map { 1 - Double($0) / 100 }
    }
}

extension WeatherCondition {
    /// How pleasant the sky is to be out under, 0…1. Shared by every scorer that cares
    /// about the sky so the activities agree on what "nice" means.
    var skyPleasantness: Double {
        switch self {
        case .clear: return 1.0
        case .partlyCloudy: return 0.9
        case .overcast: return 0.6
        case .fog: return 0.4
        case .drizzle, .showers: return 0.3
        case .snow: return 0.2
        case .rain: return 0.1
        case .thunderstorm: return 0.0
        case .unknown: return 0.5
        }
    }
}

/// The production rule set, in ranking tie-break order.
public enum ActivityScorers {
    public static let `default`: [any ActivityScoring] = [
        SkiingScorer(),
        SurfingScorer(),
        OutdoorSightseeingScorer(),
        IndoorSightseeingScorer(),
    ]
}
