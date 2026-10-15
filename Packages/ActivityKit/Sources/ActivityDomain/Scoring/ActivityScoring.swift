import Foundation

/// One rule object per activity: a pure function from one day's weather to a score.
///
/// Each scorer checks its hard requirements first (no snow, no skiing). If one fails, the
/// score is 0 and the weights never run. Otherwise the score is a weighted blend of 0…1
/// factors, and a factor whose input is missing is left out of the blend.
public protocol ActivityScoring: Sendable {
    var activity: Activity { get }
    func score(for day: DailyWeather) -> Score
}

// MARK: - Skiing

/// Skiing needs snow, either on the ground or falling. Given that, it wants cold air, a
/// decent base, fresh snow, no rain and manageable wind.
///
/// Snow depth is taken at the city's grid point, so a valley town below a ski area scores
/// 0 when there's no snow in town. See README, Assumptions.
public struct SkiingScorer: ActivityScoring {
    enum Rule {
        static let minSnowDepthM: Double = 0.05
        static let minSnowfallCM: Double = 1
        /// Daytime highs that keep snow firm. Above ~2 °C it turns to slush.
        static let idealMaxTemperature: ClosedRange<Double> = -15...2
        static let temperatureTolerance: Double = 6
        /// Half a metre of base covers most pistes.
        static let baseSaturationM: Double = 0.5
        /// 10 cm of fresh snow is a powder day.
        static let snowfallSaturationCM: Double = 10
        /// 10 mm of rain writes a ski day off.
        static let rainSaturationMM: Double = 10
        /// Above this, precipitation falls as rain rather than snow.
        static let rainThresholdC: Double = 1
        static let idealWind: ClosedRange<Double> = 0...25
        static let windTolerance: Double = 40

        static let coldWeight: Double = 30
        static let baseWeight: Double = 25
        static let freshSnowWeight: Double = 20
        static let noRainWeight: Double = 10
        static let windWeight: Double = 15
    }

    public let activity = Activity.skiing
    public init() {}

    public func score(for day: DailyWeather) -> Score {
        let hasSnow = (day.snowDepthM ?? 0) >= Rule.minSnowDepthM
            || (day.snowfallCM ?? 0) >= Rule.minSnowfallCM
        guard hasSnow else { return .min }

        let condition = day.effectiveCondition
        let isRaining = condition.isWet && condition != .snow && day.maxTemperatureC > Rule.rainThresholdC
        let noRain: Double? = isRaining
            ? day.precipitationMM.map { 1 - WeatherCurves.ratio($0, saturatingAt: Rule.rainSaturationMM) }
            : 1

        return WeatherCurves.combine([
            (Rule.coldWeight, WeatherCurves.comfort(day.maxTemperatureC, ideal: Rule.idealMaxTemperature, tolerance: Rule.temperatureTolerance)),
            (Rule.baseWeight, day.snowDepthM.map { WeatherCurves.ratio($0, saturatingAt: Rule.baseSaturationM) }),
            (Rule.freshSnowWeight, day.snowfallCM.map { WeatherCurves.ratio($0, saturatingAt: Rule.snowfallSaturationCM) }),
            (Rule.noRainWeight, noRain),
            (Rule.windWeight, day.maxWindSpeedKmh.map { WeatherCurves.comfort($0, ideal: Rule.idealWind, tolerance: Rule.windTolerance) }),
        ])
    }
}

// MARK: - Surfing

/// Surfing needs air that isn't freezing and no likely thunderstorm. Given that, it wants
/// warm air, a steady breeze (wind builds swell; too much blows it out) and a dry day.
///
/// Known limitation: wave height / swell period live in Open-Meteo's separate Marine API,
/// which is out of scope here. Wind speed is used as a proxy. See README → Assumptions.
public struct SurfingScorer: ActivityScoring {
    enum Rule {
        static let minMaxTemperatureC: Double = 5
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
        // Lightning on open water is a hard no.
        guard !day.isStormLikely, day.maxTemperatureC >= Rule.minMaxTemperatureC else { return .min }

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
            (Rule.skyWeight, day.effectiveCondition.skyPleasantness),
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
            1 - day.effectiveCondition.skyPleasantness,
        ]
        // Use the *worst* signal, not the average: one strong reason to stay in is enough.
        // A missing signal is skipped rather than read as "fine".
        let unpleasantness = signals.compactMap { $0 }.max() ?? 0
        return Score(normalised: Rule.floor + (1 - Rule.floor) * unpleasantness)
    }
}

// MARK: - Shared signals

extension DailyWeather {
    /// Below this chance of rain, a thunderstorm code is treated as a passing storm.
    static let likelyStormProbability = 50

    /// 1.0 when rain is impossible, 0.0 when it's certain. `nil` when the probability is missing.
    var dryness: Double? {
        precipitationProbability.map { 1 - Double($0) / 100 }
    }

    /// Open-Meteo's daily weather code is the worst hour of the day, so one storm in the
    /// evening marks the whole day as a thunderstorm. Only trust it when rain is likely
    /// (or we don't know the probability).
    var isStormLikely: Bool {
        condition == .thunderstorm && (precipitationProbability ?? 100) >= Self.likelyStormProbability
    }

    /// The condition the rules should react to: an unlikely storm counts as showers.
    var effectiveCondition: WeatherCondition {
        condition == .thunderstorm && !isStormLikely ? .showers : condition
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
