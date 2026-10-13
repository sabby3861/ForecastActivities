import ActivityDomain
import ActivityPresentation
import XCTest

@MainActor
final class ActivityRankingViewModelTests: XCTestCase {
    func testLoad_success_producesRankedRecommendationsForEveryActivity() async {
        let sut = ActivityRankingViewModel(city: Fixture.london, repository: StubForecastRepository.returning(Fixture.forecast))

        await sut.load()

        let ranking = sut.state.value
        XCTAssertNotNil(ranking)
        XCTAssertEqual(ranking?.forecast, Fixture.forecast)
        XCTAssertEqual(ranking?.recommendations.count, Activity.allCases.count)
        XCTAssertEqual(ranking?.recommendations.first?.activity, .outdoorSightseeing, "a mild, clear week should favour outdoor sightseeing")

        let scores = ranking?.recommendations.map(\.overallScore) ?? []
        XCTAssertEqual(scores, scores.sorted(by: >), "recommendations arrive sorted best-first")
    }

    func testLoad_failure_producesFailedState() async {
        let sut = ActivityRankingViewModel(city: Fixture.london, repository: StubForecastRepository.failing(.offline))

        await sut.load()

        XCTAssertEqual(sut.state, .failed(.offline))
    }

    func testLoad_isIdempotentOnceLoaded() async {
        let counter = CallCounter()
        let repository = StubForecastRepository { _ in
            await counter.increment()
            return Fixture.forecast
        }
        let sut = ActivityRankingViewModel(city: Fixture.london, repository: repository)

        await sut.load()
        await sut.load() // e.g. `.task` firing again after navigating back

        let calls = await counter.count
        XCTAssertEqual(calls, 1)
    }

    func testRetry_afterFailure_reloads() async {
        let counter = CallCounter()
        let repository = StubForecastRepository { _ in
            await counter.increment()
            if await counter.count == 1 { throw AppError.server(statusCode: 502) }
            return Fixture.forecast
        }
        let sut = ActivityRankingViewModel(city: Fixture.london, repository: repository)

        await sut.load()
        XCTAssertEqual(sut.state, .failed(.server(statusCode: 502)))

        await sut.retry()
        XCTAssertNotNil(sut.state.value)
    }

    func testRefresh_failure_keepsExistingContent_andExposesRefreshError() async {
        let counter = CallCounter()
        let repository = StubForecastRepository { _ in
            await counter.increment()
            if await counter.count > 1 { throw AppError.offline }
            return Fixture.forecast
        }
        let sut = ActivityRankingViewModel(city: Fixture.london, repository: repository)

        await sut.load()
        let loaded = sut.state
        XCTAssertNotNil(loaded.value)

        await sut.refresh()

        XCTAssertEqual(sut.state, loaded, "stale-but-useful content survives a failed refresh")
        XCTAssertEqual(sut.refreshError, .offline)
    }

    func testRefresh_success_clearsPreviousRefreshError() async {
        let counter = CallCounter()
        let repository = StubForecastRepository { _ in
            await counter.increment()
            if await counter.count == 2 { throw AppError.offline }
            return Fixture.forecast
        }
        let sut = ActivityRankingViewModel(city: Fixture.london, repository: repository)

        await sut.load()
        await sut.refresh() // fails
        XCTAssertEqual(sut.refreshError, .offline)

        await sut.refresh() // succeeds
        XCTAssertNil(sut.refreshError)
        XCTAssertNotNil(sut.state.value)
    }

    func testCancelledError_doesNotChangeState() async {
        let sut = ActivityRankingViewModel(city: Fixture.london, repository: StubForecastRepository.failing(.cancelled))

        await sut.load()

        XCTAssertEqual(sut.state, .loading, "a cancelled request is not a failure the user should see")
    }
}
