import ActivityDomain
import Foundation
import Testing
@testable import ActivityData

@Suite("Transport error mapping")
struct AppErrorMappingTests {
    @Test("Connectivity failures are reported as offline", arguments: [
        URLError.Code.notConnectedToInternet,
        .networkConnectionLost,
        .cannotFindHost,
        .cannotConnectToHost,
        .dnsLookupFailed,
        .internationalRoamingOff,
        .dataNotAllowed,
    ])
    func offline(code: URLError.Code) {
        #expect(AppErrorMapping.map(URLError(code)) == .offline)
    }

    @Test("A timeout is reported as timed out, not offline")
    func timedOut() {
        #expect(AppErrorMapping.map(URLError(.timedOut)) == .timedOut)
    }

    @Test("Cancellation from either source maps to cancelled", arguments: [
        URLError(.cancelled) as any Error,
        CancellationError(),
    ])
    func cancelled(error: any Error) {
        #expect(AppErrorMapping.map(error) == .cancelled)
    }

    @Test("Other URL errors keep a diagnostic message", arguments: [
        URLError.Code.badURL, .secureConnectionFailed, .badServerResponse,
    ])
    func network(code: URLError.Code) throws {
        let mapped = AppErrorMapping.map(URLError(code))
        guard case .network(let message) = mapped else {
            Issue.record("expected .network, got \(mapped)")
            return
        }
        #expect(!message.isEmpty)
    }

    @Test("An AppError passes through unchanged")
    func passthrough() {
        #expect(AppErrorMapping.map(AppError.noForecastAvailable) == .noForecastAvailable)
    }
}
