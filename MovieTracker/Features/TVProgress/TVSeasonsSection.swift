import SwiftUI

private struct CatalogTask: Hashable {
    let series: MediaID
    let seasons: [TVSeasonSummary]?
    let refresh: Int
    let fresh: Bool
}
struct TVSeasonDestination: Hashable { let series: MediaID; let number: Int }

struct TVSeasonsSection: View {
    let show: TVShow
    let catalogIsFresh: Bool
    @State private var model: TVProgressModel
    @State private var refresh = 0
    @State private var lastRefreshRequest = 0
    @Environment(LibraryStore.self) private var library

    init(show: TVShow, catalogIsFresh: Bool, model: TVProgressModel) {
        self.show = show; self.catalogIsFresh = catalogIsFresh; _model = State(initialValue: model)
    }

    var body: some View {
        DetailSection(title: "Seasons and episode progress") {
            ProgressDescription(summary: library.seriesProgress(show.id), series: true)
            Text("Regular seasons only. Specials are separate. Unknown air dates are excluded from aired progress. Progress never marks a series permanently complete.")
                .font(.footnote).foregroundStyle(.secondary)
            if model.isLoading { ProgressView("Loading seasons…") }
            if let error = model.errorMessage { Text("Season update unavailable. " + error).foregroundStyle(.secondary) }
            if library.seasons(for: show.id).isEmpty && !model.isLoading {
                Text(model.errorMessage == nil ? "No seasons available." : "No saved seasons are available.")
            }
            ForEach(library.seasons(for: show.id)) { season in
                NavigationLink(value: TVSeasonDestination(series: show.id, number: season.number)) {
                    VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
                        Text(season.name).font(.headline)
                        Text(season.number == 0 ? "Specials (season 0)" : "Season \(season.number)")
                        Text(season.expectedEpisodeCount.map { "\($0) known episodes" } ?? "Episode count unavailable")
                        ProgressDescription(summary: library.seasonProgress(season), series: false)
                        if let saved = season.refreshedAt {
                            Text("Episodes saved " + saved.formatted(date: .abbreviated, time: .shortened)).font(.footnote)
                        }
                        if !season.isListed { Text("Previously loaded; missing from the latest catalogue.").font(.footnote) }
                    }
                }
                .accessibilityIdentifier("tv.season.\(season.number)")
            }
            if !model.isLoading {
                Button("Refresh Seasons") { refresh += 1 }.accessibilityIdentifier("tv.refreshSeasons")
            }
        }
        .task(id: CatalogTask(series: show.id, seasons: show.seasons, refresh: refresh, fresh: catalogIsFresh)) {
            let force = refresh != lastRefreshRequest
            lastRefreshRequest = refresh
            await model.loadCatalog(show: show, store: library, snapshotIsFresh: catalogIsFresh, forceRefresh: force)
        }
        .navigationDestination(for: TVSeasonDestination.self) { destination in
            if destination.series == show.id, let cached = library.seasons(for: show.id).first(where: { $0.number == destination.number }) {
                TVSeasonEpisodesView(number: cached.number, model: model.seasonModel(cached))
            } else {
                ContentUnavailableView("Season unavailable", systemImage: "tv")
            }
        }
    }
}

struct ProgressDescription: View {
    let summary: EpisodeProgressSummary
    let series: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Episodes marked watched: \(summary.totalWatched)").font(.subheadline)
            Text("\(summary.watched) watched of \(summary.eligible) known aired episodes")
            if let percentage = summary.percentage {
                Text("\(percentage)% of known aired episodes").font(.subheadline)
                ProgressView(value: Double(summary.watched), total: Double(summary.eligible))
                    .accessibilityLabel("Known aired episode progress").accessibilityValue("\(percentage) percent")
            } else {
                Text(summary.eligible == 0 ? "No eligible aired episodes known." : "Percentage unavailable: episode metadata is incomplete.")
                    .font(.footnote)
            }
            if summary.isUpToDate {
                Label(series ? "All known aired regular episodes watched" : "All known aired episodes watched", systemImage: "checkmark.circle")
            }
            if summary.future > 0 { Text("\(summary.future) future episodes excluded").font(.footnote) }
            if summary.unknownAirDate > 0 { Text("\(summary.unknownAirDate) unknown air dates excluded").font(.footnote) }
        }
    }
}
