# Forecast Activities

A native iOS app that lets you search for a city and see which of four activities — **skiing, surfing, outdoor sightseeing, indoor sightseeing** — best suit its weather over the next seven days, using the Open-Meteo Geocoding and Forecast APIs.

> **Reviewer quick start:** `open ForecastActivities.xcodeproj`, pick an iPhone simulator, ⌘R. Run the tests with ⌘U, or `cd Packages/ActivityKit && swift test` (no simulator needed, ~10 s).

---

## Contents

1. [Project overview](#1-project-overview)
2. [Platform and tooling choices](#2-platform-and-tooling-choices)
3. [Architecture and technical decisions](#3-architecture-and-technical-decisions)
4. [How to build and run](#4-how-to-build-and-run)
5. [How to run tests & testing strategy](#5-how-to-run-tests--testing-strategy)
6. [API usage notes](#6-api-usage-notes)
7. [Activity recommendation logic](#7-activity-recommendation-logic)
8. [Assumptions](#8-assumptions)
9. [Trade-offs and omissions](#9-trade-offs-and-omissions)
10. [Production-readiness notes](#10-production-readiness-notes)
11. [Cross-platform delivery notes](#11-cross-platform-delivery-notes)
12. [AI usage disclosure](#12-ai-usage-disclosure)

---

## 1. Project overview

Two screens:

| Screen | What it does |
|---|---|
| **City search** | Debounced free-text search against the Open-Meteo Geocoding API. Explicit idle / loading / results / empty / error states. |
| **Activity ranking** | Fetches a 7-day daily forecast, scores each activity for each day with pure domain rules, and shows the activities ranked best-first with a per-day score strip, the best day, and the raw forecast underneath so the ranking can be sanity-checked. Pull-to-refresh keeps stale content if the refresh fails. |

The brief said architecture, maintainability, correctness, testing and communication matter more than polish or feature count, so that is where the ~4 hours went. The scoring rules are deterministic, documented and tested; the UI is deliberately plain SwiftUI.

## 2. Platform and tooling choices

| Choice | Why |
|---|---|
| **iOS 17+, Swift 6 language mode, strict concurrency** | Lets me use `@Observable`, `ContentUnavailableView` and `Duration`-based sleeps, and have the compiler prove there are no data races. Swift 6 mode is on for the package and the app. |
| **SwiftUI + `@Observable`** (not `ObservableObject`) | Views re-render only for the properties they read; no `@Published`/`objectWillChange` fan-out. |
| **Swift Package (`ActivityKit`) for everything non-UI** | Compiler-enforced layering (see §3), and `swift test` runs on macOS in seconds without a simulator. |
| **Swift concurrency (`async/await`, `Task`, `actor`)** rather than Combine | It is the platform direction; cancellation is built in (which is what makes "latest search wins" trivial); and tests read top-to-bottom. |
| **Protocol-based, constructor dependency injection** | No DI framework: the app is small enough that a composition root (`AppContainer`) wiring three dependencies is clearer than a container library. |
| **XCTest** | Asked for in the brief; works identically in `swift test` and Xcode. |
| **XcodeGen (`project.yml`)** | The `.xcodeproj` is generated from a 50-line readable spec and committed, so reviewers do not need XcodeGen installed, but there are no merge-conflict-prone pbxproj edits in the history. |
| **No third-party dependencies** | Nothing in this brief justifies one. Less to review, nothing to audit, no supply-chain surface. |

## 3. Architecture and technical decisions

### Layering

```
┌────────────────────────── App target (SwiftUI) ──────────────────────────┐
│  ForecastActivitiesApp → AppContainer (composition root)                 │
│  CitySearchView ─ ActivityRankingView ─ ErrorView ─ Formatting           │
└───────────────┬────────────────────────────────────────┬─────────────────┘
                │ reads state / calls methods            │ wires concrete types
┌───────────────▼──────────────┐             ┌───────────▼──────────────────┐
│ ActivityPresentation         │             │ ActivityData                 │
│  LoadState<T>                │             │  HTTPClient (protocol)       │
│  CitySearchViewModel         │             │  URLSessionHTTPClient        │
│  ActivityRankingViewModel    │             │  APIClient (status+decode)   │
│  AppError+Presentation       │             │  OpenMeteoEndpoints          │
└───────────────┬──────────────┘             │  DTOs → OpenMeteoMapper      │
                │ depends on                 │  OpenMeteo*Repository        │
                │                            └───────────┬──────────────────┘
┌───────────────▼────────────────────────────────────────▼─────────────────┐
│ ActivityDomain  (no networking, no UI)                                   │
│  City, Coordinate, DailyWeather, WeatherCondition, Forecast              │
│  Activity, Score, DailyScore, ActivityRecommendation, AppError           │
│  CitySearchRepository / ForecastRepository (protocols)                   │
│  WeatherCurves, ActivityScoring + 4 scorers, RankActivitiesUseCase       │
└──────────────────────────────────────────────────────────────────────────┘
```

Dependencies point **inward only**. `ActivityPresentation` imports `ActivityDomain` but *cannot* import `ActivityData` — the package manifest does not allow it — so a view model can never accidentally reach for `URLSession` or a DTO. The app target is the only module that sees all three, and it sees them only in `AppContainer`.

This is Clean Architecture in spirit, with the ceremony left out: there is one use case (`RankActivitiesUseCase`) because there is one piece of business logic; repositories are protocols in the domain with Open-Meteo implementations in the data layer; view models are MVVM.

### Key decisions

**Explicit state as an enum.** Every screen renders exactly one case of `LoadState<Value>` (`idle | loading | loaded(Value) | failed(AppError)`). Views `switch` over it, so "spinner and stale list and error banner all at once" is unrepresentable. `ActivityRankingViewModel` adds a separate `refreshError` so a failed pull-to-refresh can keep useful content on screen — a deliberate exception, not a leak back into boolean soup.

**One error type crosses the Data → Presentation boundary.** `AppError` (`offline`, `server(status)`, `invalidResponse`, `noForecastAvailable`, `cancelled`, `network(String)`) carries an `isRetryable` flag. The mapping from `URLError`/HTTP status/`DecodingError` happens in one place (`AppErrorMapping`), so the retry/offline semantics are decided once. User-facing copy lives in Presentation, not Domain, because wording is a UI concern.

**Cancellation does the heavy lifting in search.** `CitySearchViewModel` cancels the in-flight `Task` on every keystroke, sleeps for the debounce interval, then calls the repository. A superseded task throws `CancellationError` at its next suspension point and simply exits; it never writes state. There is also a `Task.isCancelled` check after the network call for clients that return normally despite cancellation. Tests cover both the debounce ("5 keystrokes → 1 request") and the race ("slow 'Lon' never overwrites fast 'London'").

**The domain never sees `nil`.** Open-Meteo returns parallel arrays with nullable entries. `OpenMeteoMapper` converts them into one well-formed `DailyWeather` per day (dropping days missing essentials, defaulting the rest to 0 — see §6), so the scoring rules are plain arithmetic with no optional handling.

**Scoring is pure and composable.** Each activity has a `struct` conforming to `ActivityScoring` that turns one `DailyWeather` into a `Score` (0–100) using two tiny curve helpers (`WeatherCurves.comfort`, a trapezoid, and `WeatherCurves.ratio`, a clamped ramp) and a weighted sum. Product can tune one activity without touching the others; tests assert *relative* behaviour ("rain lowers outdoor"; "thunderstorm zeroes surfing") so reasonable weight tuning does not break them.

**Deterministic ranking.** Sorted with two `KeyPathComparator`s — overall score descending, then rule-set position — so ties never reorder between refreshes and the intent is readable without a comparison closure.

**Named thresholds, not magic numbers.** Each scorer declares its ranges and weights in a nested `Rule` enum with a one-line reason per constant (`/// 10 cm of fresh snow is a "powder day"`). The arithmetic reads as prose and product can tune a number without reading the formula.

**Copy stays out of the domain.** `Activity.displayName`, `Score.band` labels and all error wording live in `ActivityPresentation`; the domain only knows identifiers and numbers. Every `Text("…")` literal in SwiftUI is already a `LocalizedStringKey`, so a string catalog drops in without code changes.

**`Sendable` everywhere, no `@unchecked`.** Value types throughout; view models are `@MainActor`; the test HTTP stub is an `actor`; `JSONDecoder`/`DateFormatter` (not `Sendable`) are created per call rather than stored.

## 4. How to build and run

Requirements: **Xcode 16.0+** (Swift 6 toolchain), iOS 17 simulator or device. No accounts, keys or external tools needed.

```bash
git clone <repo>
cd ForecastActivities
open ForecastActivities.xcodeproj      # select an iPhone simulator, ⌘R
```

If you change `project.yml`, regenerate the project with `brew install xcodegen && xcodegen generate` (or `make project`). The package alone can be developed in isolation: `open Packages/ActivityKit/Package.swift`.

## 5. How to run tests & testing strategy

```bash
# Fastest: package tests on macOS, no simulator
cd Packages/ActivityKit && swift test            # or: make test

# Or in Xcode: ⌘U on the ForecastActivities scheme
```

CI (`.github/workflows/ci.yml`) runs `swift test --parallel` and an iOS Simulator build on every push.

### What is tested, and why those things

| Target | Covers | Representative tests |
|---|---|---|
| `ActivityDomainTests` | The curve helpers, every scoring rule, the ranking use case | `comfort` boundaries & linear decay · scores always in 0…100 · skiing: cold+snow ≫ warm · surfing: thunderstorm = 0, breeze > calm > gale · outdoor: ideal day = 100 · indoor: floor of 50, uses the *worst* signal · ranking sorts descending, ties are stable, overall = mean, `bestDay` prefers the earliest tie · production rules rank a rainy week indoor-first and a clear week outdoor-first |
| `ActivityDataTests` | Request building, status/decode/transport error mapping, DTO decoding and domain mapping — all against a scripted `HTTPClient` actor | URLs carry every variable the mapper needs · lat/long are locale-independent · 503 → `.server`, bad JSON → `.invalidResponse`, no connection/timeout → `.offline`, `URLError.cancelled`/`CancellationError` → `.cancelled` · geocoding with no `results` key → `[]` · 7-day fixture maps correctly, dates are local midnight in the location's zone and one day apart · null essentials drop the day, null optionals default to 0 · all-null → `.noForecastAvailable`, ragged arrays → `.invalidResponse` |
| `ActivityPresentationTests` | View model state machines, with closure-driven repository stubs and a polling `waitUntil` helper | search: idle → loading (synchronously) → loaded · <2 chars never hits the network · clear query → idle · failure → `.failed`, `retry()` recovers · **latest query wins** against a slower earlier request · 5 rapid keystrokes → 1 request · ranking: load → sorted recommendations for all 4 activities · failure → `.failed` · `load()` is idempotent once loaded (`.task` re-fires safely) · refresh failure keeps content + sets `refreshError`; next success clears it · `.cancelled` never surfaces |

**Accessibility** is handled in the views rather than tested: every row is a single combined VoiceOver element with a written label (rank, score, band, best day); colour is never the only channel (the badge shows the band name); decorative elements (progress bar, per-day chips) are hidden from VoiceOver because the row label already summarises them; the forecast row switches from horizontal to vertical layout at accessibility Dynamic Type sizes instead of truncating; all type uses semantic text styles. An automated `performAccessibilityAudit()` UI test is listed under production notes.

**Not unit-tested, deliberately:** SwiftUI views. They contain no logic beyond `switch state` and formatting; snapshot tests would be the right tool and are listed under omissions. Formatting helpers are thin wrappers over Foundation's `FormatStyle`.

The test fixtures are real-shaped Open-Meteo payloads kept as string literals (no resource bundling), including the awkward cases the real API produces: a missing `results` key and `null` entries inside daily arrays.

## 6. API usage notes

Both endpoints are public and keyless. Requests are built in `OpenMeteoEndpoints` with `URLComponents` (so query values are percent-encoded correctly — "São Paulo" is tested) and locale-independent number formatting (a comma-decimal device must still send `51.5`).

**Geocoding** — `GET https://geocoding-api.open-meteo.com/v1/search?name={q}&count=10&language=en&format=json`
Queries shorter than 2 characters are short-circuited client-side (the API rejects them). `results` is *absent* rather than empty when nothing matches; the DTO models it as optional and the repository returns `[]`.

**Forecast** — `GET https://api.open-meteo.com/v1/forecast?latitude=…&longitude=…&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,snowfall_sum,precipitation_probability_max,wind_speed_10m_max&timezone=auto&forecast_days=7&wind_speed_unit=kmh&temperature_unit=celsius&precipitation_unit=mm`

- `timezone=auto` returns day boundaries in the *location's* zone and the zone identifier, which the app uses for every date it displays ("Tuesday" in Tokyo is Tokyo's Tuesday).
- `forecast_days=7` → today plus six days.
- Units are pinned explicitly rather than relying on defaults.
- Daily arrays are parallel and nullable. **Policy:** `time`, max/min temperature and `weather_code` are required — a day missing any of them is dropped; precipitation, snowfall, probability and wind default to 0. If no day survives → `AppError.noForecastAvailable`; if arrays are ragged → `AppError.invalidResponse` (broken contract, not missing data).
- `weather_code` (WMO 4677) is collapsed to a `WeatherCondition` bucket (clear / partly cloudy / overcast / fog / drizzle / rain / snow / showers / thunderstorm / unknown(code)). Unknown codes are preserved, not swallowed.

Transport: 15 s timeout, `waitsForConnectivity = false` so an offline device fails fast into the offline state instead of hanging on a spinner.

## 7. Activity recommendation logic

Every activity gets a **0–100 score per day**, from a weighted blend of 0…1 factors. Two helpers build every factor:

- `comfort(value, ideal: a...b, tolerance: t)` — 1.0 inside the ideal range, falling linearly to 0.0 once the value is `t` beyond either edge (a trapezoid).
- `ratio(value, saturatingAt: cap)` — `value / cap` clamped to 0…1 (a ramp).

| Activity | Factors (weight) | Notes |
|---|---|---|
| **Skiing** | cold: `comfort(maxTemp, −15…2 °C, tol 6)` (45) · fresh snow: `ratio(snowfall, 10 cm)` (25) · no rain: 1 − `ratio(precip, 10 mm)` *only if it is rain, i.e. wet and > 1 °C and not snowing* (15) · wind: `comfort(wind, 0…25 km/h, tol 40)` (15) | A cold dry week with no fresh snow caps around 75 — plausible for resort snow on a base. |
| **Surfing** | **thunderstorm ⇒ 0, unconditionally** · air temp: `comfort(maxTemp, 18…30, tol 10)` (35) · wind: `comfort(wind, 12…35 km/h, tol 25)` (35) — a breeze builds swell, a gale blows it out · dry: 1 − P(precip) (30) | Wind is a proxy for swell; see Assumptions. |
| **Outdoor sightseeing** | temp: `comfort(maxTemp, 15…26, tol 10)` (40) · dry: 1 − P(precip) (30) · wind: `comfort(wind, 0…20, tol 30)` (15) · sky factor by condition: clear 1.0, partly cloudy 0.9, overcast 0.6, fog 0.4, drizzle/showers 0.3, snow 0.2, rain 0.1, thunderstorm 0 (15) | |
| **Indoor sightseeing** | `50 + 50 × max(wetness, temperature discomfort, wind discomfort, sky discomfort)` where wetness = P(precip)/100 and each discomfort = 1 − the corresponding comfort | **Floor of 50** — a museum is always a reasonable plan. Uses the *worst* signal, not the average: one strong reason to stay in is enough. |

**Weekly ranking** (`RankActivitiesUseCase`): overall score = mean of the seven daily scores, rounded; activities are sorted by overall score descending, ties broken by rule-set order (stable). Each recommendation also carries all seven daily scores and the best day (earliest on ties — sooner is more useful). An empty forecast yields an empty ranking, not four zeros, so "no data" and "terrible week" stay distinguishable.

Worked example, from the unit tests: a 21 °C clear day with 5 % rain chance and an 8 km/h breeze scores outdoor 99, surfing 93, indoor 53, skiing 30. A 4 °C day with 100 % rain chance and 60 km/h wind scores indoor 100, outdoor ≈ 10.

## 8. Assumptions

1. **"Next 7 days" = today + 6**, in the city's local time zone (`forecast_days=7`, `timezone=auto`).
2. **Daily granularity is sufficient.** Hourly data would allow "morning surf, afternoon museum", but the brief asks for a ranking over days.
3. **Skiing has no snow-depth, elevation or resort data.** The forecast endpoint only provides fresh snowfall, so "cold and dry" scores moderately even in a flat city. A real product would gate skiing on elevation/resort proximity.
4. **Surfing uses wind as a swell proxy.** Wave height/period live in Open-Meteo's separate Marine API; integrating it is out of scope. There is also no "is this city coastal" check.
5. **Scores are opinionated defaults, not calibrated.** Thresholds (e.g. 15–26 °C for sightseeing) are reasonable for a general audience; the structure makes them trivial to tune or personalise.
6. **Indoor sightseeing is a fallback, so it never scores below 50.** A product decision, stated in the UI footer.
7. **Temperatures are shown via `Measurement` + `.weather` usage**, so a device set to a Fahrenheit locale sees °F; scoring always runs in °C.
8. **The geocoding result's first-level admin area (`admin1`) and country are enough** to disambiguate cities in the list (London, England vs London, Ontario).

## 9. Trade-offs and omissions

| Decision | Trade-off |
|---|---|
| **No offline cache** (bonus item) | Would be ~1 hour done properly (a `CachedForecastRepository` decorator over the protocol, keyed by city id with a TTL, plus "last updated" UI). The protocol seam is already there; it was left out to keep the time-box and because stale forecasts can mislead. |
| **No snapshot or UI tests** (bonus items) | Views are logic-free; snapshot tests would need a third-party library (pointfree's `swift-snapshot-testing`) which I did not want to introduce for a take-home. |
| **No localisation / string catalog** | Copy is English-only and inline. A string catalog is the obvious next step; `AppError+Presentation` is already the single place for error copy. |
| **Pull-to-refresh is the only manual refresh**; no auto-refresh or background fetch | Forecasts change slowly; a TTL in the cache decorator above would be the natural home. |
| **Plain visual design** | Per the brief. Dark mode works because only semantic colours are used; there is no custom theming. |
| **Minimal logging** (`AppError.network(String)` carries a diagnostic) | A real app would route through `os.Logger` with privacy annotations and attach a correlation id per request. |
| **Composition root is a struct in the app target, not a DI framework** | Right-sized for three dependencies; if the app grew, factories per feature would be the next step. |
| **No phantom types** (e.g. `Identifier<City>`, `Quantity<Celsius>`) | A newtype is used where it protects an invariant (`Score` clamps to 0–100). Phantom types pay off when many IDs or units can be confused; here there is one ID type and units are fixed by the mapper and named in the field (`maxTemperatureC`). Adding generic tags would be ceremony without a bug class to prevent. |
| **`DayScoreChip`s are `accessibilityHidden`** | The row's combined label already summarises rank, overall score and best day; reading seven numbers aloud per row would be noise. A VoiceOver user who wants the breakdown gets it from the forecast section. |

## 10. Production-readiness notes

What I would add before shipping, roughly in priority order:

1. **Observability**: `os.Logger` + a request correlation id, crash reporting, and analytics on the search → select → ranking funnel. Track `.invalidResponse` rates as an API-contract alarm.
2. **Caching & offline**: the decorator described above; show "last updated" and a staleness hint.
3. **Resilience**: retry with exponential backoff + jitter for `.offline`/5xx (not for 4xx), and a circuit breaker if Open-Meteo degrades.
4. **Rate limiting / etiquette**: Open-Meteo's free tier is fair-use; debounce is in place, caching would cut traffic further.
5. **Localisation & accessibility audit**: string catalog, Dynamic Type at the largest sizes, `performAccessibilityAudit()` in a UI test.
6. **Feature flags** around scoring weights so product can tune without a release.
7. **CI hardening**: snapshot tests, a UI smoke test, code coverage gates, SwiftLint/SwiftFormat.
8. **Privacy manifest** (`PrivacyInfo.xcprivacy`) — currently trivial as no tracking or required-reason APIs are used, but it should be explicit.
9. **Security**: enforce TLS 1.2+ via ATS (default), consider certificate pinning only if the threat model warrants it (it rarely does for public weather data).

## 11. Cross-platform delivery notes

The same architecture ports to Android one-to-one, and the Swift package layout maps onto Gradle modules:

| iOS (this repo) | Android equivalent |
|---|---|
| `ActivityDomain` Swift package target | `:domain` pure-Kotlin module (no Android deps) — the scoring rules translate line-for-line |
| `ActivityData` (`HTTPClient` protocol, `APIClient`, DTOs, mappers) | `:data` with Retrofit/Ktor + kotlinx.serialization, `Repository` interfaces implemented here |
| `ActivityPresentation` (`@Observable @MainActor` VMs, `LoadState`) | `ViewModel` + `StateFlow<LoadState>` (sealed class), `viewModelScope`, `Flow.debounce` for search |
| SwiftUI views switching on `LoadState` | Jetpack Compose `when (state)` |
| `AppContainer` composition root | Hilt modules (or manual DI for this size) |
| `swift test` on macOS | JVM unit tests with JUnit + MockK + Turbine |

If the two apps had to share logic, the domain module is the candidate for **Kotlin Multiplatform**: it is pure value types and arithmetic with no platform dependencies, which is exactly the shape KMP handles well. I would *not* share the presentation layer — platform-native state/lifecycle handling is worth the duplication.

## 12. AI usage disclosure

I used an AI coding assistant (Anthropic's Claude) during this exercise in the same way I use it day-to-day: to accelerate boilerplate (DTOs, test fixtures, the XcodeGen spec, README scaffolding) and as a reviewer for Swift 6 strict-concurrency issues. The architecture, layering, scoring design, error-handling policy and the test plan are my decisions, and every file was read, edited and verified by me:

- the full test suite passes locally (`swift test`, and ⌘U in Xcode);
- the app was run on a simulator against the live APIs for several cities (London, Zermatt, Sydney, a no-result query, airplane mode);
- the worked scoring examples in §7 were checked by hand against the formulas.

"AI usage is allowed. Poor verification is not." — agreed, which is why the verification above is the part I would stand behind in a code review.
