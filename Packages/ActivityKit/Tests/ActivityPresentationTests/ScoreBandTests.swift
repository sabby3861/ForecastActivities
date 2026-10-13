import ActivityDomain
import ActivityPresentation
import XCTest

final class ScoreBandTests: XCTestCase {
    func testBands_coverEveryScoreWithoutGaps() {
        XCTAssertEqual(Score(value: 100).band, .excellent)
        XCTAssertEqual(Score(value: 85).band, .excellent, "85 is the first excellent score")
        XCTAssertEqual(Score(value: 84).band, .good)
        XCTAssertEqual(Score(value: 70).band, .good)
        XCTAssertEqual(Score(value: 69).band, .fair)
        XCTAssertEqual(Score(value: 40).band, .fair)
        XCTAssertEqual(Score(value: 39).band, .poor)
        XCTAssertEqual(Score(value: 0).band, .poor)
    }

    func testEveryActivity_hasADisplayName() {
        for activity in Activity.allCases {
            XCTAssertFalse(activity.displayName.isEmpty, "\(activity) has no display name")
        }
    }
}
