# Forecast Activities

An iOS app where you search for a city and get skiing, surfing, outdoor sightseeing and indoor sightseeing ranked for the next 7 days, based on the Open-Meteo forecast.

## Overview

There are two screens. The first is a city search that hits the Open-Meteo geocoding API as you type, with a short debounce. Tap a result and you get the ranking screen. It fetches a 7-day daily forecast and wave forecast, scores each activity for each day, and lists the activities best first. Each row shows the overall score, the best day and a small strip of daily scores. The raw forecast is underneath so you can see why something ranked where it did. Pull to refresh is supported, and if a refresh fails the old results stay on screen.

The UI is plain SwiftUI. The brief said architecture, correctness and testing mattered more than polish, so that's where I spent the time.

## Platform and tooling

- iOS 17+, SwiftUI, Swift 6 language mode with strict concurrency on.
- `@Observable` view models, async/await for everything async. I didn't use Combine because cancellation with tasks made "latest search wins" simple.
- Protocol-based constructor injection, wired up by hand in `AppContainer`. With three dependencies, a DI framework would be overkill.
- XCTest for most tests. Swift Testing for the table-style ones (WMO codes, score bands, error mapping, city scenarios), where `@Test(arguments:)` reports each row separately.
- No third-party dependencies.
- The Xcode project is generated with XcodeGen from `project.yml`. The generated project is committed, so you don't need XcodeGen to build.

## Architecture

Everything that isn't a view lives in a local Swift package, `Packages/ActivityKit`, split into three targets:

- `ActivityDomain`: models, repository protocols, the scoring rules and the ranking use case. No networking, no UI.
- `ActivityData`: the Open-Meteo client, DTOs, mapping to domain models, and the repository implementations.
- `ActivityPresentation`: the two view models and `LoadState`.

Presentation and Data both depend on Domain, and neither knows about the other. The package manifest enforces that, so a view model can't import a DTO even by accident. The app target holds the SwiftUI views and `AppContainer`, which is the only place the concrete types are wired together.

Each screen's state is a `LoadState` enum (`idle`, `loading`, `loaded`, `failed`), and the views switch over it. The ranking screen also has a separate `refreshError`, so a failed pull-to-refresh can show a small notice without throwing away good content.

Errors from the network layer (URLError, HTTP status, decoding) are mapped to a single `AppError` type in one place. View models only ever see that type. 4xx, 5xx and timeouts are separate cases, because they need different answers: a 4xx won't succeed on a second try, so there's no "Try again" button, while a 5xx or a timeout usually will. The user-facing wording lives in the presentation layer.

Each scoring rule conforms to `ActivityScoring`, a pure function from one day's weather to a score. `IndoorSightseeingScorer` is the one rule that doesn't. It's the fallback, so it's scored against the best other activity that day rather than on the weather alone: a −5 °C powder day is bad weather for being outside, but it must not send the user to a museum when skiing is excellent. The trade-off is that the fallback is coupled to the other rules, so `RankActivitiesUseCase` scores it last, once the others are known.

## Building and running

You need Xcode 16 or later.

```
open ForecastActivities.xcodeproj
```

Pick an iPhone simulator and run. You don't need any API keys.

If you change `project.yml`, regenerate the project with `xcodegen generate` (or `make project`).

## Tests

```
cd Packages/ActivityKit
swift test
```

`make test` does the same. The tests run on macOS without a simulator and take about a second. The same tests also run from the app scheme: press ⌘U in Xcode, or run `make test-xcode` to use the first available iPhone simulator. CI runs both on every push to `main` and on pull requests. There are 91 XCTest tests, plus 10 Swift Testing tests that expand to 75 cases once the tables are unrolled:

- Domain: the curve helpers, each activity's scoring rules and gates, the ranking (sort order, tie-breaks, averaging, best day), and a set of city scenarios (Denver in June, Toronto in January, Valle Nevado with snow, Sydney with swell and so on) that check what ranks first and what's ruled out.
- Data: request building, error mapping for status codes, timeouts, offline and bad JSON, and mapping real-shaped Open-Meteo payloads, including the awkward ones (no `results` key, `null` values inside the daily arrays, arrays of different lengths). Also how the marine data is merged: coastal, inland, a failed marine request, and cancellation.
- Presentation: the view model state machines against stub repositories. That covers debounce, latest query wins over a slower earlier one, retry, and a failed refresh keeping the existing content.

The SwiftUI views aren't tested. They're mostly a `switch` over state. Snapshot tests would be the right tool, but I didn't want to add a dependency for them.


## API usage

All three endpoints are public and need no key.

Geocoding: `GET https://geocoding-api.open-meteo.com/v1/search?name=…&count=10&language=en&format=json`. When nothing matches, the response has no `results` key at all, rather than an empty array, so the DTO treats it as optional. I don't send queries shorter than 2 characters, because they don't return anything useful.

Forecast: `GET https://api.open-meteo.com/v1/forecast` with `daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,snowfall_sum,precipitation_probability_max,wind_speed_10m_max,snow_depth_max`, `forecast_days=7`, `timezone=auto`, and units fixed to °C, km/h and mm.

Marine: `GET https://marine-api.open-meteo.com/v1/marine?daily=wave_height_max` for the same coordinate, window and time zone. It's the one API beyond the two in the brief, and it's what tells a coastal city from an inland one; without it, surfing came out top in Denver. For an inland point it returns every value as `null`, which is how I tell coastal from inland. I checked about fifteen cities against the live API before relying on that. It's sent at the same time as the forecast request. If it fails, the forecast still loads, surfing falls back to a wind-based estimate, and the screen says so.

`timezone=auto` matters. Days come back in the city's own time zone, so "Tuesday" in Tokyo really is Tokyo's Tuesday, and all the dates in the UI are formatted in that zone.

The daily values are parallel arrays, and any entry can be `null`. A missing required field drops the day, and a missing optional field is left out of the score rather than guessed. Date, max/min temperature and weather code are required. Everything else is optional. Defaulting a missing value to 0 would mean "definitely dry, no wind", which pushes outdoor scores up exactly when the data is thinnest. If no days survive, the user sees a "no forecast" error. If the forecast arrays have different lengths, I treat the response as invalid.

## How activities are ranked

Every activity gets a score from 0 to 100 for each day. It happens in two stages.

First come the hard requirements. If one fails, the score is 0 and nothing else is looked at. A plain weighted sum isn't enough on its own: factors that have nothing to do with the activity still add points, which put surfing top in Denver and kept skiing above 30 on a hot day. The gates are:

- Skiing: at least 5 cm of snow on the ground, or at least 1 cm falling that day.
- Surfing: the sea (marine data isn't all null), waves of at least 0.3 m, a max temperature of at least 5 °C, and no likely thunderstorm.

Then come the weights. Each factor is between 0 and 1. Most are built from two small helpers. One gives 1.0 inside an ideal range and falls off linearly outside it. The other is a ratio that saturates at a cap.

- Skiing: cold max temperature (−15 to 2 °C ideal) 30%, snow base up to 0.5 m 25%, fresh snow up to 10 cm 20%, no rain 10%, wind up to 25 km/h 15%.
- Surfing: wave height (1 to 2.5 m ideal) 45%, light wind 20%, max temperature 18–30 °C 20%, low rain chance 15%. If wave data couldn't be fetched, a wind-based estimate stands in for wave height (12–35 km/h ideal, since a breeze builds swell and a gale blows it out), weighted with temperature and rain chance, and the screen says the score is estimated.
- Outdoor sightseeing: max temperature 15–26 °C 40%, low rain chance 30%, light wind 15%, sky 15% (clear is best, thunderstorm worst).
- Indoor sightseeing: this is the fallback, so it works differently. It starts at 50 and rises with how bad the weather is (the worst of rain chance, temperature, wind and sky), scaled by how poor the best other activity is that day. The second part stops a cold powder day from ranking the museum above skiing just because of the cold.

One more detail: Open-Meteo's daily weather code is the worst hour of the day, so a short evening storm marks the whole day as a thunderstorm. A storm code only counts when the rain chance is 50% or more, or unknown. Otherwise it's treated as showers.

An activity's weekly score is the average of its seven daily scores. Ties are broken by a fixed activity order, so the list doesn't reshuffle between refreshes. The best day is the highest-scoring one, and if two days tie, the earlier one wins.

Here's what the live API gave on 14 October 2026. Sydney had 1.1–1.5 m waves and 17–23 °C: surfing 90, outdoor 71, indoor 54, skiing 0. Denver was inland with no snow: outdoor 83, indoor 56, skiing 0, surfing 0. Valle Nevado in Chile had 2.4 m of snow: skiing 83, indoor 57, outdoor 35, surfing 0.

## Assumptions

- "Next 7 days" means today plus six more days, in the city's local time.
- Daily data is enough. Hourly data would allow "surf in the morning, museum in the afternoon", but that's more than the brief asked for.
- Snow depth is read at the city's own grid cell. A valley town under a ski area (Innsbruck, Queenstown) scores 0 for skiing when there's no snow in town. I considered using the geocoding elevation instead, but snow depth answers the real question directly.
- The marine model covers big lakes too, so Chicago and Toronto get waves. People do surf there, so I left it.
- Wave height from the Marine API is the surf signal. Wind is only the fallback, used when the marine request fails or a day has no wave value, and it's a rough estimate.
- A thunderstorm code with a rain chance under 50% is a passing storm and is scored as showers. At 50% or more, or when the chance is missing, it rules surfing out.
- Wave height is the only marine signal. Swell period and wind direction (offshore vs onshore) would make surfing more accurate.
- The thresholds are my own reasonable guesses, not calibrated against anything.
- Region plus country is enough to tell the search results apart (London, England vs London, Ontario).

## Trade-offs and what's missing

Averaging over the week hides a single great day. One powder day in seven grey ones ranks skiing low, even though "go on Thursday" is the useful answer. The best day is shown on each row partly for that reason. Ranking by the best few days is the obvious alternative.

A score of 0 from a gate looks the same as a genuinely bad 0. "Surfing · 0 · Poor" in Denver would be better shown as "not possible here", with the reason.

Not done:

- offline cache
- snapshot and UI tests
- localisation (the copy is English only)
- logging

Pull-to-refresh is the only way to refresh. Dark mode works because only system colours are used.

## Time spent

About 4 hours on the first version that met the brief: architecture, the Open-Meteo client, the scoring, both screens and tests. About 6 hours more after reviewing it: hard requirements for skiing and surfing, the Marine API, `nil` instead of 0 for missing values, and Swift Testing scenarios. The second part fixed real ranking bugs (surfing ranked first in Denver), so I kept it rather than ship the four-hour version.

## Production readiness

Before shipping this for real, I'd add:

- logging with `os.Logger` and crash reporting
- a cached repository wrapped around the existing protocol, with a "last updated" label
- retry with backoff for 5xx and offline, but not for 4xx
- a string catalog
- an accessibility pass at the largest text sizes
- a privacy manifest

## Cross-platform

The same layout maps directly onto Android: a pure Kotlin `:domain` module, a `:data` module with Retrofit or Ktor, and ViewModels exposing `StateFlow` of a sealed `LoadState`, with Compose on top. If the two apps needed to share code, the domain module is the obvious candidate for Kotlin Multiplatform, since it's just value types and arithmetic. I wouldn't share the presentation layer.

## AI usage

I used Claude Code throughout, for boilerplate and as a reviewer. The scoring gates, the Marine API fallback and the indoor-vs-best-alternative rule were worked out together in a review session after the first version let surfing rank first in Denver; I then verified every rule by hand and against the live Open-Meteo APIs (see API usage), and the test suite — including a mutation check on the gates — passes in both swift test and Xcode.
