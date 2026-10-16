# Forecast Activities

An iOS app where you search for a city and get skiing, surfing, outdoor sightseeing and indoor sightseeing ranked for the next 7 days, based on the Open-Meteo forecast.

## Overview

Two screens. City search queries the Open-Meteo geocoding API as you type, with a short debounce. Tapping a result opens the ranking screen, which fetches the 7-day forecast and wave forecast, scores each activity per day, and lists them best first with the raw forecast underneath so you can see why. Pull to refresh; if it fails the old results stay.

The UI is plain SwiftUI. The brief said architecture, correctness and testing mattered more than polish, so that's where the time went.

## Platform and tooling

- iOS 17+, SwiftUI, Swift 6 language mode with strict concurrency.
- `@Observable` view models and async/await throughout. No Combine: task cancellation made "latest search wins" simple.
- Constructor injection through protocols, wired by hand in `AppContainer`. Three dependencies don't need a framework.
- XCTest, plus Swift Testing for the table-style tests (WMO codes, score bands, error mapping, city scenarios) where `@Test(arguments:)` reports each row separately.
- No third-party dependencies. The Xcode project is generated from `project.yml` with XcodeGen and committed, so you don't need XcodeGen to build.

## Architecture

Everything that isn't a view lives in a local Swift package, `Packages/ActivityKit`, split into three targets:

- `ActivityDomain`: models, repository protocols, the scoring rules and the ranking use case. No networking, no UI.
- `ActivityData`: the Open-Meteo client, DTOs, mapping to domain models, and the repository implementations.
- `ActivityPresentation`: the two view models and `LoadState`.

Presentation and Data both depend on Domain and not on each other; the package manifest enforces it, so a view model can't import a DTO by accident. The app target holds the views and `AppContainer`, where the concrete types are wired together.

Each screen's state is a `LoadState` enum (`idle`, `loading`, `loaded`, `failed`) the views switch over. The ranking screen keeps a separate `refreshError` so a failed pull-to-refresh shows a notice without discarding good content.

Network failures (URLError, HTTP status, decoding) become one `AppError` type, mapped in one place. 4xx, 5xx and timeouts are separate cases: a 4xx won't succeed on retry, so there's no "Try again" button; a 5xx or a timeout usually will. User-facing wording lives in the presentation layer.

Each scoring rule conforms to `ActivityScoring`, a pure function from one day's weather to a score. `IndoorSightseeingScorer` is the exception: as the fallback, it's scored against the best other activity that day rather than on the weather alone. That couples it to the other rules, so `RankActivitiesUseCase` scores it last, once the others are known.

## Building and running

You need Xcode 16 or later and no API keys. Open `ForecastActivities.xcodeproj`, pick an iPhone simulator and run. If you change `project.yml`, regenerate the project with `xcodegen generate` (or `make project`).

## Tests

`make test` (or `swift test` in `Packages/ActivityKit`) runs on macOS in about a second, no simulator needed. ⌘U in Xcode or `make test-xcode` runs the same tests on an iPhone simulator. CI runs both. There are 94 XCTest tests plus 13 Swift Testing tests that expand to 84 cases:

- Domain: the curve helpers, each activity's scoring rules and gates, the ranking (sort order, tie-breaks, averaging, best day), and city scenarios (Denver in June, Toronto in January, Valle Nevado with snow, Sydney with swell and so on) that check what ranks first and what's ruled out.
- Data: request building; error mapping for status codes, timeouts, offline and bad JSON; real-shaped Open-Meteo payloads, including the awkward ones (no `results` key, `null` values inside the daily arrays, arrays of different lengths); and how marine data is merged (coastal, inland, a failed marine request, cancellation).
- Presentation: the view model state machines against stub repositories: debounce, latest query winning over a slower earlier one, retry, and a failed refresh keeping existing content.

The SwiftUI views aren't tested; they're mostly a `switch` over state, and snapshot tests would mean adding a dependency.

## API usage

All three endpoints are public and need no key.

Geocoding: `GET https://geocoding-api.open-meteo.com/v1/search?name=…&count=10&language=en&format=json`. With no match the response has no `results` key at all, so the DTO treats it as optional. Queries under 2 characters aren't sent.

Forecast: `GET https://api.open-meteo.com/v1/forecast` with `daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,snowfall_sum,precipitation_probability_max,wind_speed_10m_max,snow_depth_max`, `forecast_days=7`, `timezone=auto`, units fixed to °C, km/h and mm. `timezone=auto` means days arrive in the city's own zone, so Tuesday in Tokyo is Tokyo's Tuesday, and the UI formats dates in that zone.

Marine: `GET https://marine-api.open-meteo.com/v1/marine?daily=wave_height_max`, same coordinate and window, fetched in parallel with the forecast. It's the one API beyond the brief; without it surfing came out top in Denver. An inland point returns every value as `null`, which is how coastal is told from inland (checked against about fifteen cities). If the request fails the forecast still loads, surfing falls back to a wind estimate, and the screen says so.

Daily values are parallel arrays and any entry can be `null`. Date, max/min temperature and weather code are required; a day missing one is dropped. Other missing fields are left out of the score rather than defaulted to 0, which would mean "definitely dry, no wind" exactly when the data is thinnest. No surviving days is a "no forecast" error; arrays of different lengths are an invalid response.

## How activities are ranked

Every activity gets a 0–100 score per day, in two stages.

First, hard requirements. If one fails the score is 0 and nothing else is looked at. A weighted sum alone let unrelated factors add points, which put surfing top in Denver and kept skiing above 30 on a hot day.

- Skiing: at least 5 cm of snow on the ground, or at least 1 cm falling that day.
- Surfing: the sea (marine data isn't all null), waves of at least 0.3 m, a max temperature of at least 5 °C, and no likely thunderstorm.

Then the weights. Each factor is 0…1, built from one of two helpers: 1.0 inside an ideal range falling linearly outside it, or a ratio that saturates at a cap.

- Skiing: cold max temperature (−15 to 2 °C ideal) 30%, snow base up to 0.5 m 25%, fresh snow up to 10 cm 20%, no rain 10%, wind up to 25 km/h 15%.
- Surfing: wave height (1 to 2.5 m ideal) 45%, light wind 20%, max temperature 18–30 °C 20%, low rain chance 15%. If wave data couldn't be fetched, a wind-based estimate stands in for wave height (12–35 km/h ideal, since a breeze builds swell and a gale blows it out), weighted with temperature and rain chance, and the screen says the score is estimated.
- Outdoor sightseeing: max temperature 15–26 °C 40%, low rain chance 30%, light wind 15%, sky 15% (clear is best, thunderstorm worst).
- Indoor sightseeing: the fallback. It starts at 50 and rises with how bad the weather is (the worst of rain chance, temperature, wind and sky), scaled by how poor the best other activity is that day. The second part stops a −5 °C powder day from ranking the museum above excellent skiing just because of the cold.

Open-Meteo's daily weather code is the worst hour of the day, so one evening storm marks the whole day. A storm code only counts when the rain chance is 50% or more (or unknown); otherwise it's scored as showers.

The weekly score is the mean of the seven days. Ties are broken by a fixed activity order so the list doesn't reshuffle between refreshes. The best day is the highest-scoring; on a tie, the earlier one.

On 14 October 2026 the live API gave: Sydney (1.1–1.5 m waves, 17–23 °C) surfing 90, outdoor 71, indoor 54, skiing 0. Denver (inland, no snow) outdoor 83, indoor 56, skiing 0, surfing 0. Valle Nevado in Chile (2.4 m of snow) skiing 83, indoor 57, outdoor 35, surfing 0.

## Assumptions

- "Next 7 days" means today plus six, in the city's local time, at daily granularity.
- Snow depth is read at the city's own grid cell, so a valley town under a ski area (Innsbruck, Queenstown) scores 0 for skiing when there's no snow in town.
- The marine model covers big lakes, so Chicago and Toronto get waves. People do surf there.
- Wave height is the only marine signal; swell period and wind direction would make surfing more accurate. Wind is only a rough fallback.
- The thresholds are reasonable guesses, not calibrated against anything.

## Trade-offs and what's missing

Averaging over the week hides a single great day: one powder day in seven grey ones ranks skiing low, even though "go on Thursday" is the useful answer. That's partly why each row shows the best day.

A 0 from a gate looks the same as a genuinely bad 0. "Surfing · 0 · Poor" in Denver would be better shown as "not possible here".

Not done: an offline cache, snapshot and UI tests, localisation (the copy is English only) and logging. Dark mode works because only system colours are used.

## Time spent

About 4 hours on the first version that met the brief: architecture, the Open-Meteo client, the scoring, both screens and tests. About 6 hours more after reviewing it: hard requirements for skiing and surfing, the Marine API, `nil` instead of 0 for missing values, and Swift Testing scenarios. That second part fixed real ranking bugs, so I kept it rather than ship the four-hour version.

## Production readiness

Before shipping: `os.Logger` and crash reporting; a cached repository behind the existing protocol with a "last updated" label; retry with backoff for the errors already marked retryable; a string catalog; an accessibility pass at the largest text sizes; a privacy manifest.

## Cross-platform

The same layout maps onto Android: a pure Kotlin `:domain` module, a `:data` module with Retrofit or Ktor, ViewModels exposing a `StateFlow` of a sealed `LoadState`, Compose on top. If the apps had to share code, the domain module is the Kotlin Multiplatform candidate, being value types and arithmetic. I wouldn't share presentation.

## AI usage

I used Claude Code throughout, for boilerplate and as a reviewer. The scoring gates, the Marine API fallback and the indoor-vs-best-alternative rule were worked out together in a review session after the first version let surfing rank first in Denver. I then verified every rule by hand and against the live Open-Meteo APIs (see API usage), and the test suite, including a mutation check on the gates, passes in both swift test and Xcode.
