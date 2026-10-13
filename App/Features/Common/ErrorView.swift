import ActivityDomain
import ActivityPresentation
import SwiftUI

/// Full-screen error state with an optional retry action.
struct ErrorView: View {
    let error: AppError
    let retry: (() -> Void)?

    init(error: AppError, retry: (() -> Void)? = nil) {
        self.error = error
        self.retry = retry
    }

    var body: some View {
        ContentUnavailableView {
            Label(error.userTitle, systemImage: symbolName)
        } description: {
            Text(error.userMessage)
        } actions: {
            if error.isRetryable, let retry {
                Button("Try again", action: retry)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var symbolName: String {
        switch error {
        case .offline: return "wifi.slash"
        case .server, .network: return "cloud.bolt"
        case .noForecastAvailable: return "calendar.badge.exclamationmark"
        case .invalidResponse, .cancelled: return "exclamationmark.triangle"
        }
    }
}
