import ActivityDomain
import Foundation

/// User-facing copy for errors. Lives in Presentation, not Domain, because wording is a
/// UI concern (and the obvious place to hook localisation later).
public extension AppError {
    var userTitle: String {
        switch self {
        case .offline: return "You're offline"
        case .server: return "Service unavailable"
        case .invalidResponse: return "Something went wrong"
        case .noForecastAvailable: return "No forecast available"
        case .cancelled: return ""
        case .network: return "Connection problem"
        }
    }

    var userMessage: String {
        switch self {
        case .offline:
            return "Check your internet connection and try again."
        case .server(let statusCode):
            return "The weather service returned an error (\(statusCode)). Please try again in a moment."
        case .invalidResponse:
            return "We received an unexpected response from the weather service."
        case .noForecastAvailable:
            return "There is no forecast data for this location right now."
        case .cancelled:
            return ""
        case .network:
            return "We couldn't reach the weather service. Please try again."
        }
    }
}
