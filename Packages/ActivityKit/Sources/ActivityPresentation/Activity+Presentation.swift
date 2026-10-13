import ActivityDomain
import Foundation

/// User-facing names for activities. Kept out of the domain so the rules stay free of copy,
/// and in one place so localisation (a string catalog) is a single-file change.
public extension Activity {
    var displayName: String {
        switch self {
        case .skiing: return "Skiing"
        case .surfing: return "Surfing"
        case .outdoorSightseeing: return "Outdoor sightseeing"
        case .indoorSightseeing: return "Indoor sightseeing"
        }
    }
}

/// Human-readable bands for a score. Presentation decides what "good" means to a person;
/// the domain only promises 0…100.
public extension Score {
    enum Band: Sendable {
        case excellent, good, fair, poor

        public var label: String {
            switch self {
            case .excellent: return "Excellent"
            case .good: return "Good"
            case .fair: return "Fair"
            case .poor: return "Poor"
            }
        }
    }

    var band: Band {
        switch value {
        case 85...: return .excellent
        case 70..<85: return .good
        case 40..<70: return .fair
        default: return .poor
        }
    }
}
