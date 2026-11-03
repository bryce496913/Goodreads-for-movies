import SwiftUI

struct LibraryDetailActions: View {
    let media: MediaSearchResult
    let posterURL: URL?
    @Environment(LibraryStore.self) private var library
    @State private var errorMessage: String?
    @State private var confirmRemoval = false
    @Environment(\.dynamicTypeSize) private var textSize

    private var item: SearchItem { SearchItem(media) }
    private var entry: StoredLibraryEntry? { library.entry(for: item.id) }

    var body: some View {
        DetailSection(title: "Your library") {
            if let error = library.loadError { Text(error.localizedDescription).foregroundStyle(.secondary) }
            Text(entry?.statusLabel ?? "Not in your library")
                .accessibilityIdentifier("library.currentStatus")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading),
                                     count: textSize >= .xxxLarge ? 1 : 2),
                      alignment: .leading, spacing: AppStyle.Spacing.small) {
                Button(entry?.status == "watchlist" ? "Remove from Watchlist" : "Add to Watchlist",
                       systemImage: entry?.status == "watchlist" ? "bookmark.fill" : "bookmark") {
                    perform { try library.setStatus(entry?.status == "watchlist" ? nil : .watchlist, media: media, posterURL: posterURL) }
                }.accessibilityValue(entry?.status == "watchlist" ? "Selected" : "Not selected")
                    .accessibilityIdentifier("library.watchlistAction")
                if item.id.kind == .tvShow {
                    Button("Mark Watching", systemImage: entry?.status == "watching" ? "play.circle.fill" : "play.circle") {
                        perform { try library.setStatus(.watching, media: media, posterURL: posterURL) }
                    }.accessibilityValue(entry?.status == "watching" ? "Selected" : "Not selected")
                        .accessibilityIdentifier("library.watchingAction")
                }
                Button("Mark Watched", systemImage: entry?.status == "watched" ? "checkmark.circle.fill" : "checkmark.circle") {
                    perform { try library.setStatus(.watched, media: media, posterURL: posterURL) }
                }.accessibilityValue(entry?.status == "watched" ? "Selected" : "Not selected")
                    .accessibilityIdentifier("library.watchedAction")
                if entry != nil && entry?.status != "none" {
                    Button("Clear Viewing Status", systemImage: "minus.circle") {
                        perform { try library.setStatus(nil, media: media, posterURL: posterURL) }
                    }.accessibilityIdentifier("library.clearStatus")
                }
                Button(entry?.isFavorite == true ? "Remove Favorite" : "Add Favorite",
                       systemImage: entry?.isFavorite == true ? "heart.fill" : "heart") {
                    perform { try library.setFavorite(entry?.isFavorite != true, media: media, posterURL: posterURL) }
                }.accessibilityValue(entry?.isFavorite == true ? "Selected" : "Not selected")
                    .accessibilityIdentifier("library.favoriteAction")
            }
            .buttonStyle(AppActionStyle())
            PersonalRatingControl(current: { try library.entry(for: item.id)?.validatedRating() }, save: {
                try library.setPersonalRating($0, media: media, posterURL: posterURL)
            })
            if entry != nil {
                Button("Remove from Library", role: .destructive) { confirmRemoval = true }
                    .accessibilityIdentifier("library.removeAction")
            }
        }
        .buttonStyle(.bordered)
        .confirmationDialog("Remove this title from your library?", isPresented: $confirmRemoval, titleVisibility: .visible) {
            Button("Remove from Library", role: .destructive) { perform { try library.remove(item.id) } }
        } message: {
            Text("This removes the saved library entry, rating, status and favorite. Written reviews, viewing history and episode progress are kept.")
        }
        .alert("Library change failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "Your change could not be saved.") }
    }

    private func perform(_ operation: () throws -> Void) {
        do { try operation() } catch { errorMessage = error.localizedDescription }
    }
}
