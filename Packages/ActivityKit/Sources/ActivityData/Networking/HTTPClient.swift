import ActivityDomain
import Foundation

/// Status and body of an HTTP exchange. Small enough for a test double to build in one line.
public struct HTTPResponse: Sendable {
    public let statusCode: Int
    public let data: Data

    public init(statusCode: Int, data: Data) {
        self.statusCode = statusCode
        self.data = data
    }

    public var isSuccess: Bool { (200..<300).contains(statusCode) }
}

/// The network seam. Everything above it is tested with a stub that returns canned responses.
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
