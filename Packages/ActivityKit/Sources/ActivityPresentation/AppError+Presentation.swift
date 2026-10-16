import ActivityDomain
import Foundation

/// User-facing copy for errors. Lives in Presentation, not Domain, because wording is a
/// UI concern (and the obvious place to hook localisation later).
public extension AppError {
    var userTitle: String {
        switch self {
        case .offline: return "You're offline"
        case .clientError: return "Request not accepted"
        case .serverError: return "Service unavailable"
        case .timedOut: return "Taking too long"
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
        case .clientError:
            return "The weather service couldn't handle this request."
        case .serverError:
            return "The weather service is having problems. Please try again in a moment."
        case .timedOut:
            return "The weather service took too long to answer. Please try again."
        case .invalidResponse:
            return "We got an unexpected reply from the weather service. If you're on public Wi-Fi, you may need to sign in first."
        case .noForecastAvailable:
            return "There is no forecast data for this location right now."
        case .cancelled:
            return ""
        case .network:
            return "We couldn't reach the weather service. Please try again."
        }
    }
}
