import ActivityData
import ActivityDomain
import ActivityPresentation
import Foundation
import SwiftUI

/// Composition root: the one place that knows how concrete types are wired together.
///
/// Views receive view models from here instead of constructing repositories themselves, so
/// swapping the network stack (stub for previews/UI tests, a cached repository later) is a
/// one-line change in `live()` rather than a hunt through the feature code.
@MainActor
struct AppContainer {
    let citySearchRepository: any CitySearchRepository
    let forecastRepository: any ForecastRepository
    let rankActivities: RankActivitiesUseCase

    static func live() -> AppContainer {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 15

        let client = APIClient(http: URLSessionHTTPClient(session: URLSession(configuration: configuration)))
        return AppContainer(
            citySearchRepository: OpenMeteoCitySearchRepository(client: client),
            forecastRepository: OpenMeteoForecastRepository(client: client),
            rankActivities: RankActivitiesUseCase()
        )
    }

    func makeCitySearchViewModel() -> CitySearchViewModel {
        CitySearchViewModel(repository: citySearchRepository)
    }

    func makeActivityRankingViewModel(for city: City) -> ActivityRankingViewModel {
        ActivityRankingViewModel(city: city, repository: forecastRepository, rankActivities: rankActivities)
    }
}

// MARK: - Environment plumbing

private struct AppContainerKey: EnvironmentKey {
    static let defaultValue: AppContainer? = nil
}

extension EnvironmentValues {
    var appContainer: AppContainer? {
        get { self[AppContainerKey.self] }
        set { self[AppContainerKey.self] = newValue }
    }
}

extension View {
    func appContainer(_ container: AppContainer) -> some View {
        environment(\.appContainer, container)
    }
}
