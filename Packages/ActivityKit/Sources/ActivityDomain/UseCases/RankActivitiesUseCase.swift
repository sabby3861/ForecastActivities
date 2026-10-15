import Foundation

/// Turns a multi-day forecast into a ranked list of activity recommendations.
public struct RankActivitiesUseCase: Sendable {
    private let scorers: [any ActivityScoring]
    private let fallback: IndoorSightseeingScorer?

    /// - Parameters:
    ///   - scorers: the regular rule set. Defaults to production rules; tests inject their own.
    ///   - fallback: scored per day after the others, against the best of them. `nil` to leave it out.
    public init(
        scorers: [any ActivityScoring] = ActivityScorers.default,
        fallback: IndoorSightseeingScorer? = ActivityScorers.fallback
    ) {
        self.scorers = scorers
        self.fallback = fallback
    }

    /// Ranks activities for the given days.
    ///
    /// - Returns: one recommendation per activity, best overall first. Ties go to the
    ///   earlier activity in the rule set (the fallback comes last), so equal scores don't
    ///   swap places between refreshes.
    /// - Note: no days gives an empty result rather than a list of zeros, so "no data" and
    ///   "terrible week" stay distinguishable.
    public func rank(_ days: [DailyWeather]) -> [ActivityRecommendation] {
        guard !days.isEmpty else { return [] }

        let activities = scorers.map(\.activity) + (fallback.map { [$0.activity] } ?? [])

        // One row per day, one column per activity, in `activities` order.
        let scoresByDay: [[Score]] = days.map { day in
            let scores = scorers.map { $0.score(for: day) }
            guard let fallback else { return scores }
            return scores + [fallback.score(for: day, bestAlternative: scores.max() ?? .min)]
        }

        let recommendations = activities.enumerated().map { column, activity in
            let daily = zip(days, scoresByDay).map { day, scores in
                DailyScore(date: day.date, score: scores[column])
            }
            let mean = Double(daily.reduce(0) { $0 + $1.score.value }) / Double(daily.count)
            return ActivityRecommendation(
                activity: activity,
                overallScore: Score(value: Int(mean.rounded())),
                dailyScores: daily
            )
        }

        return recommendations.enumerated()
            .sorted(using: [
                KeyPathComparator(\.element.overallScore, order: .reverse),
                KeyPathComparator(\.offset),
            ])
            .map(\.element)
    }
}
