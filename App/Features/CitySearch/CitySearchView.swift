import ActivityDomain
import ActivityPresentation
import SwiftUI

/// Entry screen: search for a city, tap a result to see the activity ranking.
struct CitySearchView: View {
    @State private var viewModel: CitySearchViewModel
    @Environment(\.appContainer) private var container

    init(viewModel: CitySearchViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Where to?")
                .navigationDestination(for: City.self) { city in
                    if let container {
                        ActivityRankingView(viewModel: container.makeActivityRankingViewModel(for: city))
                    } else {
                        let _ = assertionFailure("AppContainer missing from environment")
                        ContentUnavailableView("Configuration error", systemImage: "exclamationmark.triangle")
                    }
                }
        }
        .searchable(text: $viewModel.query, prompt: "Search for a city")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.words)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle:
            ContentUnavailableView(
                "Find a destination",
                systemImage: "magnifyingglass",
                description: Text("Type a city name to see which activities suit its weather over the next 7 days.")
            )

        case .loading:
            ProgressView("Searching…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loaded(let cities) where cities.isEmpty:
            ContentUnavailableView.search(text: viewModel.query)

        case .loaded(let cities):
            List(cities) { city in
                NavigationLink(value: city) {
                    CityRow(city: city)
                }
            }
            .listStyle(.plain)

        case .failed(let error):
            ErrorView(error: error) {
                viewModel.retry()
            }
        }
    }
}

private struct CityRow: View {
    let city: City

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(city.name)
                .font(.body.weight(.medium))
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(city.displayName)
    }

    private var subtitle: String {
        [city.region, city.country].compactMap { $0 }.joined(separator: ", ")
    }
}
