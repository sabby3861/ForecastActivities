import ActivityDomain
import ActivityPresentation
import Foundation
import SwiftUI

/// Shared formatting so the two screens agree.
enum Formatting {
    /// "Tue 14" — weekday + day-of-month, rendered in the *location's* time zone.
    static func shortDay(_ date: Date, in timeZone: TimeZone) -> String {
        date.formatted(Date.FormatStyle(timeZone: timeZone).weekday(.abbreviated).day())
    }

    /// "Tuesday 14 October" — for headers.
    static func longDay(_ date: Date, in timeZone: TimeZone) -> String {
        date.formatted(Date.FormatStyle(timeZone: timeZone).weekday(.wide).day().month(.wide))
    }

    /// "14 Oct – 20 Oct"
    static func dateRange(_ dates: [Date], in timeZone: TimeZone) -> String {
        guard let first = dates.first, let last = dates.last else { return "" }
        let style = Date.FormatStyle(timeZone: timeZone).day().month(.abbreviated)
        return "\(first.formatted(style)) – \(last.formatted(style))"
    }

    /// "12°" — whole degrees, locale-aware sign.
    static func temperature(_ celsius: Double) -> String {
        Measurement(value: celsius, unit: UnitTemperature.celsius)
            .formatted(.measurement(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))))
    }
}

extension Activity {
    var symbolName: String {
        switch self {
        case .skiing: return "figure.skiing.downhill"
        case .surfing: return "figure.surfing"
        case .outdoorSightseeing: return "camera"
        case .indoorSightseeing: return "building.columns"
        }
    }
}

extension WeatherCondition {
    var symbolName: String {
        switch self {
        case .clear: return "sun.max"
        case .partlyCloudy: return "cloud.sun"
        case .overcast: return "cloud"
        case .fog: return "cloud.fog"
        case .drizzle: return "cloud.drizzle"
        case .rain: return "cloud.rain"
        case .snow: return "cloud.snow"
        case .showers: return "cloud.heavyrain"
        case .thunderstorm: return "cloud.bolt.rain"
        case .unknown: return "questionmark.circle"
        }
    }

    var label: String {
        switch self {
        case .clear: return "Clear"
        case .partlyCloudy: return "Partly cloudy"
        case .overcast: return "Overcast"
        case .fog: return "Fog"
        case .drizzle: return "Drizzle"
        case .rain: return "Rain"
        case .snow: return "Snow"
        case .showers: return "Showers"
        case .thunderstorm: return "Thunderstorm"
        case .unknown(let code): return "Code \(code)"
        }
    }
}

extension Score.Band {
    /// Semantic colour per band, always shown alongside a text label.
    var tint: Color {
        switch self {
        case .excellent, .good: return .green
        case .fair: return .orange
        case .poor: return .red
        }
    }
}

extension Score {
    var tint: Color { band.tint }
}
