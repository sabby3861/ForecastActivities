import ActivityDomain
import Testing

@Suite("WMO weather codes")
struct WeatherConditionTests {
    @Test("Every documented WMO code maps to the right bucket", arguments: [
        (0, WeatherCondition.clear),
        (1, .partlyCloudy), (2, .partlyCloudy),
        (3, .overcast),
        (45, .fog), (48, .fog),
        (51, .drizzle), (53, .drizzle), (55, .drizzle), (56, .drizzle), (57, .drizzle),
        (61, .rain), (63, .rain), (65, .rain), (66, .rain), (67, .rain),
        (71, .snow), (73, .snow), (75, .snow), (77, .snow), (85, .snow), (86, .snow),
        (80, .showers), (81, .showers), (82, .showers),
        (95, .thunderstorm), (96, .thunderstorm), (99, .thunderstorm),
    ])
    func mapsKnownCode(code: Int, expected: WeatherCondition) {
        #expect(WeatherCondition(wmoCode: code) == expected)
    }

    @Test("Unknown codes keep the raw value", arguments: [4, 50, 100, -1])
    func keepsUnknownCode(code: Int) {
        #expect(WeatherCondition(wmoCode: code) == .unknown(code: code))
    }

    @Test("Only falling water counts as wet", arguments: [
        (WeatherCondition.clear, false), (.partlyCloudy, false), (.overcast, false),
        (.fog, false), (.unknown(code: 4), false),
        (.drizzle, true), (.rain, true), (.showers, true), (.snow, true), (.thunderstorm, true),
    ])
    func wetness(condition: WeatherCondition, isWet: Bool) {
        #expect(condition.isWet == isWet)
    }
}
