# Forecast Activities

An iOS app where you search for a city and get skiing, surfing, outdoor sightseeing and indoor sightseeing ranked for the next 7 days, based on the Open-Meteo forecast.

## Overview

There are two screens. The first is a city search that hits the Open-Meteo geocoding API as you type, with a short debounce. Tap a result and you get the ranking screen. It fetches a 7-day daily forecast, scores each activity for each day, and lists the activities best first. Each row shows the overall score, the best day and a small strip of daily scores. The raw forecast is underneath so you can see why something ranked where it did. Pull to refresh is supported, and if a refresh fails the old results stay on screen.

The UI is plain SwiftUI. The brief said architecture, correctness and testing mattered more than polish, so that's where I spent the time.

## Platform and tooling

- iOS 17+, SwiftUI, Swift 6 language mode with strict concurrency on.
- `@Observable` view models, async/await for everything async. I didn't use Combine because cancellation with tasks made "latest search wins" simple.
- Protocol-based constructor injection, wired up by hand in `AppContainer`. With three dependencies, a DI framework would be overkill.
- XCTest for most tests. Swift Testing for the table-style ones (WMO codes, score bands, error mapping), where `@Test(arguments:)` reports each row separately.
- No third-party dependencies.
- The Xcode project is generated with XcodeGen from `project.yml`. The generated project is committed, so you don't need XcodeGen to build.

## Architecture

Everything that isn't a view lives in a local Swift package, `Packages/ActivityKit`, split into three targets:

- `ActivityDomain`: models, repository protocols, the scoring rules and the ranking use case. No networking, no UI.
- `ActivityData`: the Open-Meteo client, DTOs, mapping to domain models, and the repository implementations.
- `ActivityPresentation`: the two view models and `LoadState`.

Presentation and Data both depend on Domain, and neither knows about the other. The package manifest enforces that, so a view model can't import a DTO even by accident. The app target holds the SwiftUI views and `AppContainer`, which is the only place the concrete types are wired together.

Each screen's state is a `LoadState` enum (`idle`, `loading`, `loaded`, `failed`), and the views switch over it. The ranking screen also has a separate `refreshError`, so a failed pull-to-refresh can show a small notice without throwing away good content.

Errors from the network layer (URLError, HTTP status, decoding) are mapped to a single `AppError` type in one place. View models only ever see that type. The user-facing wording lives in the presentation layer.

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

`make test` does the same. The tests run on macOS without a simulator and take about a second. The same tests also run from the app scheme: press ⌘U in Xcode, or run `make test-xcode` to use the first available iPhone simulator. CI runs both on every push to `main` and on pull requests. There are 70 XCTest tests, plus 9 Swift Testing tests that expand to 68 parameterised cases:

- Domain: the curve helpers, each activity's scoring rules, and the ranking (sort order, tie-breaks, averaging, best day).
- Data: request building, error mapping for status codes, timeouts, offline and bad JSON, and mapping real-shaped Open-Meteo payloads, including the awkward ones (no `results` key, `null` values inside the daily arrays, arrays of different lengths).
- Presentation: the view model state machines against stub repositories. That covers debounce, latest query wins over a slower earlier one, retry, and a failed refresh keeping the existing content.

The SwiftUI views aren't tested. They're mostly a `switch` over state. Snapshot tests would be the right tool, but I didn't want to add a dependency for them.

One thing that caught me out: XcodeGen only accepts package test targets in a scheme written as `- package: ActivityKit/ActivityDomainTests`. The plain `ActivityKit/ActivityDomainTests` form fails with "invalid project reference".

## API usage

Both endpoints are public and need no key.

Geocoding: `GET https://geocoding-api.open-meteo.com/v1/search?name=…&count=10&language=en&format=json`. When nothing matches, the response has no `results` key at all, rather than an empty array, so the DTO treats it as optional. I don't send queries shorter than 2 characters, because they don't return anything useful.

Forecast: `GET https://api.open-meteo.com/v1/forecast` with `daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,snowfall_sum,precipitation_probability_max,wind_speed_10m_max`, `forecast_days=7`, `timezone=auto`, and units fixed to °C, km/h and mm.

`timezone=auto` matters. Days come back in the city's own time zone, so "Tuesday" in Tokyo really is Tokyo's Tuesday, and all the dates in the UI are formatted in that zone.

The daily values are parallel arrays, and any entry can be `null`. My rule: if a day is missing its date, max/min temperature or weather code, I drop it. If precipitation, snowfall, rain probability or wind is missing, I treat it as 0. If no days survive, the user sees a "no forecast" error. If the arrays have different lengths, I treat the response as invalid.

## How activities are ranked

Every activity gets a score from 0 to 100 for each day. Most of the factors are built from two small helpers. One gives 1.0 inside an ideal range and falls off linearly outside it. The other is a ratio that saturates at a cap. The factors are then combined using fixed weights:

- Skiing: cold max temperature (−15 to 2 °C ideal) 45%, fresh snowfall up to 10 cm 25%, no rain 15%, wind up to 25 km/h 15%.
- Surfing: max temperature 18–30 °C 35%, wind 12–35 km/h 35% (wind stands in for swell), low rain chance 30%. Any thunderstorm day scores 0.
- Outdoor sightseeing: max temperature 15–26 °C 40%, low rain chance 30%, light wind 15%, sky condition 15% (clear is best, thunderstorm worst).
- Indoor sightseeing: starts at 50 and climbs towards 100 based on whichever is worst outside: rain chance, temperature, wind or sky. It's the fallback, so it never drops below 50.

An activity's weekly score is the average of its seven daily scores. Ties are broken by a fixed activity order, so the list doesn't reshuffle between refreshes. The best day is the highest-scoring one, and if two days tie, the earlier one wins.

As an example, take a 21 °C clear day with a 5% rain chance and 8 km/h wind. That scores outdoor 99, surfing 93, indoor 53 and skiing 30.

## Assumptions

- "Next 7 days" means today plus six more days, in the city's local time.
- Daily data is enough. Hourly data would allow "surf in the morning, museum in the afternoon", but that's more than the brief asked for.
- The forecast API has no snow depth or resort data, so skiing is judged on temperature and fresh snow only.
- There's no wave data in the forecast API, so surfing uses wind as a rough proxy, and nothing checks whether the city is on the coast.
- The thresholds are my own reasonable guesses, not calibrated against anything.
- Region plus country is enough to tell the search results apart (London, England vs London, Ontario).

## Trade-offs and what's missing

Some of the ranking limitations show up quickly in practice. An inland city on a warm, breezy day can rank surfing first. Skiing never scores below about 30, because the "no rain" and "light wind" factors still count on a warm day. Open-Meteo's daily weather code is the worst weather of the day, so a short storm marks the whole day as a thunderstorm. Averaging over the week also hides a single great day. The plan is to give each activity hard requirements (sea for surfing, snow or cold for skiing) that zero the score before the weighting, and to use the Open-Meteo Marine API to tell coastal from inland.

Not done:

- offline cache
- snapshot and UI tests
- localisation (the copy is English only)
- logging

Pull-to-refresh is the only way to refresh. Dark mode works because only system colours are used.

## Production readiness

Before shipping this for real, I'd add:

- logging with `os.Logger` and crash reporting
- a cached repository wrapped around the existing protocol, with a "last updated" label
- retry with backoff for 5xx and offline, but not for 4xx
- a string catalog
- an accessibility pass at the largest text sizes
- a privacy manifest
- tests running in CI on every PR

## Cross-platform

The same layout maps directly onto Android: a pure Kotlin `:domain` module, a `:data` module with Retrofit or Ktor, and ViewModels exposing `StateFlow` of a sealed `LoadState`, with Compose on top. If the two apps needed to share code, the domain module is the obvious candidate for Kotlin Multiplatform, since it's just value types and arithmetic. I wouldn't share the presentation layer.

## AI usage

I used Claude while building this, mainly for boilerplate (DTOs, test fixtures, the XcodeGen spec), for help with Swift 6 concurrency errors, and as a reviewer. The architecture, the scoring rules and the error-handling approach are my own choices, and I've read and edited everything in the repo. The package tests pass with `swift test`, and the app builds and runs on the simulator.
