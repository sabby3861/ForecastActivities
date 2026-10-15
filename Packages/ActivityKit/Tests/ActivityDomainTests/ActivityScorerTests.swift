import ActivityDomain
import XCTest

/// Tests for each rule. They check relative orderings and hard limits (gates that force 0,
/// the indoor floor, the 100 cap) rather than exact scores, so tuning a weight doesn't
/// break them.
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

    func testSkiing_coldPowderDayBeatsMildDayOnTheSameBase() {
        let scorer = SkiingScorer()
        let powder = scorer.score(for: Fixture.day(maxTemp: -4, minTemp: -10, snowfallCM: 12, snowDepthM: 0.8, wind: 10, condition: .snow))
        let mild = scorer.score(for: Fixture.day(maxTemp: 7, minTemp: 1, snowDepthM: 0.8, condition: .clear))
        XCTAssertGreaterThan(powder, mild)
        XCTAssertGreaterThanOrEqual(powder.value, 90)
    }

    func testSkiing_rainPenalisesButSnowDoesNot() {
        let scorer = SkiingScorer()
        let rainy = scorer.score(for: Fixture.day(maxTemp: 3, minTemp: -1, precipitationMM: 10, snowDepthM: 0.5, condition: .rain))
        let snowy = scorer.score(for: Fixture.day(maxTemp: 3, minTemp: -1, precipitationMM: 10, snowDepthM: 0.5, condition: .snow))
        XCTAssertLessThan(rainy, snowy)
    }

    func testSkiing_strongWindLowersScore() {
        let scorer = SkiingScorer()
        let calm = scorer.score(for: Fixture.day(maxTemp: -5, minTemp: -10, snowDepthM: 0.5, wind: 10))
        let gale = scorer.score(for: Fixture.day(maxTemp: -5, minTemp: -10, snowDepthM: 0.5, wind: 70))
        XCTAssertLessThan(gale, calm)
    }

    // MARK: - Surfing

    func testSurfing_likelyThunderstormIsZero() {
        let day = Fixture.day(maxTemp: 25, minTemp: 20, precipitationProbability: 80, wind: 10, condition: .thunderstorm)
        XCTAssertEqual(SurfingScorer().score(for: day), .min)
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

    func testOutdoor_idealDayScoresPerfect() {
        let score = OutdoorSightseeingScorer().score(for: Fixture.day(maxTemp: 21, minTemp: 12, precipitationProbability: 0, wind: 8, condition: .clear))
        XCTAssertEqual(score, .max)
    }

    func testOutdoor_rainProbabilityDragsScoreDown() {
        let scorer = OutdoorSightseeingScorer()
        let dry = scorer.score(for: Fixture.day(precipitationProbability: 0, condition: .clear))
        let wet = scorer.score(for: Fixture.day(precipitationProbability: 90, condition: .rain))
        XCTAssertGreaterThan(dry.value - wet.value, 30)
    }

    func testOutdoor_missingRainChance_isNotTreatedAsDry() {
        let scorer = OutdoorSightseeingScorer()
        let missing = scorer.score(for: Fixture.day(maxTemp: 20, minTemp: 12, precipitationProbability: nil, wind: nil, condition: .overcast))
        let assumedDry = scorer.score(for: Fixture.day(maxTemp: 20, minTemp: 12, precipitationProbability: 0, wind: 0, condition: .overcast))
        XCTAssertLessThan(missing, assumedDry)
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
