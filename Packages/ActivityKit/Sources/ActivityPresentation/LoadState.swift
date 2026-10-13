import ActivityDomain
import Foundation

/// Explicit screen state. A view switches over this and renders exactly one branch, which
/// rules out the classic "spinner *and* stale list *and* error banner" bugs that come from
/// juggling `isLoading` / `items` / `error` as three independent properties.
public enum LoadState<Value: Equatable & Sendable>: Equatable, Sendable {
    /// Nothing requested yet (e.g. search field is empty).
    case idle
    case loading
    case loaded(Value)
    case failed(AppError)

    public var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    public var error: AppError? {
        if case .failed(let error) = self { return error }
        return nil
    }

    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}
