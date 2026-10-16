import ActivityDomain
import Foundation

/// User-facing names, kept out of the domain.
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

/// Human-readable bands for a score.
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
