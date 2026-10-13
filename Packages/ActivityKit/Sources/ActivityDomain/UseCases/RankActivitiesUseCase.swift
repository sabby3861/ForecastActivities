import Foundation

/// Turns a multi-day forecast into a ranked list of activity recommendations.
///
/// This is the single piece of business logic the app exists for, so it is a plain,
/// synchronous, dependency-free struct: easy to test exhaustively and impossible to
/// couple to networking or UI by accident.
public struct RankActivitiesUseCase: Sendable {
    private let scorers: [any ActivityScoring]

    /// - Parameter scorers: the rule set. Defaults to production rules; tests inject their own.
    public init(scorers: [any ActivityScoring] = ActivityScorers.default) {
        self.scorers = scorers
    }

    /// Ranks activities for the given days.
    ///
    /// - Returns: one recommendation per scorer, best overall first. Ordering is total and
    ///   deterministic: by overall score descending, then by the scorer's position in the
    ///   rule set, so equal scores never flicker between refreshes.
    /// - Note: an empty `days` array yields an empty result rather than a list of zeros,
    ///   because "no data" and "terrible conditions" must be distinguishable in the UI.
    public func rank(_ days: [DailyWeather]) -> [ActivityRecommendation] {
        guard !days.isEmpty else { return [] }

        let recommendations = scorers.map { scorer -> ActivityRecommendation in
            let daily = days.map { DailyScore(date: $0.date, score: scorer.score(for: $0)) }
            let mean = Double(daily.reduce(0) { $0 + $1.score.value }) / Double(daily.count)
            return ActivityRecommendation(
                activity: scorer.activity,
                overallScore: Score(value: Int(mean.rounded())),
                dailyScores: daily
            )
        }

        // Two comparators, applied in order: best score first, then original rule-set
        // position to break ties. Declarative, and the intent is visible without reading
        // a comparison closure.
        return recommendations.enumerated()
            .sorted(using: [
                KeyPathComparator(\.element.overallScore, order: .reverse),
                KeyPathComparator(\.offset),
            ])
            .map(\.element)
    }
}
