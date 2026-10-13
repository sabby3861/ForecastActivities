import ActivityDomain
import ActivityPresentation
import XCTest

@MainActor
final class CitySearchViewModelTests: XCTestCase {
    func testInitialState_isIdle() {
        let sut = CitySearchViewModel(repository: StubCitySearchRepository.returning([]), debounce: .zero)
        XCTAssertEqual(sut.state, .idle)
        XCTAssertEqual(sut.query, "")
    }

    func testTypingAQuery_loadsResults() async {
        let sut = CitySearchViewModel(repository: StubCitySearchRepository.returning([Fixture.london]), debounce: .zero)

        sut.query = "Lon"

        XCTAssertEqual(sut.state, .loading, "state flips to loading synchronously so the UI reacts immediately")
        await waitUntil("results loaded") { sut.state.value != nil }
        XCTAssertEqual(sut.state, .loaded([Fixture.london]))
    }

    func testQueryShorterThanTwoCharacters_staysIdle_andDoesNotSearch() async {
        let counter = CallCounter()
        let repository = StubCitySearchRepository { _ in
            await counter.increment()
            return [Fixture.london]
        }
        let sut = CitySearchViewModel(repository: repository, debounce: .zero)

        sut.query = "L"
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(sut.state, .idle)
        let calls = await counter.count
        XCTAssertEqual(calls, 0)
    }

    func testClearingTheQuery_returnsToIdle() async {
        let sut = CitySearchViewModel(repository: StubCitySearchRepository.returning([Fixture.london]), debounce: .zero)

        sut.query = "London"
        await waitUntil("results loaded") { sut.state.value != nil }

        sut.query = ""

        XCTAssertEqual(sut.state, .idle)
    }

    func testRepositoryFailure_isSurfacedAsFailedState() async {
        let sut = CitySearchViewModel(repository: StubCitySearchRepository.failing(.offline), debounce: .zero)

        sut.query = "London"

        await waitUntil("failure surfaced") { sut.state.error != nil }
        XCTAssertEqual(sut.state, .failed(.offline))
    }

    func testRetry_afterFailure_searchesAgain() async {
        let counter = CallCounter()
        let repository = StubCitySearchRepository { _ in
            await counter.increment()
            if await counter.count == 1 { throw AppError.server(statusCode: 500) }
            return [Fixture.london]
        }
        let sut = CitySearchViewModel(repository: repository, debounce: .zero)

        sut.query = "London"
        await waitUntil("first attempt failed") { sut.state.error != nil }

        sut.retry()

        await waitUntil("retry loaded") { sut.state.value != nil }
        XCTAssertEqual(sut.state, .loaded([Fixture.london]))
    }

    func testLatestQueryWins_whenAnEarlierRequestIsSlower() async {
        // "Lon" takes 200 ms to answer; "London" answers immediately. Whatever the timing,
        // the UI must end up showing London's results.
        let repository = StubCitySearchRepository { query in
            if query == "Lon" {
                try await Task.sleep(for: .milliseconds(200))
                return [Fixture.paris] // deliberately wrong so a leak would be visible
            }
            return [Fixture.london]
        }
        let sut = CitySearchViewModel(repository: repository, debounce: .zero)

        sut.query = "Lon"
        try? await Task.sleep(for: .milliseconds(20))
        sut.query = "London"

        await waitUntil("latest results loaded") { sut.state.value != nil }
        XCTAssertEqual(sut.state, .loaded([Fixture.london]))

        // Give the slow request time to (fail to) overwrite the state.
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(sut.state, .loaded([Fixture.london]))
    }

    func testDebounce_coalescesRapidKeystrokesIntoOneRequest() async {
        let counter = CallCounter()
        let repository = StubCitySearchRepository { _ in
            await counter.increment()
            return [Fixture.london]
        }
        let sut = CitySearchViewModel(repository: repository, debounce: .milliseconds(100))

        sut.query = "Lo"
        sut.query = "Lon"
        sut.query = "Lond"
        sut.query = "Londo"
        sut.query = "London"

        await waitUntil("debounced search completed", timeout: .seconds(3)) { sut.state.value != nil }
        let calls = await counter.count
        XCTAssertEqual(calls, 1)
    }

    func testEmptyResults_areLoadedNotFailed() async {
        let sut = CitySearchViewModel(repository: StubCitySearchRepository.returning([]), debounce: .zero)

        sut.query = "Zzzz"

        await waitUntil("search settled") { !sut.state.isLoading }
        XCTAssertEqual(sut.state, .loaded([]))
    }
}
