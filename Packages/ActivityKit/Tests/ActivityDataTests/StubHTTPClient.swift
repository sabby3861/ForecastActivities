import ActivityDomain
import Foundation
@testable import ActivityData

/// A scripted `HTTPClient`. Records every request so tests can assert on URLs, and returns
/// whatever result the test queued — a response or an error.
///
/// An `actor` rather than a class so it is `Sendable` under strict concurrency without
/// locks or `@unchecked`.
actor StubHTTPClient: HTTPClient {
    enum Scripted {
        case response(HTTPResponse)
        case failure(any Error)
    }

    private(set) var requests: [URLRequest] = []
    private var script: [Scripted]

    init(_ script: Scripted...) {
        self.script = script
    }

    static func returning(status: Int = 200, data: Data) -> StubHTTPClient {
        StubHTTPClient(.response(HTTPResponse(statusCode: status, data: data)))
    }

    static func failing(with error: any Error) -> StubHTTPClient {
        StubHTTPClient(.failure(error))
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requests.append(request)
        guard !script.isEmpty else {
            throw URLError(.badServerResponse)
        }
        switch script.removeFirst() {
        case .response(let response): return response
        case .failure(let error): throw error
        }
    }

    var lastRequest: URLRequest? { requests.last }
}
