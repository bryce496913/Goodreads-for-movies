import SwiftUI

/// Saved metadata remains reachable offline even when the title has no Library row.
struct SavedTVProgressView: View {
    @Environment(LibraryStore.self) private var library
    private var shows: [TVShow] {
        var seen = Set<MediaID>()
        return library.tvSeasons.compactMap { row -> TVShow? in
            seen.insert(row.seriesID).inserted ? library.savedTVShow(for: row.seriesID) : nil
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    var body: some View {
        List {
            Text("Previously loaded TV seasons remain available offline. Percentages require complete episode metadata.").font(.footnote)
            if let error = library.loadError {
                Text(error.localizedDescription)
                Button("Retry Saved Progress") { library.reload() }
            }
            if shows.isEmpty && library.loadError == nil {
                ContentUnavailableView("No saved TV seasons", systemImage: "tv",
                    description: Text("Open a series in Search and load its season information."))
            }
            ForEach(shows) { show in
                NavigationLink(value: MediaDestination(id: show.id, title: show.title, year: SearchItem(.tvShow(show)).year)) {
                    VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
                        Text(show.title).font(.headline)
                        ProgressDescription(summary: library.seriesProgress(show.id), series: true)
                    }
                }.accessibilityIdentifier("tv.savedSeries.\(show.id.value)")
            }
        }
        .navigationTitle("TV Episode Progress")
    }
}
