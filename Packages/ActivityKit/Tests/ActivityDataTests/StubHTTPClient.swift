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
    private var routes: [String: Scripted] = [:]

    init(_ script: Scripted...) {
        self.script = script
    }

    /// Answers by host instead of in order, for repositories that send requests concurrently.
    init(routes: [String: Scripted]) {
        self.script = []
        self.routes = routes
    }

    static func returning(status: Int = 200, data: Data) -> StubHTTPClient {
        StubHTTPClient(.response(HTTPResponse(statusCode: status, data: data)))
    }

    static func failing(with error: any Error) -> StubHTTPClient {
        StubHTTPClient(.failure(error))
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requests.append(request)
        let next: Scripted
        if let host = request.url?.host, let routed = routes[host] {
            next = routed
        } else if !script.isEmpty {
            next = script.removeFirst()
        } else {
            throw URLError(.badServerResponse)
        }
        switch next {
        case .response(let response): return response
        case .failure(let error): throw error
        }
    }

    func requests(toHost host: String) -> [URLRequest] {
        requests.filter { $0.url?.host == host }
    }

    var lastRequest: URLRequest? { requests.last }
}
