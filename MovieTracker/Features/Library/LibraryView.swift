import SwiftUI

struct LibraryView: View {
    let detailModel: (MediaDestination, MediaSearchResult?) -> MediaDetailModel
    @Environment(LibraryStore.self) private var library

    var body: some View {
        List {
            NavigationLink("TV Episode Progress") { SavedTVProgressView() }
                .accessibilityIdentifier("tv.savedProgress")
            NavigationLink("Viewing History") { ViewingHistoryView() }
                .accessibilityIdentifier("diary.open")
            NavigationLink("Personal Reviews") { PersonalReviewsView() }
                .accessibilityIdentifier("review.archive")
            if let error = library.loadError {
                Text(error.localizedDescription).accessibilityIdentifier("library.loadError")
                Button("Retry Library") { library.reload() }
            }
            if library.entries.isEmpty && library.loadError == nil {
                ContentUnavailableView("Your library is empty", systemImage: "books.vertical",
                    description: Text("Find a movie or TV show in Search, then save it from its detail page."))
                    .accessibilityIdentifier("library.empty")
            }
            ForEach(library.entries) { entry in
                if let id = entry.mediaID {
                    NavigationLink(value: MediaDestination(id: id, title: entry.displayTitle, year: entry.savedYear)) {
                        VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
                            SearchResultRow(item: SearchItem(id: id, title: entry.displayTitle, year: entry.savedYear,
                                                           posterReference: entry.savedPosterReference), posterURL: entry.thumbnailURL)
                            PersonalRatingSummary(entry: entry)
                            Text(entry.statusLabel).font(.subheadline).foregroundStyle(.secondary)
                            if entry.isFavorite { Label("Favorite", systemImage: "heart.fill").font(.subheadline) }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .accessibilityIdentifier("library.row.\(id.kind.rawValue).\(id.value)")
                } else {
                    Text("\(entry.displayTitle) — unknown media type")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Library")
        .navigationDestination(for: MediaDestination.self) { destination in
            let media = library.entry(for: destination.id)?.offlineMedia
                ?? library.events(for: destination.id).first?.savedMedia ?? library.reviews(for: destination.id).first?.savedMedia
                ?? library.savedTVShow(for: destination.id).map { .tvShow($0) }
            MediaDetailView(model: detailModel(destination, media))
        }
    }
}
