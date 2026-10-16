import ActivityDomain
import Foundation

/// Sends a request, checks the status, decodes JSON and maps every failure to `AppError`.
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
            return try JSONDecoder().decode(T.self, from: response.data)
        } catch {
            // Usually a contract break, but a captive portal's HTML login page lands here too.
            throw AppError.invalidResponse
        }
    }
}

/// Transport errors → `AppError`, decided once here rather than per repository.
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
