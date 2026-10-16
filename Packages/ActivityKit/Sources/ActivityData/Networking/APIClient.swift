import ActivityDomain
import Foundation

/// Sends a request, checks the status code, decodes JSON, and translates every failure
/// into an `AppError`. Repositories compose this with an endpoint and a mapper.
public struct APIClient: Sendable {
    private let http: any HTTPClient

    public init(http: any HTTPClient) {
        self.http = http
    }

    /// Performs `request` and decodes the body as `T`.
    public func get<T: Decodable & Sendable>(_ request: URLRequest, as type: T.Type = T.self) async throws -> T {
        let response: HTTPResponse
        do {
            response = try await http.send(request)
        } catch {
            throw AppErrorMapping.map(error)
        }

        guard response.isSuccess else {
            switch response.statusCode {
            case 400...499: throw AppError.clientError(statusCode: response.statusCode)
            default: throw AppError.serverError(statusCode: response.statusCode)
            }
        }

        do {
            return try Self.makeDecoder().decode(T.self, from: response.data)
        } catch {
            // Usually a contract break, but a captive portal's HTML login page lands here
            // too, so this stays retryable.
            throw AppError.invalidResponse
        }
    }

    /// `JSONDecoder` is not `Sendable`, so we build one per call rather than storing it.
    /// Construction is cheap; sharing would force an actor hop on every decode.
    /// DTOs declare explicit `CodingKeys` instead of relying on `.convertFromSnakeCase`, so
    /// the mapping from the API's `temperature_2m_max` is visible and greppable.
    private static func makeDecoder() -> JSONDecoder {
        JSONDecoder()
    }
}

/// Translates transport errors into the domain's `AppError`. Kept in one place so the
/// retry/offline semantics are decided once, not per repository.
enum AppErrorMapping {
    static func map(_ error: any Error) -> AppError {
        if let appError = error as? AppError {
            return appError
        }
        if error is CancellationError {
            return .cancelled
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled:
                return .cancelled
            case .timedOut:
                return .timedOut
            case .notConnectedToInternet,
                 .networkConnectionLost,
                 .cannotFindHost,
                 .cannotConnectToHost,
                 .dnsLookupFailed,
                 .internationalRoamingOff,
                 .dataNotAllowed:
                return .offline
            default:
                return .network(urlError.localizedDescription)
            }
        }
        return .network(String(describing: error))
    }
}
