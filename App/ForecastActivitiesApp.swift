import SwiftUI

@main
struct ForecastActivitiesApp: App {
    /// The composition root. Built once, for the lifetime of the process.
    private let container = AppContainer.live()

    var body: some Scene {
        WindowGroup {
            CitySearchView(viewModel: container.makeCitySearchViewModel())
                .appContainer(container)
        }
    }
}
