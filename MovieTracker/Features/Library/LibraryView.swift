import SwiftUI

struct LibraryView: View {
    let detailModel: (MediaDestination, MediaSearchResult?) -> MediaDetailModel
    @Environment(LibraryStore.self) private var library

    var body: some View {
        List {
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
            MediaDetailView(model: detailModel(destination, library.entry(for: destination.id)?.savedMedia))
        }
    }
}
