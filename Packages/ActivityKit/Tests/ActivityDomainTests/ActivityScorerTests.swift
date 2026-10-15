import ActivityDomain
import XCTest

/// Tests for each rule. They check relative orderings and hard limits (gates that force 0,
/// the indoor floor, the 100 cap) rather than exact scores, so tuning a weight doesn't
/// break them.
final class ActivityScorerTests: XCTestCase {
    // MARK: - Invariants shared by every scorer

    func testAllScorers_alwaysProduceScoresWithinRange() {
        let extremes: [DailyWeather] = [
            Fixture.day(maxTemp: -40, minTemp: -50, snowDepthM: 5, precipitationProbability: 0, wind: 0, condition: .clear),
            Fixture.day(maxTemp: 50, minTemp: 40, precipitationMM: 200, snowfallCM: 100, precipitationProbability: 100, wind: 200, condition: .thunderstorm, sea: .waves(heightM: 12)),
            Fixture.day(maxTemp: 0, minTemp: 0, precipitationMM: nil, snowfallCM: nil, snowDepthM: nil, precipitationProbability: nil, wind: nil, condition: .unknown(code: 999), sea: .noSea),
        ]
        for day in extremes {
            for scorer in ActivityScorers.default {
                let score = scorer.score(for: day)
                XCTAssertTrue((0...100).contains(score.value), "\(scorer.activity) produced \(score.value)")
            }
            for alternative in [Score.min, .max] {
                let score = ActivityScorers.fallback.score(for: day, bestAlternative: alternative)
                XCTAssertTrue((50...100).contains(score.value), "indoor produced \(score.value)")
            }
        }
    }

    func testDefaultScorers_coverEveryActivityExactlyOnce() {
        XCTAssertEqual(ActivityScorers.default.map(\.activity) + [ActivityScorers.fallback.activity], Activity.allCases)
    }

    // MARK: - Skiing

    func testSkiing_withoutSnow_scoresZero() {
        let scorer = SkiingScorer()
        // Cold and clear, but nothing on the ground and nothing falling.
        XCTAssertEqual(scorer.score(for: Fixture.day(maxTemp: -3, minTemp: -9, snowfallCM: 0, snowDepthM: 0)), .min)
        XCTAssertEqual(scorer.score(for: Fixture.day(maxTemp: 24, minTemp: 15)), .min)
        XCTAssertEqual(scorer.score(for: Fixture.day(maxTemp: -3, minTemp: -9, snowfallCM: nil, snowDepthM: nil)), .min, "no snow data is not evidence of snow")
    }

    func testSkiing_freshSnowAloneIsEnough() {
        let score = SkiingScorer().score(for: Fixture.day(maxTemp: -2, minTemp: -8, snowfallCM: 5, snowDepthM: 0, condition: .snow))
        XCTAssertGreaterThan(score, .min)
    }

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
        let day = Fixture.day(maxTemp: 25, minTemp: 20, precipitationProbability: 80, wind: 10, condition: .thunderstorm, sea: .waves(heightM: 1.5))
        XCTAssertEqual(SurfingScorer().score(for: day), .min)
    }

    func testSurfing_unlikelyThunderstormIsNotAnAutomaticZero() {
        // The daily code is the worst hour; with a 20% chance it's a passing storm.
        let day = Fixture.day(maxTemp: 25, minTemp: 20, precipitationProbability: 20, wind: 10, condition: .thunderstorm, sea: .waves(heightM: 1.5))
        XCTAssertGreaterThan(SurfingScorer().score(for: day), .min)
    }

    func testSurfing_inland_isZeroEvenOnAPerfectDay() {
        let day = Fixture.day(maxTemp: 26, minTemp: 18, precipitationProbability: 0, wind: 10, sea: .noSea)
        XCTAssertEqual(SurfingScorer().score(for: day), .min)
    }

    func testSurfing_flatSea_isZero() {
        let day = Fixture.day(maxTemp: 26, minTemp: 18, wind: 10, sea: .waves(heightM: 0.2))
        XCTAssertEqual(SurfingScorer().score(for: day), .min)
    }

    func testSurfing_freezingAir_isZero() {
        let day = Fixture.day(maxTemp: -3, minTemp: -8, wind: 10, sea: .waves(heightM: 1.5))
        XCTAssertEqual(SurfingScorer().score(for: day), .min)
    }

    func testSurfing_goodWavesBeatSmallWaves() {
        let scorer = SurfingScorer()
        let good = scorer.score(for: Fixture.day(maxTemp: 24, minTemp: 18, wind: 10, sea: .waves(heightM: 1.6)))
        let small = scorer.score(for: Fixture.day(maxTemp: 24, minTemp: 18, wind: 10, sea: .waves(heightM: 0.5)))
        XCTAssertGreaterThan(good, small)
    }

    func testSurfing_withWaveData_lightWindBeatsStrongWind() {
        let scorer = SurfingScorer()
        let light = scorer.score(for: Fixture.day(maxTemp: 24, minTemp: 18, wind: 8, sea: .waves(heightM: 1.6)))
        let strong = scorer.score(for: Fixture.day(maxTemp: 24, minTemp: 18, wind: 45, sea: .waves(heightM: 1.6)))
        XCTAssertGreaterThan(light, strong)
    }

    func testSurfing_withoutWaveData_moderateBreezeBeatsCalmAndGale() {
        // Fallback path: wind stands in for swell.
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
            scorer.score(for: Fixture.day(maxTemp: 8, minTemp: 3, wind: 10, sea: .waves(heightM: 1.6))),
            scorer.score(for: Fixture.day(maxTemp: 24, minTemp: 18, wind: 10, sea: .waves(heightM: 1.6)))
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

    private let miserable = Fixture.day(maxTemp: 4, minTemp: 0, precipitationProbability: 100, wind: 60, condition: .rain)

    func testIndoor_neverDropsBelowFifty() {
        let perfectDay = Fixture.day(maxTemp: 21, minTemp: 12, precipitationProbability: 0, wind: 5, condition: .clear)
        XCTAssertEqual(IndoorSightseeingScorer().score(for: perfectDay, bestAlternative: .min).value, 50)
        XCTAssertEqual(IndoorSightseeingScorer().score(for: miserable, bestAlternative: .max).value, 50)
    }

    func testIndoor_miserableWeatherWithNothingElseScoresMaximum() {
        XCTAssertEqual(IndoorSightseeingScorer().score(for: miserable, bestAlternative: .min), .max)
    }

    func testIndoor_usesWorstSignalNotAverage() {
        // Perfect temperature and wind, but certain rain: that alone should push indoors to 100.
        let certainRain = Fixture.day(maxTemp: 21, minTemp: 12, precipitationProbability: 100, wind: 5, condition: .clear)
        XCTAssertEqual(IndoorSightseeingScorer().score(for: certainRain, bestAlternative: .min), .max)
    }

    func testIndoor_coldDayLosesToAGreatAlternative() {
        // A powder day is cold, but that's no reason to go to a museum.
        let powderDay = Fixture.day(maxTemp: -4, minTemp: -10, snowfallCM: 12, snowDepthM: 0.8, wind: 10, condition: .snow)
        let skiing = SkiingScorer().score(for: powderDay)
        XCTAssertLessThan(IndoorSightseeingScorer().score(for: powderDay, bestAlternative: skiing), skiing)
    }

    func testIndoor_unlikelyStormDoesNotMaxOut() {
        let scorer = IndoorSightseeingScorer()
        let passing = scorer.score(for: Fixture.day(maxTemp: 22, minTemp: 15, precipitationProbability: 20, wind: 10, condition: .thunderstorm), bestAlternative: .min)
        let likely = scorer.score(for: Fixture.day(maxTemp: 22, minTemp: 15, precipitationProbability: 80, wind: 10, condition: .thunderstorm), bestAlternative: .min)
        XCTAssertLessThan(passing, .max)
        XCTAssertEqual(likely, .max)
    }

    // MARK: - Cross-activity sanity

    func testRainyColdDay_prefersIndoorOverOutdoor() {
        let day = Fixture.day(maxTemp: 6, minTemp: 2, precipitationMM: 12, precipitationProbability: 95, wind: 30, condition: .rain)
        let outdoor = OutdoorSightseeingScorer().score(for: day)
        XCTAssertGreaterThan(IndoorSightseeingScorer().score(for: day, bestAlternative: outdoor), outdoor)
    }

    func testWarmClearDay_prefersOutdoorOverIndoor() {
        let day = Fixture.day(maxTemp: 22, minTemp: 14, precipitationProbability: 5, wind: 10, condition: .clear)
        let outdoor = OutdoorSightseeingScorer().score(for: day)
        XCTAssertGreaterThan(outdoor, IndoorSightseeingScorer().score(for: day, bestAlternative: outdoor))
    }
}
