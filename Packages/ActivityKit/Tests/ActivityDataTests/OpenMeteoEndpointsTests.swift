import ActivityDomain
import XCTest
@testable import ActivityData

final class OpenMeteoEndpointsTests: XCTestCase {
    private let endpoints = OpenMeteoEndpoints()

    func testCitySearch_buildsExpectedURL() throws {
        let request = endpoints.citySearch(query: "São Paulo")
        let components = try components(of: request)

        XCTAssertEqual(components.host, "geocoding-api.open-meteo.com")
        XCTAssertEqual(components.path, "/v1/search")
        XCTAssertEqual(query(components, "name"), "São Paulo", "URLComponents percent-encodes for us; the decoded value must round-trip")
        XCTAssertEqual(query(components, "count"), "10")
        XCTAssertEqual(query(components, "format"), "json")
        XCTAssertEqual(request.httpMethod, "GET")
    }

    func testForecast_requestsEveryVariableTheMapperNeeds() throws {
        let request = endpoints.forecast(for: Coordinate(latitude: 51.50853, longitude: -0.12574))
        let components = try components(of: request)

        XCTAssertEqual(components.host, "api.open-meteo.com")
        XCTAssertEqual(components.path, "/v1/forecast")
        XCTAssertEqual(query(components, "latitude"), "51.5085")
        XCTAssertEqual(query(components, "longitude"), "-0.1257")
        XCTAssertEqual(query(components, "timezone"), "auto")
        XCTAssertEqual(query(components, "forecast_days"), "7")

        let daily = try XCTUnwrap(query(components, "daily")).split(separator: ",").map(String.init)
        for variable in DailySeriesDTO.CodingKeys.allCases where variable != .time {
            XCTAssertTrue(daily.contains(variable.rawValue), "daily= is missing \(variable.rawValue)")
        }
    }

    func testForecast_usesCustomBaseURL() throws {
        let custom = OpenMeteoEndpoints(forecastBase: URL(string: "https://proxy.example.test")!)
        let request = custom.forecast(for: Coordinate(latitude: 0, longitude: 0))
        XCTAssertEqual(request.url?.host, "proxy.example.test")
    }

    private func components(of request: URLRequest) throws -> URLComponents {
        let url = try XCTUnwrap(request.url)
        return try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
    }

    private func query(_ components: URLComponents, _ name: String) -> String? {
        components.queryItems?.first { $0.name == name }?.value
    }
}
