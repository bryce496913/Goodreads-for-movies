#if DEBUG
import Foundation

/// Compiled only for debug UI tests; never used without the explicit launch argument.
actor SearchUITestService: MediaMetadataService {
    private var retryAttempts = 0
    private let movie = Movie(id: "fixture:1", title: "Sample Story", releaseDate: Date(timeIntervalSince1970: 1_577_836_800))
    private let show = TVShow(id: "fixture:1", title: "Sample Story", firstAirDate: Date(timeIntervalSince1970: 1_704_067_200))

    func searchAll(query: String, page: Int) async throws -> MetadataPage<MediaSearchResult> {
        try check(query)
        if query == "empty" { return MetadataPage(items: [], page: page, totalPages: 0, totalResults: 0) }
        let values: [MediaSearchResult] = page == 1 ? [.movie(movie), .tvShow(show)]
            : [.movie(movie), .movie(Movie(id: "fixture:2", title: "Another Sample Story"))]
        return MetadataPage(items: values, page: page, totalPages: 2, totalResults: 3)
    }

    func searchMovies(query: String, page: Int) async throws -> MetadataPage<Movie> {
        try check(query)
        return MetadataPage(items: query == "empty" ? [] : [movie], page: page, totalPages: query == "empty" ? 0 : 1, totalResults: query == "empty" ? 0 : 1)
    }

    func searchTVShows(query: String, page: Int) async throws -> MetadataPage<TVShow> {
        try check(query)
        return MetadataPage(items: query == "empty" ? [] : [show], page: page, totalPages: query == "empty" ? 0 : 1, totalResults: query == "empty" ? 0 : 1)
    }

    private func check(_ query: String) throws {
        if query == "error" { throw MetadataError.offline }
        if query == "retry" {
            retryAttempts += 1
            if retryAttempts == 1 { throw MetadataError.offline }
        }
    }

    func movieDetails(id: MediaID) async throws -> Movie { throw MetadataError.invalidIdentifier }
    func tvShowDetails(id: MediaID) async throws -> TVShow { throw MetadataError.invalidIdentifier }
    func genres(for kind: MediaID.Kind) async throws -> [MediaGenre] { [] }
    func imageResolver() async throws -> MetadataImageResolver { throw MetadataError.invalidPayload }
}
#endif
