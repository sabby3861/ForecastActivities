import ActivityDomain
import Testing

/// Typical weeks for real places, run through the production rules. Each one only checks
/// what comes first and what's ruled out, which is what a user would notice.
struct CityScenario: Sendable, CustomTestStringConvertible {
    let name: String
    let day: DailyWeather
    let expectedFirst: Activity?
    let ruledOut: Set<Activity>

    var testDescription: String { name }

    static let all: [CityScenario] = [
        CityScenario(
            name: "Denver in June (inland, warm, breezy)",
            day: Fixture.day(maxTemp: 27, minTemp: 14, precipitationProbability: 10, wind: 20, condition: .partlyCloudy, sea: .noSea),
            expectedFirst: .outdoorSightseeing,
            ruledOut: [.surfing, .skiing]
        ),
        CityScenario(
            name: "Madrid in July (inland, hot)",
            day: Fixture.day(maxTemp: 33, minTemp: 20, precipitationProbability: 5, wind: 15, condition: .clear, sea: .noSea),
            expectedFirst: nil,
            ruledOut: [.surfing, .skiing]
        ),
        CityScenario(
            name: "Toronto in January (freezing, lake waves, no snow)",
            day: Fixture.day(maxTemp: -3, minTemp: -10, precipitationProbability: 10, wind: 15, condition: .clear, sea: .waves(heightM: 0.9)),
            expectedFirst: .indoorSightseeing,
            ruledOut: [.surfing, .skiing]
        ),
        CityScenario(
            name: "Valle Nevado in October (deep snow)",
            day: Fixture.day(maxTemp: -2, minTemp: -9, snowfallCM: 3, snowDepthM: 2.3, precipitationProbability: 10, wind: 25, condition: .snow, sea: .noSea),
            expectedFirst: .skiing,
            ruledOut: [.surfing]
        ),
        CityScenario(
            name: "Sydney in summer (good swell)",
            day: Fixture.day(maxTemp: 26, minTemp: 19, precipitationProbability: 10, wind: 12, condition: .partlyCloudy, sea: .waves(heightM: 1.5)),
            expectedFirst: .surfing,
            ruledOut: [.skiing]
        ),
        CityScenario(
            name: "London in October (wet, inland)",
            day: Fixture.day(maxTemp: 13, minTemp: 8, precipitationMM: 6, precipitationProbability: 80, wind: 25, condition: .rain, sea: .noSea),
            expectedFirst: .indoorSightseeing,
            ruledOut: [.surfing, .skiing]
        ),
        CityScenario(
            name: "Dubai in January (flat sea)",
            day: Fixture.day(maxTemp: 25, minTemp: 17, precipitationProbability: 0, wind: 15, condition: .clear, sea: .waves(heightM: 0.2)),
            expectedFirst: .outdoorSightseeing,
            ruledOut: [.surfing, .skiing]
        ),
    ]
}

@Suite("City scenarios")
struct CityScenarioTests {
    @Test("Ranking makes sense for a typical week", arguments: CityScenario.all)
    func ranking(scenario: CityScenario) {
        let week = (0..<7).map { offset in
            let day = scenario.day
            return Fixture.day(
                offset: offset,
                maxTemp: day.maxTemperatureC, minTemp: day.minTemperatureC,
                precipitationMM: day.precipitationMM, snowfallCM: day.snowfallCM, snowDepthM: day.snowDepthM,
                precipitationProbability: day.precipitationProbability, wind: day.maxWindSpeedKmh,
                condition: day.condition, sea: day.sea
            )
        }
        let ranked = RankActivitiesUseCase().rank(week)

        if let expectedFirst = scenario.expectedFirst {
            #expect(ranked.first?.activity == expectedFirst)
        }
        for recommendation in ranked where scenario.ruledOut.contains(recommendation.activity) {
            #expect(recommendation.overallScore == .min, "\(recommendation.activity) should be ruled out")
        }
    }
}
