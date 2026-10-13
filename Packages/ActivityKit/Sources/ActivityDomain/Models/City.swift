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

/// A place the user can pick from search results.
///
/// `id` is the Open-Meteo geonames identifier. We keep it (rather than synthesising one)
/// so results stay stable across refreshes and can be used as a `NavigationStack` value.
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

    /// "London, England, United Kingdom" — omits missing parts rather than printing "nil".
    public var displayName: String {
        [name, region, country]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}
