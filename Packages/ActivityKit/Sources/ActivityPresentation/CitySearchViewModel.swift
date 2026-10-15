import ActivityDomain
import Foundation
import Observation

/// Drives the city search screen.
///
/// Responsibilities:
/// - Debounce keystrokes so we do not hit the geocoding API on every character.
/// - Guarantee that only the *latest* query's results are ever shown (cancellation).
/// - Expose one `LoadState` the view can switch over.
///
/// `@MainActor` because its state is read by SwiftUI; `@Observable` so views re-render on
/// exactly the properties they touch (no `objectWillChange` fan-out).
@MainActor
@Observable
public final class CitySearchViewModel {
    /// Bound to the search field. Every change schedules a (debounced) search.
    public var query: String = "" {
        didSet { if query != oldValue { scheduleSearch() } }
    }

    public private(set) var state: LoadState<[City]> = .idle

    private let repository: any CitySearchRepository
    private let debounce: Duration
    private var searchTask: Task<Void, Never>?

    /// - Parameters:
    ///   - repository: where cities come from.
    ///   - debounce: how long to wait after the last keystroke. Tests pass `.zero`.
    public init(repository: any CitySearchRepository, debounce: Duration = .milliseconds(300)) {
        self.repository = repository
        self.debounce = debounce
    }

    /// Re-runs the current query, e.g. from a "Try again" button after a failure. The user
    /// tapped a button, so there's nothing to debounce: it shows `.loading` and searches now.
    public func retry() {
        search(after: nil)
    }

    private func scheduleSearch() {
        search(after: debounce)
    }

    /// Cancels any search in flight and starts one for the current query.
    ///
    /// - Parameter delay: how long to wait for typing to pause before showing `.loading`
    ///   and searching, or `nil` to do both straight away.
    private func search(after delay: Duration?) {
        // Cancelling the in-flight task is what makes "latest query wins" hold: a slow
        // response for "Lon" can never overwrite the results for "London".
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            state = .idle
            return
        }

        if delay == nil {
            state = .loading
        }
        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                if let delay {
                    try await Task.sleep(for: delay)
                    // Only now, once typing has paused: switching earlier would replace the
                    // current results with a spinner on every keystroke.
                    self.state = .loading
                }
                let cities = try await self.repository.search(query: trimmed)
                // The repository may have returned normally even though we were cancelled
                // mid-flight (not every HTTPClient cooperates with cancellation).
                guard !Task.isCancelled else { return }
                self.state = .loaded(cities)
            } catch is CancellationError {
                // Superseded by a newer query; that task owns the state now.
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
