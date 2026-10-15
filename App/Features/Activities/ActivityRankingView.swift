import ActivityDomain
import ActivityPresentation
import SwiftUI

/// Shows the ranked activities for a city over the next 7 days, plus the raw forecast.
struct ActivityRankingView: View {
    @State private var viewModel: ActivityRankingViewModel

    init(viewModel: ActivityRankingViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        content
            .navigationTitle(viewModel.city.name)
            .navigationBarTitleDisplayMode(.large)
            .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("Checking the forecast…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loaded(let ranking):
            RankingList(ranking: ranking, refreshError: viewModel.refreshError)
                .refreshable { await viewModel.refresh() }

        case .failed(let error):
            ErrorView(error: error) {
                Task { await viewModel.retry() }
            }
        }
    }
}

private struct RankingList: View {
    let ranking: ActivityRanking
    let refreshError: AppError?

    private var timeZone: TimeZone { ranking.forecast.timeZone }

    var body: some View {
        List {
            if let refreshError {
                Section {
                    Label(refreshError.userMessage, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach(Array(ranking.recommendations.enumerated()), id: \.element.id) { index, recommendation in
                    ActivityRow(rank: index + 1, recommendation: recommendation, timeZone: timeZone)
                }
            } header: {
                Text("Best activities · \(Formatting.dateRange(ranking.forecast.days.map(\.date), in: timeZone))")
            } footer: {
                Text("Scores are 0–100 and based on temperature, precipitation, wind and sky conditions. Indoor sightseeing never drops below 50 — it is always a reasonable fallback.")
            }

            Section("7-day forecast") {
                ForEach(ranking.forecast.days) { day in
                    DayForecastRow(day: day, timeZone: timeZone)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

/// One ranked activity: title, overall score, and a strip of seven daily scores.
private struct ActivityRow: View {
    let rank: Int
    let recommendation: ActivityRecommendation
    let timeZone: TimeZone

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: recommendation.activity.symbolName)
                    .font(.title2)
                    .frame(width: 32)
                    .foregroundStyle(recommendation.overallScore.tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(rank). \(recommendation.activity.displayName)")
                        .font(.headline)
                    if let bestDay = recommendation.bestDay {
                        Text("Best day: \(Formatting.shortDay(bestDay.date, in: timeZone)) (\(bestDay.score.value))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                ScoreBadge(score: recommendation.overallScore)
            }

            // Purely decorative: the badge already states the number and the band.
            ProgressView(value: Double(recommendation.overallScore.value), total: 100)
                .tint(recommendation.overallScore.tint)
                .accessibilityHidden(true)

            HStack(spacing: 6) {
                ForEach(recommendation.dailyScores) { daily in
                    DayScoreChip(daily: daily, timeZone: timeZone)
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = ["Rank \(rank). \(recommendation.activity.displayName). Overall score \(recommendation.overallScore.value), \(recommendation.overallScore.band.label)."]
        if let bestDay = recommendation.bestDay {
            parts.append("Best day \(Formatting.longDay(bestDay.date, in: timeZone)).")
        }
        return parts.joined(separator: " ")
    }
}

private struct ScoreBadge: View {
    let score: Score

    var body: some View {
        VStack(spacing: 0) {
            Text("\(score.value)")
                .font(.title3.weight(.bold).monospacedDigit())
            Text(score.band.label)
                .font(.caption2)
        }
        .foregroundStyle(score.tint)
        .frame(minWidth: 56)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Score \(score.value) out of 100, \(score.band.label)")
    }
}

/// A compact per-day score: weekday initial over the number, coloured by band.
private struct DayScoreChip: View {
    let daily: DailyScore
    let timeZone: TimeZone

    var body: some View {
        VStack(spacing: 2) {
            Text(weekdayInitial)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(daily.score.value)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(daily.score.tint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(daily.score.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityHidden(true) // The row's combined label already summarises the week.
    }

    private var weekdayInitial: String {
        daily.date.formatted(Date.FormatStyle(timeZone: timeZone).weekday(.narrow))
    }
}

/// One day of raw forecast, so the user can sanity-check the ranking.
private struct DayForecastRow: View {
    let day: DailyWeather
    let timeZone: TimeZone

    /// At accessibility text sizes a four-column row no longer fits, so the layout flips
    /// to vertical rather than truncating.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 12))

        layout {
            Text(Formatting.shortDay(day.date, in: timeZone))
                .font(.subheadline.weight(.medium))
                .frame(minWidth: 56, alignment: .leading)

            Image(systemName: day.condition.symbolName)
                .symbolRenderingMode(.multicolor)
                .frame(minWidth: 28)
                .accessibilityLabel(day.condition.label)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(Formatting.temperature(day.maxTemperatureC)) / \(Formatting.temperature(day.minTemperatureC))")
                    .font(.subheadline.monospacedDigit())
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "Rain 20% · Wind 14 km/h · Snow 5 cm". Missing values show as "–".
    private var details: String {
        var parts = [
            "Rain \(day.precipitationProbability.map { "\($0)%" } ?? "–")",
            "Wind \(day.maxWindSpeedKmh.map { "\(Int($0.rounded())) km/h" } ?? "–")",
        ]
        if let snowfall = day.snowfallCM, snowfall > 0 {
            parts.append("Snow \(Int(snowfall.rounded())) cm")
        }
        return parts.joined(separator: " · ")
    }
}
