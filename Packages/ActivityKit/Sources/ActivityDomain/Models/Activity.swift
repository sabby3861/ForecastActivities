import Foundation

/// The activities the product ranks. Declaration order is the tie-break when scores match.
public enum Activity: String, CaseIterable, Identifiable, Hashable, Sendable {
    case skiing
    case surfing
    case outdoorSightseeing
    case indoorSightseeing

    public var id: String { rawValue }

    // Display names live in ActivityPresentation.
}

/// A suitability score, clamped to 0…100. Its own type so it can't be mixed up with a
/// temperature or a percentage.
public struct Score: Hashable, Comparable, Sendable {
    public static let min = Score(value: 0)
    public static let max = Score(value: 100)

    public let value: Int

    /// Clamps to 0…100.
    public init(value: Int) {
        self.value = Swift.min(Swift.max(value, 0), 100)
    }

    /// Builds a score from a 0…1 normalised factor (rounded to the nearest point).
    public init(normalised: Double) {
        self.init(value: Int((normalised * 100).rounded()))
    }

    public static func < (lhs: Score, rhs: Score) -> Bool { lhs.value < rhs.value }
}

/// The score an activity gets on one particular day.
public struct DailyScore: Identifiable, Hashable, Sendable {
    public let date: Date
    public let score: Score

    public var id: Date { date }

    public init(date: Date, score: Score) {
        self.date = date
        self.score = score
    }
}

/// The ranking output for one activity across the forecast window.
public struct ActivityRecommendation: Identifiable, Hashable, Sendable {
    public let activity: Activity
    /// Mean of the daily scores.
    public let overallScore: Score
    /// One entry per forecast day, in date order.
    public let dailyScores: [DailyScore]

    public var id: Activity { activity }

    /// The best day; ties go to the earlier one.
    public var bestDay: DailyScore? {
        dailyScores.max { lhs, rhs in
            lhs.score < rhs.score || (lhs.score == rhs.score && lhs.date > rhs.date)
        }
    }

    public init(activity: Activity, overallScore: Score, dailyScores: [DailyScore]) {
        self.activity = activity
        self.overallScore = overallScore
        self.dailyScores = dailyScores
    }
}
