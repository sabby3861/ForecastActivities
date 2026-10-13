#if DEBUG
import ActivityDomain
import ActivityPresentation
import Foundation
import SwiftUI

/// Canned data and in-memory repositories for Xcode previews. Lives in the app target
/// behind `#if DEBUG` so it never ships.
enum PreviewData {
    static let london = City(
        id: 2643743,
        name: "London",
        region: "England",
        country: "United Kingdom",
        coordinate: Coordinate(latitude: 51.5085, longitude: -0.1257)
    )

    static let days: [DailyWeather] = (0..<7).map { offset in
        let date = Calendar(identifier: .gregorian).date(byAdding: .day, value: offset, to: .now) ?? .now
        let wet = offset.isMultiple(of: 3)
        return DailyWeather(
            date: date,
            maxTemperatureC: 14 + Double(offset),
            minTemperatureC: 7 + Double(offset),
            precipitationMM: wet ? 6 : 0,
            snowfallCM: 0,
            precipitationProbability: wet ? 80 : 10,
            maxWindSpeedKmh: 15 + Double(offset * 3),
            condition: wet ? .rain : .partlyCloudy
        )
    }

    static let forecast = Forecast(city: london, timeZone: TimeZone(identifier: "Europe/London")!, days: days)

    struct CityRepository: CitySearchRepository {
        func search(query: String) async throws -> [City] { [PreviewData.london] }
    }

    struct ForecastRepository: ActivityDomain.ForecastRepository {
        func forecast(for city: City) async throws -> Forecast { PreviewData.forecast }
    }
}

#Preview("City search") {
    CitySearchView(viewModel: CitySearchViewModel(repository: PreviewData.CityRepository()))
}

#Preview("Ranking") {
    NavigationStack {
        ActivityRankingView(
            viewModel: ActivityRankingViewModel(city: PreviewData.london, repository: PreviewData.ForecastRepository())
        )
    }
}
#endif
