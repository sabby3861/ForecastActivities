import ActivityDomain
import XCTest

final class WeatherCurvesTests: XCTestCase {
    // MARK: comfort

    func testComfort_insideIdealRange_isOne() {
        XCTAssertEqual(WeatherCurves.comfort(20, ideal: 15...25, tolerance: 10), 1)
        XCTAssertEqual(WeatherCurves.comfort(15, ideal: 15...25, tolerance: 10), 1, "lower bound is inclusive")
        XCTAssertEqual(WeatherCurves.comfort(25, ideal: 15...25, tolerance: 10), 1, "upper bound is inclusive")
    }

    func testComfort_decaysLinearlyOutsideRange() {
        XCTAssertEqual(WeatherCurves.comfort(28, ideal: 15...25, tolerance: 10), 0.7, accuracy: 0.0001)
        XCTAssertEqual(WeatherCurves.comfort(10, ideal: 15...25, tolerance: 10), 0.5, accuracy: 0.0001)
    }

    func testComfort_clampsToZeroBeyondTolerance() {
        XCTAssertEqual(WeatherCurves.comfort(40, ideal: 15...25, tolerance: 10), 0)
        XCTAssertEqual(WeatherCurves.comfort(-50, ideal: 15...25, tolerance: 10), 0)
    }

    // MARK: ratio

    func testRatio_scalesAndSaturates() {
        XCTAssertEqual(WeatherCurves.ratio(5, saturatingAt: 10), 0.5)
        XCTAssertEqual(WeatherCurves.ratio(25, saturatingAt: 10), 1)
        XCTAssertEqual(WeatherCurves.ratio(-3, saturatingAt: 10), 0, "negative input never yields a negative factor")
    }

    // MARK: combine

    func testCombine_normalisesWeights() {
        let score = WeatherCurves.combine([(weight: 3, value: 1), (weight: 1, value: 0)])
        XCTAssertEqual(score.value, 75)
    }

    func testCombine_clampsFactorsIntoUnitInterval() {
        let score = WeatherCurves.combine([(weight: 1, value: 7), (weight: 1, value: -2)])
        XCTAssertEqual(score.value, 50)
    }

    func testCombine_withNoWeight_isZero() {
        XCTAssertEqual(WeatherCurves.combine([]), .min)
    }

    func testCombine_dropsMissingFactorsAndRescales() {
        let score = WeatherCurves.combine([(weight: 1, value: 1), (weight: 3, value: nil)])
        XCTAssertEqual(score.value, 100, "the missing factor neither adds nor subtracts")
    }

    func testCombine_withEveryFactorMissing_isZero() {
        XCTAssertEqual(WeatherCurves.combine([(weight: 1, value: nil), (weight: 2, value: nil)]), .min)
    }

    // MARK: Score

    func testScore_clampsToRange() {
        XCTAssertEqual(Score(value: -10).value, 0)
        XCTAssertEqual(Score(value: 140).value, 100)
        XCTAssertEqual(Score(normalised: 0.456).value, 46)
    }
}
