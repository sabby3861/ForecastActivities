import ActivityDomain
import XCTest

final class RankActivitiesUseCaseTests: XCTestCase {
    /// A scorer that returns a fixed score, so ordering tests are independent of the real rules.
    private struct FixedScorer: ActivityScoring {
        let activity: Activity
        let value: Int
        func score(for day: DailyWeather) -> Score { Score(value: value) }
    }

    /// A scorer whose score depends on the day, to test per-day output and averaging.
    private struct DayIndexedScorer: ActivityScoring {
        let activity: Activity
        let values: [Int]
        func score(for day: DailyWeather) -> Score {
            let index = Int(day.date.timeIntervalSince(Fixture.date(offset: 0)) / 86_400)
            return Score(value: values[index])
        }
    }

    func testEmptyForecast_producesNoRecommendations() {
        XCTAssertTrue(RankActivitiesUseCase().rank([]).isEmpty)
    }

    func testSortsByOverallScoreDescending() {
        let useCase = RankActivitiesUseCase(scorers: [
            FixedScorer(activity: .skiing, value: 10),
            FixedScorer(activity: .surfing, value: 90),
            FixedScorer(activity: .outdoorSightseeing, value: 50),
        ])

        let ranked = useCase.rank([Fixture.day()])

        XCTAssertEqual(ranked.map(\.activity), [.surfing, .outdoorSightseeing, .skiing])
        XCTAssertEqual(ranked.map(\.overallScore.value), [90, 50, 10])
    }

    func testTies_resolveByScorerOrder_soRankingIsStable() {
        let useCase = RankActivitiesUseCase(scorers: [
            FixedScorer(activity: .indoorSightseeing, value: 60),
            FixedScorer(activity: .skiing, value: 60),
            FixedScorer(activity: .surfing, value: 60),
        ])

        let first = useCase.rank([Fixture.day()])
        let second = useCase.rank([Fixture.day()])

        XCTAssertEqual(first.map(\.activity), [.indoorSightseeing, .skiing, .surfing])
        XCTAssertEqual(first, second)
    }

    func testOverallScore_isMeanOfDailyScores_andDailyScoresKeepDateOrder() {
        let days = (0..<3).map { Fixture.day(offset: $0) }
        let useCase = RankActivitiesUseCase(scorers: [
            DayIndexedScorer(activity: .skiing, values: [20, 40, 90]),
        ])

        let ranked = useCase.rank(days)

        XCTAssertEqual(ranked.count, 1)
        XCTAssertEqual(ranked[0].overallScore.value, 50)
        XCTAssertEqual(ranked[0].dailyScores.map(\.score.value), [20, 40, 90])
        XCTAssertEqual(ranked[0].dailyScores.map(\.date), days.map(\.date))
    }

    func testBestDay_isHighestScore_tieGoesToEarliestDay() {
        let days = (0..<3).map { Fixture.day(offset: $0) }
        let useCase = RankActivitiesUseCase(scorers: [
            DayIndexedScorer(activity: .surfing, values: [70, 90, 90]),
        ])

        let best = useCase.rank(days)[0].bestDay

        XCTAssertEqual(best?.score.value, 90)
        XCTAssertEqual(best?.date, Fixture.date(offset: 1))
    }

    func testProductionRules_rankRainyColdWeekIndoorFirst() {
        let week = (0..<7).map {
            Fixture.day(offset: $0, maxTemp: 5, minTemp: 1, precipitationMM: 8, precipitationProbability: 90, wind: 35, condition: .rain)
        }

        let ranked = RankActivitiesUseCase().rank(week)

        XCTAssertEqual(ranked.first?.activity, .indoorSightseeing)
        XCTAssertEqual(ranked.count, Activity.allCases.count)
    }

    func testProductionRules_rankWarmClearWeekOutdoorFirst() {
        let week = (0..<7).map {
            Fixture.day(offset: $0, maxTemp: 23, minTemp: 15, precipitationProbability: 5, wind: 10, condition: .clear)
        }

        let ranked = RankActivitiesUseCase().rank(week)

        XCTAssertEqual(ranked.first?.activity, .outdoorSightseeing)
    }
}
