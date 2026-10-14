import ActivityDomain
import ActivityPresentation
import Testing

@Suite("Score bands")
struct ScoreBandTests {
    // Both edges of every band, so a gap or overlap between bands fails here.
    @Test("Band boundaries", arguments: [
        (100, Score.Band.excellent), (85, .excellent),
        (84, .good), (70, .good),
        (69, .fair), (40, .fair),
        (39, .poor), (0, .poor),
    ])
    func band(value: Int, expected: Score.Band) {
        #expect(Score(value: value).band == expected)
    }

    @Test("Every activity has a display name", arguments: Activity.allCases)
    func displayName(activity: Activity) {
        #expect(!activity.displayName.isEmpty)
    }
}
