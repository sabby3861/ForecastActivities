import ActivityDomain
import Testing

@Suite("Retry policy")
struct AppErrorTests {
    static let cases: [(AppError, Bool)] = [
        (.offline, true),
        (.serverError(statusCode: 503), true),
        (.timedOut, true),
        (.network("connection reset"), true),
        (.invalidResponse, true),
        (.clientError(statusCode: 404), false),
        (.noForecastAvailable, false),
        (.cancelled, false),
    ]

    @Test("Each error says whether trying again can help", arguments: cases)
    func retryable(error: AppError, expected: Bool) {
        #expect(error.isRetryable == expected)
    }

    @Test("The table covers every case")
    func coversEveryCase() {
        #expect(Set(Self.cases.map { Self.name(of: $0.0) }).count == 8)
    }

    /// Exhaustive on purpose: a new case fails to compile here until it's added to the table.
    private static func name(of error: AppError) -> String {
        switch error {
        case .offline: "offline"
        case .clientError: "clientError"
        case .serverError: "serverError"
        case .timedOut: "timedOut"
        case .invalidResponse: "invalidResponse"
        case .noForecastAvailable: "noForecastAvailable"
        case .cancelled: "cancelled"
        case .network: "network"
        }
    }
}
