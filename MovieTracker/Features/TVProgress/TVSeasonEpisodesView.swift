import SwiftUI

struct TVSeasonEpisodesView: View {
    let number: Int
    var embedded = false
    var loadsAutomatically = true
    @State private var model: TVProgressModel
    @State private var refresh = 0
    @State private var batchWatched: Bool?
    @State private var errorMessage: String?
    @State private var progressSaved = false
    @Environment(LibraryStore.self) private var library

    init(number: Int, model: TVProgressModel, embedded: Bool = false, loadsAutomatically: Bool = true) {
        self.number = number; self.embedded = embedded; self.loadsAutomatically = loadsAutomatically
        _model = State(initialValue: model)
    }
    private var season: StoredTVSeason? { library.seasons(for: model.show.id).first { $0.number == number } }

    var body: some View {
        Group {
            if embedded {
                LazyVStack(alignment: .leading, spacing: AppStyle.Spacing.medium) { content }
            } else {
                List { content }
                    .appListScreen(TVSeasonPresentation.title(number))
                    .accessibilityIdentifier("screen.season")
            }
        }
        .onChange(of: library.metadataReferenceDate) { _, now in model.expireMetadata(at: now) }
        .task(id: refresh) { if loadsAutomatically || refresh > 0 { await model.loadSeason(number, store: library, force: refresh > 0) } }
        .confirmationDialog(batchWatched == true ? "Mark known aired episodes watched?" : "Mark this season unwatched?",
            isPresented: Binding(get: { batchWatched != nil }, set: { if !$0 { batchWatched = nil } }), titleVisibility: .visible) {
            Button(batchWatched == true ? "Mark Aired Watched" : "Mark Unwatched", role: batchWatched == true ? nil : .destructive) {
                if let season, let watched = batchWatched { perform { try library.setSeasonWatched(watched, season: season, show: model.show) } }
                batchWatched = nil
            }
        } message: {
            Text(batchWatched == true
                 ? "Only known aired episodes will change. Future and unknown air dates are skipped. Use Mark Season Unwatched to reverse watched state."
                 : "All saved watched flags in this season will be cleared, including manually marked episodes. Other seasons, ratings and diary entries stay unchanged.")
        }
        .alert("Progress could not be saved", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "Try again.") }
    }

    @ViewBuilder private var content: some View {
        if model.usesTestData { Text("UI test data").font(.caption) }
        if let cached = season {
            VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
                if !embedded { ProgressDescription(summary: library.seasonProgress(cached), series: false) }
                if progressSaved {
                    Label("Progress saved", systemImage: "checkmark.circle")
                        .font(AppStyle.Typography.caption).foregroundStyle(AppStyle.Colors.secondaryText)
                        .accessibilityIdentifier("tv.progressSaved")
                }
                if model.isLoading { AppLoadingState(title: "Loading episodes…") }
                if let error = model.errorMessage {
                    AppErrorMessage(message: "Episode update unavailable. Saved watched flags are kept. " + error)
                        .accessibilityIdentifier("tv.cached")
                }
                Menu {
                    Button("Mark Aired Episodes Watched") { batchWatched = true }
                        .disabled(library.episodes(for: cached).isEmpty).accessibilityIdentifier("tv.batchWatched")
                    Button("Mark Season Unwatched", role: .destructive) { batchWatched = false }
                        .disabled(library.episodes(for: cached).isEmpty).accessibilityIdentifier("tv.batchUnwatched")
                } label: { Label("Season actions", systemImage: "ellipsis.circle") }
                .frame(minHeight: AppStyle.Layout.minimumTarget, alignment: .leading)
                .accessibilityIdentifier("tv.actions." + String(number))
                if model.canRefresh && !model.isLoading {
                    Button(model.errorMessage == nil ? "Refresh Episodes" : "Retry Episodes") { refresh += 1 }
                        .accessibilityIdentifier("tv.refreshEpisodes")
                }
                if library.episodes(for: cached).isEmpty && !model.isLoading {
                    Text(TVSeasonPresentation.emptyState(loaded: cached.listingLoaded, expected: cached.expectedEpisodeCount))
                        .font(AppStyle.Typography.metadata).foregroundStyle(AppStyle.Colors.secondaryText)
                }
                DisclosureGroup("Metadata details") {
                    let receipt = MetadataAvailability.receipt(cached.refreshedAt, at: library.metadataReferenceDate)
                    let availability: MetadataAvailability = !cached.listingLoaded && MetadataPolicy.isUsable(cached.refreshedAt, at: library.metadataReferenceDate) ? .unavailable : receipt
                    Text(availability.message).accessibilityIdentifier("tv.availability")
                    if let saved = cached.refreshedAt { Text("Episode metadata saved " + saved.formatted(date: .abbreviated, time: .shortened)) }
                    Text("Future and unknown air dates are excluded from aired progress. Watched flags remain available offline.")
                    let summary = library.seasonProgress(cached)
                    if summary.future > 0 { Text("\(summary.future) future episodes excluded") }
                    if summary.unknownAirDate > 0 { Text("\(summary.unknownAirDate) unknown air dates excluded") }
                    if !cached.isListed { Text("Previously loaded; missing from the latest catalogue.") }
                    if !cached.name.isEmpty && cached.name != TVSeasonPresentation.title(cached.number) { Text(cached.name) }
                }.font(AppStyle.Typography.caption)
            }
            ForEach(library.episodes(for: cached)) { episode in
                TVEpisodeRow(episode: episode, watched: library.isWatched(episode.id),
                    future: library.isFuture(episode), listed: cached.listedIDs.contains(episode.id)) { watched in
                        perform { try library.setEpisodeWatched(watched, episode: episode, show: model.show) }
                    }
            }
        } else {
            EmptyStateCard(title: "No saved season metadata", systemImage: "tv",
                message: "Saved watched flags are kept. Retry when metadata is available, or return to the series.", presentation: .inline)
            if model.isLoading { ProgressView("Loading episodes…") }
            if let error = model.errorMessage { Text(error) }
            if model.canRefresh && !model.isLoading { Button("Retry Episodes") { refresh += 1 }.accessibilityIdentifier("tv.refreshEpisodes") }
        }
    }

    private func perform(_ operation: () throws -> Void) {
        do { try operation(); progressSaved = true } catch { progressSaved = false; errorMessage = error.localizedDescription }
    }
}

struct TVEpisodeRow: View {
    let episode: TVEpisode
    let watched: Bool
    let future: Bool
    let listed: Bool
    let setWatched: @MainActor @Sendable (Bool) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.xSmall) {
            Toggle(isOn: Binding(get: { watched }, set: { value in setWatched(value) })) {
                VStack(alignment: .leading, spacing: AppStyle.Spacing.xSmall) {
                    Text(episode.number > 0 ? "E\(episode.number) — \(episode.title)" : "Saved episode")
                        .font(AppStyle.Typography.mediaTitle).fixedSize(horizontal: false, vertical: true)
                    if let date = episode.airDate {
                        Text((future ? "Upcoming · " : "") + DetailFormatting.date(date))
                            .font(AppStyle.Typography.caption).foregroundStyle(AppStyle.Colors.secondaryText)
                    } else {
                        Text("Air date unavailable").font(AppStyle.Typography.caption).foregroundStyle(AppStyle.Colors.secondaryText)
                    }
                }
            }
            .disabled(future && !watched)
            .frame(minHeight: AppStyle.Layout.minimumTarget)
            .accessibilityLabel(episode.number == 0 ? "Watched episode reference " + episode.id.providerValue : "Watched: season \(episode.seasonNumber), episode \(episode.number), \(episode.title)")
            .accessibilityIdentifier("episode.toggle.\(episode.id.providerValue)")
            if !listed { Text("Previously saved episode").font(AppStyle.Typography.caption).foregroundStyle(AppStyle.Colors.secondaryText) }
            if !episode.overview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (episode.runtimeMinutes ?? 0) > 0 {
                DisclosureGroup("Episode synopsis") {
                    if let runtime = episode.runtimeMinutes, runtime > 0 { Text("\(runtime) min").font(AppStyle.Typography.caption) }
                    Text(episode.overview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Synopsis unavailable." : episode.overview)
                        .font(AppStyle.Typography.body).fixedSize(horizontal: false, vertical: true)
                }.font(AppStyle.Typography.metadata)
            }
        }
        .padding(.vertical, AppStyle.Spacing.xSmall)
    }
}
