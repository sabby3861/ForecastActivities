import Foundation

/// The only error type that crosses the Data → Presentation boundary.
///
/// Repositories translate transport-level failures (`URLError`, HTTP status codes,
/// `DecodingError`) into these cases so the presentation layer can decide what to show
/// and whether to offer "Retry" without knowing anything about URLSession.
public enum AppError: Error, Equatable, Sendable {
    /// No connectivity, DNS failure, timeout — anything where retrying later may help.
    case offline
    /// The server answered with a non-2xx status.
    case server(statusCode: Int)
    /// The response was 2xx but could not be understood (malformed JSON, missing fields).
    case invalidResponse
    /// The forecast came back with no usable days.
    case noForecastAvailable
    /// The work was cancelled (user typed again, screen dismissed). Never shown to the user.
    case cancelled
    /// Any other transport failure, with a short diagnostic message for logs.
    case network(String)

    /// Whether offering the user a "Try again" action makes sense.
    public var isRetryable: Bool {
        switch self {
        case .offline, .server, .network, .noForecastAvailable: return true
        case .invalidResponse, .cancelled: return false
        }
    }
}
