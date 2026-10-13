import ActivityDomain
import Foundation

/// The raw result of an HTTP exchange. A tiny value type instead of `HTTPURLResponse`
/// so test doubles can build one in a single line and nothing in the package depends on
/// `URLSession` types above this file.
public struct HTTPResponse: Sendable {
    public let statusCode: Int
    public let data: Data

    public init(statusCode: Int, data: Data) {
        self.statusCode = statusCode
        self.data = data
    }

    public var isSuccess: Bool { (200..<300).contains(statusCode) }
}

/// The seam between our code and the network.
///
/// Everything above this protocol (API client, repositories, view models) is testable with
/// a stub that returns canned `HTTPResponse` values — no `URLProtocol` subclassing needed.
public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

/// Production `HTTPClient` backed by `URLSession`.
public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.invalidResponse
        }
        return HTTPResponse(statusCode: http.statusCode, data: data)
    }
}
