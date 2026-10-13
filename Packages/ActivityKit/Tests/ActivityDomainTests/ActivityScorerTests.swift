import ActivityDomain
import XCTest

/// Behavioural tests for each rule. They assert *relative* orderings and hard limits rather
/// than exact numbers, so reasonable weight tuning does not break the suite.
final class ActivityScorerTests: XCTestCase {
    // MARK: - Invariants shared by every scorer

    func testAllScorers_alwaysProduceScoresWithinRange() {
        let extremes: [DailyWeather] = [
            Fixture.day(maxTemp: -40, minTemp: -50, precipitationMM: 0, snowfallCM: 0, precipitationProbability: 0, wind: 0, condition: .clear),
            Fixture.day(maxTemp: 50, minTemp: 40, precipitationMM: 200, snowfallCM: 100, precipitationProbability: 100, wind: 200, condition: .thunderstorm),
            Fixture.day(maxTemp: 0, minTemp: 0, precipitationMM: 0, snowfallCM: 0, precipitationProbability: 0, wind: 0, condition: .unknown(code: 999)),
        ]
        for scorer in ActivityScorers.default {
            for day in extremes {
                let score = scorer.score(for: day)
                XCTAssertTrue((0...100).contains(score.value), "\(scorer.activity) produced \(score.value)")
            }
        }
    }

    func testDefaultScorers_coverEveryActivityExactlyOnce() {
        XCTAssertEqual(ActivityScorers.default.map(\.activity), Activity.allCases)
    }

    // MARK: - Skiing

    func testSkiing_coldSnowyDayBeatsWarmDryDay() {
        let scorer = SkiingScorer()
        let powder = scorer.score(for: Fixture.day(maxTemp: -4, minTemp: -10, snowfallCM: 12, wind: 10, condition: .snow))
        let warm = scorer.score(for: Fixture.day(maxTemp: 24, minTemp: 15, condition: .clear))
        XCTAssertGreaterThan(powder, warm)
        XCTAssertGreaterThanOrEqual(powder.value, 90)
        XCTAssertEqual(warm.value, 30, "only the no-rain and calm-wind factors (15 + 15) survive on a warm, dry day")
    }

    func testSkiing_rainPenalisesButSnowDoesNot() {
        let scorer = SkiingScorer()
        let rainy = scorer.score(for: Fixture.day(maxTemp: 3, minTemp: -1, precipitationMM: 10, condition: .rain))
        let snowy = scorer.score(for: Fixture.day(maxTemp: 3, minTemp: -1, precipitationMM: 10, snowfallCM: 0, condition: .snow))
        XCTAssertLessThan(rainy, snowy)
    }

    func testSkiing_strongWindLowersScore() {
        let scorer = SkiingScorer()
        let calm = scorer.score(for: Fixture.day(maxTemp: -5, minTemp: -10, wind: 10))
        let gale = scorer.score(for: Fixture.day(maxTemp: -5, minTemp: -10, wind: 70))
        XCTAssertLessThan(gale, calm)
    }

    // MARK: - Surfing

    func testSurfing_thunderstormIsAlwaysZero() {
        let score = SurfingScorer().score(for: Fixture.day(maxTemp: 25, minTemp: 20, precipitationProbability: 0, wind: 20, condition: .thunderstorm))
        XCTAssertEqual(score, .min)
    }

    func testSurfing_moderateBreezeBeatsCalmAndGale() {
        let scorer = SurfingScorer()
        let breeze = scorer.score(for: Fixture.day(maxTemp: 24, minTemp: 18, wind: 22))
        let calm = scorer.score(for: Fixture.day(maxTemp: 24, minTemp: 18, wind: 0))
        let gale = scorer.score(for: Fixture.day(maxTemp: 24, minTemp: 18, wind: 70))
        XCTAssertGreaterThan(breeze, calm)
        XCTAssertGreaterThan(breeze, gale)
    }

    func testSurfing_coldDayScoresLowerThanWarmDay() {
        let scorer = SurfingScorer()
        XCTAssertLessThan(
            scorer.score(for: Fixture.day(maxTemp: 6, minTemp: 1, wind: 22)),
            scorer.score(for: Fixture.day(maxTemp: 24, minTemp: 18, wind: 22))
        )
    }

    // MARK: - Outdoor sightseeing

    func testOutdoor_idealDayScoresNearPerfect() {
        let score = OutdoorSightseeingScorer().score(for: Fixture.day(maxTemp: 21, minTemp: 12, precipitationProbability: 0, wind: 8, condition: .clear))
        XCTAssertEqual(score, .max)
    }

    func testOutdoor_rainProbabilityDragsScoreDown() {
        let scorer = OutdoorSightseeingScorer()
        let dry = scorer.score(for: Fixture.day(precipitationProbability: 0, condition: .clear))
        let wet = scorer.score(for: Fixture.day(precipitationProbability: 90, condition: .rain))
        XCTAssertGreaterThan(dry.value - wet.value, 30)
    }

    func testOutdoor_extremeHeatIsPenalised() {
        let scorer = OutdoorSightseeingScorer()
        XCTAssertLessThan(
            scorer.score(for: Fixture.day(maxTemp: 38, minTemp: 28)),
            scorer.score(for: Fixture.day(maxTemp: 22, minTemp: 14))
        )
    }

    // MARK: - Indoor sightseeing

    func testIndoor_neverDropsBelowFifty() {
        let perfectDay = Fixture.day(maxTemp: 21, minTemp: 12, precipitationProbability: 0, wind: 5, condition: .clear)
        XCTAssertEqual(IndoorSightseeingScorer().score(for: perfectDay).value, 50)
    }

    func testIndoor_miserableWeatherScoresMaximum() {
        let miserable = Fixture.day(maxTemp: 4, minTemp: 0, precipitationProbability: 100, wind: 60, condition: .rain)
        XCTAssertEqual(IndoorSightseeingScorer().score(for: miserable), .max)
    }

    func testIndoor_usesWorstSignalNotAverage() {
        // Perfect temperature and wind, but certain rain: that alone should push indoors to 100.
        let certainRain = Fixture.day(maxTemp: 21, minTemp: 12, precipitationProbability: 100, wind: 5, condition: .clear)
        XCTAssertEqual(IndoorSightseeingScorer().score(for: certainRain), .max)
    }

    // MARK: - Cross-activity sanity

    func testRainyColdDay_prefersIndoorOverOutdoor() {
        let day = Fixture.day(maxTemp: 6, minTemp: 2, precipitationMM: 12, precipitationProbability: 95, wind: 30, condition: .rain)
        XCTAssertGreaterThan(IndoorSightseeingScorer().score(for: day), OutdoorSightseeingScorer().score(for: day))
    }

    func testWarmClearDay_prefersOutdoorOverIndoor() {
        let day = Fixture.day(maxTemp: 22, minTemp: 14, precipitationProbability: 5, wind: 10, condition: .clear)
        XCTAssertGreaterThan(OutdoorSightseeingScorer().score(for: day), IndoorSightseeingScorer().score(for: day))
    }
}
