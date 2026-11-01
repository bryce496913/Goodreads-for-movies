import SwiftUI

struct TVSeasonEpisodesView: View {
    let number: Int
    @State private var model: TVProgressModel
    @State private var refresh = 0
    @State private var batchWatched: Bool?
    @State private var errorMessage: String?
    @Environment(LibraryStore.self) private var library

    init(number: Int, model: TVProgressModel) { self.number = number; _model = State(initialValue: model) }
    private var season: StoredTVSeason? { library.seasons(for: model.show.id).first { $0.number == number } }

    var body: some View {
        List {
            if model.usesTestData { Text("UI test data").font(.caption) }
            if let cached = season {
                Section {
                    ProgressDescription(summary: library.seasonProgress(cached), series: false)
                    if let saved = cached.refreshedAt {
                        Text("Episode metadata saved " + saved.formatted(date: .abbreviated, time: .shortened)).font(.footnote)
                    }
                    if model.isLoading { ProgressView("Updating episodes…") }
                    if let error = model.errorMessage { Text("Showing saved episodes. " + error).accessibilityIdentifier("tv.cached") }
                    Button("Mark Aired Episodes Watched") { batchWatched = true }
                        .disabled(library.episodes(for: cached).isEmpty).accessibilityIdentifier("tv.batchWatched")
                    Button("Mark Season Unwatched") { batchWatched = false }
                        .disabled(library.episodes(for: cached).isEmpty).accessibilityIdentifier("tv.batchUnwatched")
                    if !model.isLoading { Button("Refresh Episodes") { refresh += 1 }.accessibilityIdentifier("tv.refreshEpisodes") }
                }
                if library.episodes(for: cached).isEmpty && !model.isLoading {
                    Text("No saved episodes available for this season.")
                }
                ForEach(library.episodes(for: cached)) { episode in
                    VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
                        Text("Episode \(episode.number): \(episode.title)").font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        if let airDate = episode.airDate {
                            Text((library.isFuture(episode) ? "Future air date: " : "Air date: ") + DetailFormatting.date(airDate)).font(.subheadline)
                        } else { Text("Air date unknown; excluded from aired progress.").font(.subheadline) }
                        if let runtime = episode.runtimeMinutes, runtime > 0 { Text("\(runtime) min").font(.subheadline) }
                        Text(episode.overview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Synopsis unavailable." : episode.overview)
                            .font(.body).fixedSize(horizontal: false, vertical: true)
                        if !cached.listedIDs.contains(episode.id) {
                            Text("Previously loaded; not in the latest episode listing.").font(.footnote)
                        }
                        Toggle("Watched", isOn: Binding(get: { library.isWatched(episode.id) }, set: { watched in
                            perform { try library.setEpisodeWatched(watched, episode: episode, show: model.show) }
                        }))
                        .disabled(library.isFuture(episode) && !library.isWatched(episode.id))
                        .accessibilityLabel("Watched: season \(number), episode \(episode.number), \(episode.title)")
                        .accessibilityIdentifier("episode.toggle.\(episode.id.providerValue)")
                    }
                }
            } else {
                Text("No saved season metadata is available.")
                if let error = model.errorMessage { Text(error) }
            }
        }
        .navigationTitle(number == 0 ? "Specials" : "Season \(number)")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: refresh) { await model.loadSeason(number, store: library) }
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

    private func perform(_ operation: () throws -> Void) {
        do { try operation() } catch { errorMessage = error.localizedDescription }
    }
}
