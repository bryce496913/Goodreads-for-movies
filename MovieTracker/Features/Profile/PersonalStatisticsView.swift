import Charts
import SwiftUI

struct PersonalStatisticsView: View {
    @State private var model = PersonalStatisticsModel()
    @Environment(LibraryStore.self) private var library
    @Environment(\.timeZone) private var timeZone
    @Environment(\.locale) private var locale

    private var source: PersonalStatisticsModel.Source {
        .init(revision: library.revision, invalidation: library.metadataInvalidation, year: model.year,
              timeZone: timeZone, referenceDate: library.metadataReferenceDate)
    }
    var body: some View {
        let source = self.source
        List {
            Section {
                Text("Your year in viewing").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Text("Private statistics from this device. Diary watches, ratings and episode marking actions stay distinct.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Picker("Year", selection: $model.year) {
                    ForEach(model.snapshot?.years ?? [model.year], id: \.self) { Text(String($0)).tag($0) }
                }.pickerStyle(.menu).accessibilityIdentifier("statistics.year")
            }
            if let error = library.loadError { AppErrorMessage(message: error.localizedDescription) }
            else if model.isReady(for: source), let snapshot = model.snapshot {
                summary(snapshot)
                monthly(snapshot)
                ratings(snapshot)
                genres(snapshot)
                episodes(snapshot)
                Section("Date Coverage") {
                    Text("\(snapshot.undatedEvents) undated diary events across all years are excluded from annual totals. Recording a watch today does not move an old watch into this year.")
                    if snapshot.excludedEvents > 0 { Text("\(snapshot.excludedEvents) diary records have future, invalid dates or unavailable media identity and are excluded.") }
                    Text("Diary dates use their saved Gregorian calendar day. Episode marking timestamps use \(timeZone.identifier). Future dates are excluded. Status-only Watched titles do not invent dated watches.")
                }.font(.footnote)
            } else if let error = model.errorMessage { AppErrorMessage(message: error) }
            else { AppLoadingState(title: "Preparing viewing statistics…") }
        }
        .appListScreen("Year in Review")
        .accessibilityIdentifier("screen.statistics")
        .onChange(of: library.metadataReferenceDate) { _, date in model.expireMetadata(at: date) }
        .task(id: source) {
            guard library.loadError == nil, !model.isReady(for: source) else { return }
            await model.refresh(PersonalStatisticsInput.capture(library), source: source, now: max(source.referenceDate, Date.now))
        }
    }

    @ViewBuilder private func summary(_ value: PersonalStatisticsSnapshot) -> some View {
        Section("\(String(value.year)) Summary") {
            if value.movieEvents + value.seriesEvents + value.episodeMarks == 0 {
                EmptyStateCard(title: "No dated activity this year", systemImage: "chart.bar",
                    message: "Log a dated watch from a title’s detail page, or choose a different year. Undated watches remain in your diary.", presentation: .inline)
                    .accessibilityIdentifier("statistics.empty")
            }
            metric("Movie viewing events", value.movieEvents, "movies")
            metric("Unique movies logged", value.uniqueMovies, "uniqueMovies")
            metric("Series viewing events", value.seriesEvents, "series")
            metric("Unique series logged", value.uniqueSeries, "uniqueSeries")
            metric("Months with movie logs", value.activeMovieMonths, "activeMonths")
            if let busiest = value.busiestMovieMonth {
                DashboardMetricRow(label: "Busiest movie month", value: "\(monthName(busiest.number)): \(busiest.movieEvents) viewing events")
            }
            Text("Rewatches add events, not unique titles. Tied busiest months use the earliest month.").font(.footnote)
        }
    }
    private func monthly(_ value: PersonalStatisticsSnapshot) -> some View {
        Section("Monthly Diary Activity") {
            Chart(value.months) { month in
                BarMark(x: .value("Month", monthName(month.number)), y: .value("Viewing events", month.movieEvents))
                    .foregroundStyle(by: .value("Media", "Movies"))
                    .position(by: .value("Media", "Movies"))
                BarMark(x: .value("Month", monthName(month.number)), y: .value("Viewing events", month.seriesEvents))
                    .foregroundStyle(by: .value("Media", "TV Series"))
                    .position(by: .value("Media", "TV Series"))
            }
            .chartForegroundStyleScale(["Movies": AppStyle.Colors.accent, "TV Series": AppStyle.Colors.primaryText])
            .chartXAxis(.hidden).frame(height: 180)
            .accessibilityLabel("Monthly diary activity for \(value.year)")
            .accessibilityIdentifier("statistics.monthlyChart")
            // Native rows remain readable with VoiceOver, high contrast and large Dynamic Type.
            ForEach(value.months) { month in
                DashboardMetricRow(label: monthName(month.number), value: "\(month.movieEvents) movie, \(month.seriesEvents) series events")
                    .accessibilityIdentifier("statistics.month.\(month.number)")
            }
        }
    }
    private func ratings(_ value: PersonalStatisticsSnapshot) -> some View {
        Section("Current Personal Ratings · All Years") {
            Text("Your current ratings across saved movies and TV, independent of the selected year. Rating edits are not historical watch events.")
                .font(.footnote)
            Chart(value.ratingBuckets) { bucket in
                BarMark(x: .value("Stars", bucket.stars), y: .value("Titles", bucket.count), width: .ratio(0.7))
                    .foregroundStyle(AppStyle.Colors.accent)
            }.frame(height: 160).chartXScale(domain: 0...5.5)
                .accessibilityLabel("Current personal rating distribution, all years")
                .accessibilityIdentifier("statistics.ratingsChart")
            ForEach(value.ratingBuckets) { bucket in
                DashboardMetricRow(label: "\(bucket.stars.formatted(.number.precision(.fractionLength(1)))) stars", value: "\(bucket.count) titles")
            }
            metric("Unrated titles", value.unratedTitles, "unrated")
            if value.invalidRatings > 0 { Text("\(value.invalidRatings) invalid saved ratings are excluded.").font(.footnote) }
            Text("Each title contributes its current valid half-star rating once. No historical rating is reconstructed from an edit timestamp.").font(.footnote)
        }
    }
    private func genres(_ value: PersonalStatisticsSnapshot) -> some View {
        Section("Genres of Logged Titles") {
            Text("Unique movie and series titles logged in \(String(value.year)), using available local genre metadata. A multi-genre title contributes once to each genre; rewatching it does not increase its genre count.")
                .font(.footnote)
            if value.genres.isEmpty { Text("No eligible genre metadata for this year’s logged titles.").accessibilityIdentifier("statistics.genres.empty") }
            ForEach(value.genres) { genre in DashboardMetricRow(label: genre.name, value: "\(genre.titles) unique titles") }
            Text("\(value.genreEligibleTitles) titles have eligible genres; \(value.missingGenreTitles) have missing, expired or unavailable genre metadata. These are not your Favorites flag or a personalized recommendation.").font(.footnote)
        }
    }
    private func episodes(_ value: PersonalStatisticsSnapshot) -> some View {
        Section("TV Episode Marking Activity") {
            metric("Episodes marked watched this year", value.episodeMarks, "episodeMarks")
            metric("Current watched episode flags · all years", value.overallWatchedEpisodes, "overallEpisodes")
            ForEach(value.months) { month in
                DashboardMetricRow(label: monthName(month.number), value: "\(month.episodeMarks) episodes marked watched")
            }
            Text("Marking time records an action, not a verified viewing date. Only currently watched episodes with a known, nonfuture timestamp enter annual totals; specials are included. A single flag cannot count rewatches.").font(.footnote)
            Text("Across all years: \(value.unknownEpisodeDates) watched episodes have no marking date; \(value.excludedEpisodeDates) have invalid/future dates. \(value.conflictingEpisodes) conflicting duplicate identities are excluded. No dates are backfilled.").font(.footnote)
        }
    }
    private func metric(_ label: String, _ count: Int, _ identifier: String) -> some View {
        DashboardMetricRow(label: label, value: count.formatted()).accessibilityIdentifier("statistics." + identifier)
    }
    private func monthName(_ number: Int) -> String {
        var calendar = Calendar(identifier: .gregorian); calendar.locale = locale
        return calendar.monthSymbols[number - 1]
    }
}
