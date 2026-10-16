import Foundation

/// A geographic coordinate in decimal degrees.
public struct Coordinate: Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// A place from search results. `id` is Open-Meteo's geonames id, so it is stable across
/// refreshes and usable as a `NavigationStack` value.
public struct City: Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
    /// First-level administrative area (state, county, region). Optional in the API.
    public let region: String?
    public let country: String?
    public let coordinate: Coordinate

    public init(id: Int, name: String, region: String? = nil, country: String? = nil, coordinate: Coordinate) {
        self.id = id
        self.name = name
        self.region = region
        self.country = country
        self.coordinate = coordinate
    }

    /// "London, England, United Kingdom", omitting missing parts.
    public var displayName: String {
        [name, region, country]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}
