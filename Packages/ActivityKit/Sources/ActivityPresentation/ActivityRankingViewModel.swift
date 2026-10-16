import ActivityDomain
import Foundation
import Observation

/// Everything the ranking screen renders, bundled so `LoadState` carries one value.
public struct ActivityRanking: Equatable, Sendable {
    public let forecast: Forecast
    public let recommendations: [ActivityRecommendation]

    public init(forecast: Forecast, recommendations: [ActivityRecommendation]) {
        self.forecast = forecast
        self.recommendations = recommendations
    }

    /// True when any day lacked wave data, so surfing used the wind-based estimate.
    public var surfingIsEstimated: Bool {
        forecast.days.contains { $0.sea == .unknown }
    }
}

/// Drives the activity ranking screen for one city.
@MainActor
@Observable
public final class ActivityRankingViewModel {
    public let city: City
    public private(set) var state: LoadState<ActivityRanking> = .idle

    /// A failed pull-to-refresh keeps the content on screen and shows this as a notice.
    public private(set) var refreshError: AppError?

    private let repository: any ForecastRepository
    private let rankActivities: RankActivitiesUseCase

    public init(
        city: City,
        repository: any ForecastRepository,
        rankActivities: RankActivitiesUseCase = RankActivitiesUseCase()
    ) {
        self.city = city
        self.repository = repository
        self.rankActivities = rankActivities
    }

    /// Initial load. A no-op once loaded, so `.task {}` can call it repeatedly.
    public func load() async {
        guard state.value == nil else { return }
        state = .loading
        await fetch(keepingContentOnFailure: false)
    }

    /// Explicit retry after a failure. Always refetches.
    public func retry() async {
        state = .loading
        await fetch(keepingContentOnFailure: false)
    }

    /// Pull-to-refresh. Keeps the current content visible if the refresh fails.
    public func refresh() async {
        refreshError = nil
        await fetch(keepingContentOnFailure: true)
    }

    private func fetch(keepingContentOnFailure keepContent: Bool) async {
        do {
            let forecast = try await repository.forecast(for: city)
            guard !Task.isCancelled else { return }
            let recommendations = rankActivities.rank(forecast.days)
            state = .loaded(ActivityRanking(forecast: forecast, recommendations: recommendations))
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            let appError = (error as? AppError) ?? .network(String(describing: error))
            guard appError != .cancelled else { return }
            if keepContent, state.value != nil {
                refreshError = appError
            } else {
                state = .failed(appError)
            }
        }
    }
}
