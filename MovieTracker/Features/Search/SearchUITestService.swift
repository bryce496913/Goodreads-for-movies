#if DEBUG
import Foundation

/// Compiled only for debug UI tests; never used without the explicit launch argument.
actor SearchUITestService: MediaMetadataService {
    private var retryAttempts = 0
    private var detailAttempts = 0
    private let detailScenario: String

    init(detailScenario: String = "complete") { self.detailScenario = detailScenario }
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

    func movieDetails(id: MediaID) async throws -> Movie {
        try checkDetails()
        guard id.kind == .movie, ["fixture:1", "fixture:2"].contains(id.value) else { throw MetadataError.invalidIdentifier }
        if detailScenario == "missing" { return Movie(id: id.value, title: "Sample Story") }
        return Movie(id: id.value, title: detailScenario == "long" ? longTitle : "Sample Story",
            overview: detailScenario == "long" ? longOverview : "A fictional movie synopsis for deterministic UI testing.",
            releaseDate: movie.releaseDate, runtimeMinutes: 98,
            genres: [MediaGenre(id: "fixture:drama", name: "Drama")])
    }

    func tvShowDetails(id: MediaID) async throws -> TVShow {
        try checkDetails()
        guard id.kind == .tvShow, id.value == "fixture:1" else { throw MetadataError.invalidIdentifier }
        if detailScenario == "missing" { return TVShow(id: id.value, title: "Sample Story") }
        return TVShow(id: id.value, title: detailScenario == "long" ? longTitle : "Sample Story",
            overview: detailScenario == "long" ? longOverview : "A fictional series synopsis for deterministic UI testing.",
            firstAirDate: show.firstAirDate, seasonCount: 3, episodeRuntimeMinutes: 45,
            genres: [MediaGenre(id: "fixture:drama", name: "Drama")], episodeCount: 24, seriesStatus: "Returning Series")
    }

    func castPreview(for id: MediaID) async throws -> [CastMember] {
        if detailScenario == "missing" { return [] }
        return [CastMember(id: "fixture:cast1", name: "Sample Performer", character: "Lead"),
                CastMember(id: "fixture:cast2", name: "Another Performer", character: nil)]
    }

    private func checkDetails() throws {
        detailAttempts += 1
        if detailScenario == "error" || (detailScenario == "retry" && detailAttempts == 1)
            || (detailScenario == "offline-after-load" && detailAttempts > 1) { throw MetadataError.offline }
    }

    private var longTitle: String { String(repeating: "A Very Long Movie and Television Title ", count: 4) }
    private var longOverview: String { String(repeating: "An extended fictional synopsis that remains readable while scrolling. ", count: 8) }

    func genres(for kind: MediaID.Kind) async throws -> [MediaGenre] { [] }
    func imageResolver() async throws -> MetadataImageResolver { throw MetadataError.invalidPayload }
}
#endif
