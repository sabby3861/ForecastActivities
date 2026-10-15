import ActivityDomain
import ActivityPresentation
import Foundation
import XCTest

// MARK: - Repository doubles

/// Closure-driven doubles: each test describes behaviour inline instead of maintaining a
/// zoo of fake subclasses.
struct StubCitySearchRepository: CitySearchRepository {
    let handler: @Sendable (String) async throws -> [City]

    init(_ handler: @escaping @Sendable (String) async throws -> [City]) {
        self.handler = handler
    }

    static func returning(_ cities: [City]) -> StubCitySearchRepository {
        StubCitySearchRepository { _ in cities }
    }

    static func failing(_ error: AppError) -> StubCitySearchRepository {
        StubCitySearchRepository { _ in throw error }
    }

    func search(query: String) async throws -> [City] {
        try await handler(query)
    }
}

struct StubForecastRepository: ForecastRepository {
    let handler: @Sendable (City) async throws -> Forecast

    init(_ handler: @escaping @Sendable (City) async throws -> Forecast) {
        self.handler = handler
    }

    static func returning(_ forecast: Forecast) -> StubForecastRepository {
        StubForecastRepository { _ in forecast }
    }

    static func failing(_ error: AppError) -> StubForecastRepository {
        StubForecastRepository { _ in throw error }
    }

    func forecast(for city: City) async throws -> Forecast {
        try await handler(city)
    }
}

/// Counts calls across concurrent invocations without data races.
actor CallCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

// MARK: - Fixtures

enum Fixture {
    static let london = City(
        id: 1,
        name: "London",
        region: "England",
        country: "United Kingdom",
        coordinate: Coordinate(latitude: 51.5, longitude: -0.12)
    )

    static let paris = City(id: 2, name: "Paris", country: "France", coordinate: Coordinate(latitude: 48.85, longitude: 2.35))

    static func day(offset: Int, sea: SeaState = .noSea) -> DailyWeather {
        DailyWeather(
            date: Date(timeIntervalSince1970: 1_791_849_600 + Double(offset) * 86_400),
            maxTemperatureC: 21,
            minTemperatureC: 12,
            condition: .clear,
            precipitationMM: 0,
            snowfallCM: 0,
            snowDepthM: 0,
            precipitationProbability: 5,
            maxWindSpeedKmh: 8,
            sea: sea
        )
    }

    static let forecast = Forecast(
        city: london,
        timeZone: TimeZone(identifier: "Europe/London")!,
        days: (0..<7).map { day(offset: $0) }
    )
}

// MARK: - Async assertions

extension XCTestCase {
    /// Polls `condition` on the main actor until it is true or `timeout` elapses.
    ///
    /// View models update their state from detached-ish `Task`s, so tests cannot simply
    /// `await` a method and assert; they wait for the state machine to settle.
    @MainActor
    func waitUntil(
        _ description: String = "condition",
        timeout: Duration = .seconds(2),
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for \(description)", file: file, line: line)
    }
}
