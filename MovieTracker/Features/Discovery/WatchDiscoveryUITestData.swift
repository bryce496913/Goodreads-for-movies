#if DEBUG
import Foundation

/// Explicit opt-in only, inside the application's isolated UI-test container.
@MainActor
enum WatchDiscoveryUITestData {
    static func seed(_ store: LibraryStore) throws {
        let movie = MediaSearchResult.movie(Movie(id: "fixture:discovery:movie", title: "A Quiet Evening", releaseDate: Date(timeIntervalSince1970: 1_577_836_800), runtimeMinutes: 90,
            genres: [MediaGenre(id: "drama", name: "Drama")]))
        let show = MediaSearchResult.tvShow(TVShow(id: "fixture:discovery:show", title: "One More Episode", firstAirDate: Date(timeIntervalSince1970: 1_609_459_200),
            episodeRuntimeMinutes: 42, genres: [MediaGenre(id: "comedy", name: "Comedy")]))
        let watched = MediaSearchResult.movie(Movie(id: "fixture:discovery:watched", title: "An Old Favorite", runtimeMinutes: 120,
            genres: [MediaGenre(id: "comedy", name: "Comedy")]))
        try store.setStatus(.watchlist, media: movie)
        try store.setStatus(.watchlist, media: show)
        try store.setStatus(.watched, media: watched)
        let collection = try store.saveCollection(name: "Movie Night")
        try store.setCollectionMembership(true, collection: collection, media: watched)
    }
}
#endif
