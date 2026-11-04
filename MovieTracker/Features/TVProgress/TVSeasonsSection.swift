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
            if model.isLoading { ProgressView("Loading seasons…") }
            if let error = model.errorMessage { Text("Season update unavailable. " + error).foregroundStyle(.secondary) }
            if library.seasons(for: show.id).isEmpty && !model.isLoading {
                EmptyStateCard(title: "No saved seasons", systemImage: "tv",
                    message: "Load season metadata when available to browse episodes. Your series status is separate from episode progress.", presentation: .inline)
            }
            ForEach(library.seasons(for: show.id)) { season in
                TVSeasonGroup(season: season, model: model.seasonModel(season))
            }
            if model.canRefresh && !model.isLoading {
                Button("Refresh Seasons") { refresh += 1 }.buttonStyle(AppActionStyle()).accessibilityIdentifier("tv.refreshSeasons")
            }
        }
        .onChange(of: library.metadataReferenceDate) { _, now in model.expireMetadata(at: now) }
        .task(id: CatalogTask(series: show.id, seasons: show.seasons, refresh: refresh, fresh: catalogIsFresh)) {
            let force = refresh != lastRefreshRequest
            lastRefreshRequest = refresh
            await model.loadCatalog(show: show, store: library, snapshotIsFresh: catalogIsFresh, forceRefresh: force)
        }
        .navigationDestination(for: TVSeasonDestination.self) { destination in
            if destination.series == show.id, let cached = library.seasons(for: show.id).first(where: { $0.number == destination.number }) {
                TVSeasonEpisodesView(number: cached.number, model: model.seasonModel(cached))
            } else {
                EmptyStateCard(title: "Season unavailable", systemImage: "tv",
                    message: "No season metadata is saved here. Return to the series and refresh when available.", presentation: .inline)
                    .padding(AppStyle.Layout.contentMargin)
                    .appPageTitle("Season")
            }
        }
    }
}

struct ProgressDescription: View {
    let summary: EpisodeProgressSummary
    let series: Bool
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.xSmall) {
            Text(TVSeasonPresentation.progress(summary))
                .font(AppStyle.Typography.metadata).foregroundStyle(AppStyle.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let percentage = summary.percentage {
                ProgressView(value: Double(percentage), total: 100)
                    .accessibilityLabel(series ? "Known aired regular episode progress" : "Known aired episode progress")
                    .accessibilityValue("\(percentage) percent")
            }
            if summary.isUpToDate {
                Label(series ? "Up to date with known aired regular episodes" : "All known aired episodes watched", systemImage: "checkmark.circle.fill")
                    .font(AppStyle.Typography.caption)
            }
            if series && !compact {
                Text("Known aired regular episodes only; not series completion.")
                    .font(AppStyle.Typography.caption).foregroundStyle(AppStyle.Colors.secondaryText)
            }
        }
        .tint(AppStyle.Colors.accent)
        .accessibilityIdentifier("tv.progressSummary")
    }
}

struct TVSeasonGroup: View {
    let season: StoredTVSeason
    @State private var model: TVProgressModel
    @State private var expanded = false
    @State private var attemptedLoad = false
    @Environment(LibraryStore.self) private var library

    init(season: StoredTVSeason, model: TVProgressModel) {
        self.season = season
        _model = State(initialValue: model)
    }
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            if expanded {
                TVSeasonEpisodesView(number: season.number, model: model, embedded: true, loadsAutomatically: false)
                    .padding(.leading, AppStyle.Spacing.small)
                NavigationLink(value: TVSeasonDestination(series: season.seriesID, number: season.number)) {
                    Label("Open " + TVSeasonPresentation.title(season.number), systemImage: "arrow.up.right")
                }.accessibilityIdentifier("tv.openSeason.\(season.number)")
            }
        } label: {
            VStack(alignment: .leading, spacing: AppStyle.Spacing.xSmall) {
                Text(TVSeasonPresentation.title(season.number)).font(AppStyle.Typography.mediaTitle)
                    .foregroundStyle(AppStyle.Colors.primaryText)
                if library.episodes(for: season).isEmpty {
                    if !expanded {
                        Text(TVSeasonPresentation.emptyState(loaded: season.listingLoaded, expected: season.expectedEpisodeCount))
                            .font(AppStyle.Typography.metadata).foregroundStyle(AppStyle.Colors.secondaryText)
                    }
                } else {
                    ProgressDescription(summary: library.seasonProgress(season), series: false, compact: true)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: AppStyle.Layout.minimumTarget, alignment: .leading)
        }
        .accessibilityIdentifier("tv.season.\(season.number)")
        .task(id: expanded) {
            guard expanded, !attemptedLoad else { return }
            attemptedLoad = true
            await model.loadSeason(season.number, store: library)
            if Task.isCancelled { attemptedLoad = false }
        }
        .onChange(of: library.metadataReferenceDate) { _, now in model.expireMetadata(at: now) }
        .padding(.vertical, AppStyle.Spacing.small)
        .overlay(alignment: .bottom) { Divider() }
    }
}

enum TVSeasonPresentation {
    static func title(_ number: Int) -> String { number == 0 ? "Specials" : "Season \(number)" }
    static func emptyState(loaded: Bool, expected: Int?) -> String {
        loaded && expected == 0 ? "No episodes listed" : "Episode details unavailable"
    }
    static func progress(_ summary: EpisodeProgressSummary) -> String {
        if let percentage = summary.percentage {
            return "\(summary.watched) of \(summary.eligible) known aired episodes · \(percentage)% of known"
        }
        return "\(summary.totalWatched) \(summary.totalWatched == 1 ? "episode" : "episodes") watched"
    }
}
