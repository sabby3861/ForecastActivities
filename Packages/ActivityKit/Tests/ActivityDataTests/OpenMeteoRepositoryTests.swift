import ActivityDomain
import XCTest
@testable import ActivityData

final class OpenMeteoCitySearchRepositoryTests: XCTestCase {
    func testSearch_mapsResultsInOrder() async throws {
        let http = StubHTTPClient.returning(data: Fixtures.geocodingLondon)
        let repository = OpenMeteoCitySearchRepository(client: APIClient(http: http))

        let cities = try await repository.search(query: "London")

        XCTAssertEqual(cities.count, 2)
        XCTAssertEqual(cities[0], Fixtures.city)
        XCTAssertEqual(cities[0].displayName, "London, England, United Kingdom")
        XCTAssertEqual(cities[1].country, "Canada")
    }

    func testSearch_withNoResultsKey_returnsEmptyArray() async throws {
        let http = StubHTTPClient.returning(data: Fixtures.geocodingNoResults)
        let repository = OpenMeteoCitySearchRepository(client: APIClient(http: http))

        let cities = try await repository.search(query: "Zzzzzz")

        XCTAssertTrue(cities.isEmpty)
    }

    func testSearch_trimsWhitespaceBeforeSending() async throws {
        let http = StubHTTPClient.returning(data: Fixtures.geocodingNoResults)
        let repository = OpenMeteoCitySearchRepository(client: APIClient(http: http))

        _ = try await repository.search(query: "  Paris \n")

        let sentURL = await http.lastRequest?.url
        let url = try XCTUnwrap(sentURL)
        let name = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "name" }?.value
        XCTAssertEqual(name, "Paris")
    }

    func testSearch_withQueryShorterThanTwoCharacters_doesNotHitNetwork() async throws {
        let http = StubHTTPClient()
        let repository = OpenMeteoCitySearchRepository(client: APIClient(http: http))

        let cities = try await repository.search(query: "L")

        XCTAssertTrue(cities.isEmpty)
        let requests = await http.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testSearch_propagatesAppErrors() async {
        let repository = OpenMeteoCitySearchRepository(
            client: APIClient(http: StubHTTPClient.returning(status: 429, data: Data()))
        )

        do {
            _ = try await repository.search(query: "London")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? AppError, .server(statusCode: 429))
        }
    }
}

final class OpenMeteoForecastRepositoryTests: XCTestCase {
    func testForecast_mapsSevenDays() async throws {
        let http = StubHTTPClient.returning(data: Fixtures.forecastSevenDays)
        let repository = OpenMeteoForecastRepository(client: APIClient(http: http))

        let forecast = try await repository.forecast(for: Fixtures.city)

        XCTAssertEqual(forecast.city, Fixtures.city)
        XCTAssertEqual(forecast.timeZone.identifier, "Europe/London")
        XCTAssertEqual(forecast.days.count, 7)

        let first = forecast.days[0]
        XCTAssertEqual(first.maxTemperatureC, 15.2)
        XCTAssertEqual(first.minTemperatureC, 8.1)
        XCTAssertEqual(first.precipitationProbability, 10)
        XCTAssertEqual(first.maxWindSpeedKmh, 18.4)
        XCTAssertEqual(first.snowDepthM, 0)
        XCTAssertEqual(first.condition, .overcast)

        XCTAssertEqual(forecast.days[1].condition, .rain)
        XCTAssertEqual(forecast.days[2].condition, .showers)
        XCTAssertEqual(forecast.days[6].condition, .thunderstorm)
    }

    func testForecast_datesAreLocalMidnightInTheLocationTimeZone() async throws {
        let http = StubHTTPClient.returning(data: Fixtures.forecastSevenDays)
        let repository = OpenMeteoForecastRepository(client: APIClient(http: http))

        let forecast = try await repository.forecast(for: Fixtures.city)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = forecast.timeZone
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: forecast.days[0].date)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 10)
        XCTAssertEqual(components.day, 13)
        XCTAssertEqual(components.hour, 0)
        XCTAssertEqual(components.minute, 0)

        // Days are strictly increasing and one calendar day apart.
        let gaps = zip(forecast.days, forecast.days.dropFirst()).map {
            calendar.dateComponents([.day], from: $0.date, to: $1.date).day
        }
        XCTAssertEqual(gaps, Array(repeating: 1, count: 6))
    }

    func testForecast_dropsDaysMissingRequiredFields_andKeepsOptionalOnesAsNil() async throws {
        let http = StubHTTPClient.returning(data: Fixtures.forecastWithNulls)
        let repository = OpenMeteoForecastRepository(client: APIClient(http: http))

        let forecast = try await repository.forecast(for: Fixtures.city)

        XCTAssertEqual(forecast.days.count, 2, "day 2 (no max temp) and day 4 (no weather code) are dropped")
        XCTAssertEqual(forecast.days.map(\.maxTemperatureC), [20.0, 22.0])

        let third = forecast.days[1]
        XCTAssertNil(third.precipitationMM, "missing values are passed on, not guessed")
        XCTAssertNil(third.precipitationProbability)
        XCTAssertNil(third.maxWindSpeedKmh)
        XCTAssertNil(third.snowDepthM)
    }

    func testForecast_withNoUsableDays_throwsNoForecastAvailable() async {
        let repository = OpenMeteoForecastRepository(
            client: APIClient(http: StubHTTPClient.returning(data: Fixtures.forecastAllNull))
        )

        do {
            _ = try await repository.forecast(for: Fixtures.city)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? AppError, .noForecastAvailable)
        }
    }

    func testForecast_withMismatchedArrayLengths_throwsInvalidResponse() async {
        let repository = OpenMeteoForecastRepository(
            client: APIClient(http: StubHTTPClient.returning(data: Fixtures.forecastMismatchedLengths))
        )

        do {
            _ = try await repository.forecast(for: Fixtures.city)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? AppError, .invalidResponse)
        }
    }

    func testForecast_sendsCityCoordinates() async throws {
        let http = StubHTTPClient.returning(data: Fixtures.forecastSevenDays)
        let repository = OpenMeteoForecastRepository(client: APIClient(http: http))

        _ = try await repository.forecast(for: Fixtures.city)

        let sentURL = await http.lastRequest?.url
        let url = try XCTUnwrap(sentURL)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "latitude" }?.value, "51.5085")
        XCTAssertEqual(items.first { $0.name == "longitude" }?.value, "-0.1257")
    }
}
