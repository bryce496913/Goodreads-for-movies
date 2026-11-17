import SwiftUI

struct LibraryDetailActions: View {
    let media: MediaSearchResult
    let posterURL: URL?
    @Environment(LibraryStore.self) private var library
    @State private var errorMessage: String?
    @State private var confirmRemoval = false
    @State private var loggingWatch = false

    private var item: SearchItem { SearchItem(media) }
    private var entry: StoredLibraryEntry? { library.entry(for: item.id) }

    var body: some View {
        DetailSection(title: "Your library") {
            if let error = library.loadError { Text(error.localizedDescription).foregroundStyle(.secondary) }
            if item.id.kind == .movie {
                Button(library.events(for: item.id).isEmpty && entry?.status != LibraryStatus.watched.rawValue ? "Log a Watch" : "Log Again", systemImage: "plus.circle") { loggingWatch = true }
                    .buttonStyle(AppActionStyle(emphasis: .primary, fillsWidth: true)).accessibilityIdentifier("watch.open")
            }
            ViewingStatusSelector(status: entry.flatMap { LibraryStatus(rawValue: $0.status) },
                currentLabel: entry?.statusLabel ?? "Not in your library", supportsWatching: item.id.kind == .tvShow, canClear: entry != nil && entry?.status != "none", emphasis: item.id.kind == .movie ? .secondary : .primary) { status in
                    perform { try library.setStatus(status, media: media, posterURL: posterURL) }
                }
            FavoriteAction(selected: entry?.isFavorite == true) {
                perform { try library.setFavorite(entry?.isFavorite != true, media: media, posterURL: posterURL) }
            }.accessibilityIdentifier("library.favoriteAction")
            AddToCollectionAction(media: media)
            PersonalRatingControl(current: { try library.entry(for: item.id)?.validatedRating() }, save: {
                try library.setPersonalRating($0, media: media, posterURL: posterURL)
            })
            if entry != nil {
                Button("Remove from Library", role: .destructive) { confirmRemoval = true }
                    .appDestructiveAction().accessibilityIdentifier("library.removeAction")
            }
        }
        .sheet(isPresented: $loggingWatch) {
            MovieWatchLogView(media: media, rating: Result { try library.entry(for: item.id)?.validatedRating() }).appEditorSheet()
        }
        .confirmationDialog("Remove this title from your library?", isPresented: $confirmRemoval, titleVisibility: .visible) {
            Button("Remove from Library", role: .destructive) { perform { try library.remove(item.id) } }
        } message: {
            Text("This removes the saved library entry, rating, status and favorite. Written reviews, viewing history, episode progress and collection memberships are kept. Collections retain this title by its saved identity; without cached metadata it may appear by ID.")
        }
        .alert("Library change failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "Your change could not be saved.") }
    }

    private func perform(_ operation: () throws -> Void) {
        do { try operation() } catch { errorMessage = error.localizedDescription }
    }
}
