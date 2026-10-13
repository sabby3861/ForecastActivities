import ActivityDomain
import XCTest
@testable import ActivityData

final class APIClientTests: XCTestCase {
    private struct Payload: Decodable, Equatable, Sendable {
        let name: String
    }

    private let request = URLRequest(url: URL(string: "https://example.com/test")!)

    func testSuccess_decodesBody() async throws {
        let http = StubHTTPClient.returning(data: Data(#"{"name":"ok"}"#.utf8))
        let client = APIClient(http: http)

        let payload: Payload = try await client.get(request)

        XCTAssertEqual(payload, Payload(name: "ok"))
        let sent = await http.lastRequest
        XCTAssertEqual(sent?.url, request.url)
    }

    func testNon2xxStatus_isServerError() async {
        let client = APIClient(http: StubHTTPClient.returning(status: 503, data: Data()))

        await assertThrows(AppError.server(statusCode: 503)) {
            let _: Payload = try await client.get(self.request)
        }
    }

    func testMalformedJSON_isInvalidResponse() async {
        let client = APIClient(http: StubHTTPClient.returning(data: Data("not json".utf8)))

        await assertThrows(AppError.invalidResponse) {
            let _: Payload = try await client.get(self.request)
        }
    }

    func testMissingField_isInvalidResponse() async {
        let client = APIClient(http: StubHTTPClient.returning(data: Data(#"{"other":1}"#.utf8)))

        await assertThrows(AppError.invalidResponse) {
            let _: Payload = try await client.get(self.request)
        }
    }

    func testNoConnection_isOffline() async {
        let client = APIClient(http: StubHTTPClient.failing(with: URLError(.notConnectedToInternet)))

        await assertThrows(AppError.offline) {
            let _: Payload = try await client.get(self.request)
        }
    }

    func testTimeout_isOffline() async {
        let client = APIClient(http: StubHTTPClient.failing(with: URLError(.timedOut)))

        await assertThrows(AppError.offline) {
            let _: Payload = try await client.get(self.request)
        }
    }

    func testURLCancellation_isCancelled() async {
        let client = APIClient(http: StubHTTPClient.failing(with: URLError(.cancelled)))

        await assertThrows(AppError.cancelled) {
            let _: Payload = try await client.get(self.request)
        }
    }

    func testTaskCancellation_isCancelled() async {
        let client = APIClient(http: StubHTTPClient.failing(with: CancellationError()))

        await assertThrows(AppError.cancelled) {
            let _: Payload = try await client.get(self.request)
        }
    }

    func testOtherURLError_isNetworkWithMessage() async {
        let client = APIClient(http: StubHTTPClient.failing(with: URLError(.badURL)))

        do {
            let _: Payload = try await client.get(request)
            XCTFail("expected an error")
        } catch let error as AppError {
            guard case .network = error else { return XCTFail("expected .network, got \(error)") }
        } catch {
            XCTFail("expected AppError, got \(error)")
        }
    }

    // MARK: - Helpers

    private func assertThrows(
        _ expected: AppError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("expected \(expected) to be thrown", file: file, line: line)
        } catch let error as AppError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("expected AppError.\(expected), got \(error)", file: file, line: line)
        }
    }
}
