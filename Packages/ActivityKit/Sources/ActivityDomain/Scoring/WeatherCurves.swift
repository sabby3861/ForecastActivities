import Foundation

/// Small, pure helpers that turn a raw weather measurement into a 0…1 "how good is this" factor.
///
/// Every scoring rule is built from these two shapes so the behaviour is predictable and
/// each rule can be expressed as "ideal range + weights" rather than nested `if`s.
public enum WeatherCurves {
    /// A trapezoid: 1.0 anywhere inside `ideal`, then falling linearly to 0.0 once the value
    /// is `tolerance` units beyond either edge of the range.
    ///
    /// ```
    /// 1 ┤      ┌───────┐
    ///   │     /         \
    /// 0 ┼────┘           └────
    ///        ^  ideal   ^
    ///    -tolerance   +tolerance
    /// ```
    ///
    /// Example: `comfort(28, ideal: 15...25, tolerance: 10)` = 0.7 (3 degrees over, out of 10).
    public static func comfort(_ value: Double, ideal: ClosedRange<Double>, tolerance: Double) -> Double {
        precondition(tolerance > 0, "tolerance must be positive")
        if ideal.contains(value) { return 1 }
        let distance = value < ideal.lowerBound
            ? ideal.lowerBound - value
            : value - ideal.upperBound
        return max(0, 1 - distance / tolerance)
    }

    /// A ramp: `value / cap`, clamped to 0…1. Used for "more is better, up to a point"
    /// signals such as fresh snowfall.
    public static func ratio(_ value: Double, saturatingAt cap: Double) -> Double {
        precondition(cap > 0, "cap must be positive")
        return min(max(value / cap, 0), 1)
    }

    /// Combines weighted 0…1 factors into a `Score`. Weights are normalised, so callers
    /// can use any convenient scale (e.g. 45/25/15/15) and still get a 0…100 result.
    public static func combine(_ factors: [(weight: Double, value: Double)]) -> Score {
        let totalWeight = factors.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return .min }
        let weighted = factors.reduce(0) { $0 + $1.weight * min(max($1.value, 0), 1) }
        return Score(normalised: weighted / totalWeight)
    }
}
