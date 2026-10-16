// swift-tools-version: 6.0
import PackageDescription

/// ActivityKit holds everything that is not SwiftUI: the domain model and rules,
/// the Open-Meteo data layer, and the presentation state (view models).
///
/// Keeping it as a Swift package (rather than app-target folders) gives us:
/// - Compiler-enforced layering: `ActivityDomain` cannot import `ActivityData`.
/// - Fast tests: `swift test` runs on macOS in seconds, no simulator needed.
/// - A codebase that is trivially reusable by a second app target (e.g. widgets, watchOS).
let package = Package(
    name: "ActivityKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ActivityDomain", targets: ["ActivityDomain"]),
        .library(name: "ActivityData", targets: ["ActivityData"]),
        .library(name: "ActivityPresentation", targets: ["ActivityPresentation"]),
    ],
    targets: [
        // Pure model + business rules. No networking, no UI.
        .target(name: "ActivityDomain"),

        // Open-Meteo API client, DTOs and repository implementations. Depends only on Domain.
        .target(name: "ActivityData", dependencies: ["ActivityDomain"]),

        // Observable view models and explicit screen state. Depends only on Domain (never on Data).
        .target(name: "ActivityPresentation", dependencies: ["ActivityDomain"]),

        .testTarget(name: "ActivityDomainTests", dependencies: ["ActivityDomain"]),
        .testTarget(name: "ActivityDataTests", dependencies: ["ActivityData", "ActivityDomain"]),
        .testTarget(name: "ActivityPresentationTests", dependencies: ["ActivityPresentation", "ActivityDomain"]),
    ],
    swiftLanguageModes: [.v6]
)
