import Foundation

/// The only error type that crosses the Data → Presentation boundary.
///
/// Repositories translate transport-level failures (`URLError`, HTTP status codes,
/// `DecodingError`) into these cases so the presentation layer can decide what to show
/// and whether to offer "Retry" without knowing anything about URLSession.
public enum AppError: Error, Equatable, Sendable {
    /// No connectivity or DNS failure — anything where retrying later may help.
    case offline
    /// The server rejected the request (4xx). Sending the same request again won't help.
    case clientError(statusCode: Int)
    /// The server failed (5xx, or any other non-2xx status). Usually temporary.
    case serverError(statusCode: Int)
    /// The request took longer than the session's timeout.
    case timedOut
    /// The response was 2xx but could not be understood (malformed JSON, missing fields).
    /// Retryable: a captive portal answers 200 with an HTML login page.
    case invalidResponse
    /// The forecast came back with no usable days. Retrying returns the same data.
    case noForecastAvailable
    /// The work was cancelled (user typed again, screen dismissed). Never shown to the user.
    case cancelled
    /// Any other transport failure, with a short diagnostic message for logs.
    case network(String)

    /// Whether offering the user a "Try again" action makes sense.
    public var isRetryable: Bool {
        switch self {
        case .offline, .serverError, .timedOut, .network, .invalidResponse: return true
        case .clientError, .noForecastAvailable, .cancelled: return false
        }
    }
}
