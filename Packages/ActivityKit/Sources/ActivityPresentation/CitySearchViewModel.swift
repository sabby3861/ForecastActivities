import ActivityDomain
import Foundation
import Observation

/// Drives the city search screen: debounces typing, and guarantees that only the latest
/// query's results are ever shown.
@MainActor
@Observable
public final class CitySearchViewModel {
    /// Bound to the search field.
    public var query: String = "" {
        didSet { if query != oldValue { scheduleSearch() } }
    }

    public private(set) var state: LoadState<[City]> = .idle

    private let repository: any CitySearchRepository
    private let debounce: Duration
    private var searchTask: Task<Void, Never>?

    /// - Parameter debounce: how long to wait after the last keystroke. Tests pass `.zero`.
    public init(repository: any CitySearchRepository, debounce: Duration = .milliseconds(300)) {
        self.repository = repository
        self.debounce = debounce
    }

    /// Re-runs the current query immediately. A tap needs no debounce.
    public func retry() {
        search(after: nil)
    }

    private func scheduleSearch() {
        search(after: debounce)
    }

    /// Cancels any search in flight and starts one for the current query, after `delay`
    /// if given.
    private func search(after delay: Duration?) {
        // Cancelling the previous task is what makes "latest query wins" hold.
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            state = .idle
            return
        }

        if delay == nil {
            state = .loading
        }
        searchTask = Task {
            do {
                if let delay {
                    try await Task.sleep(for: delay)
                    // Only once typing has paused, so results aren't replaced by a spinner per keystroke.
                    self.state = .loading
                }
                let cities = try await self.repository.search(query: trimmed)
                // Not every HTTPClient cooperates with cancellation.
                guard !Task.isCancelled else { return }
                self.state = .loaded(cities)
            } catch is CancellationError {
                // Superseded by a newer query.
            } catch let error as AppError {
                guard !Task.isCancelled, error != .cancelled else { return }
                self.state = .failed(error)
            } catch {
                guard !Task.isCancelled else { return }
                self.state = .failed(.network(String(describing: error)))
            }
        }
    }
}
