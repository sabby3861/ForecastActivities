import ActivityData
import ActivityDomain
import ActivityPresentation
import Foundation
import SwiftUI

/// Composition root: the one place concrete types are wired together.
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
