import XCTest
@testable import MovieTracker

final class MediaDetailTests: XCTestCase {
    @MainActor
    func testMovieLoadsRealFieldsThroughMovieEndpoint() async {
        let movie = Movie(id: "1", title: "Movie", overview: "Overview", runtimeMinutes: 98,
                          genres: [MediaGenre(id: "drama", name: "Drama")])
        let service = DetailStubService(movie: movie)
        let model = makeModel(kind: .movie, service: service)
        await model.load()
        guard case .movie(let loaded)? = model.snapshot?.media else { return XCTFail("Expected movie details") }
        XCTAssertEqual(loaded, movie)
        XCTAssertEqual(model.snapshot?.cast.first?.name, "Performer")
        XCTAssertNil(model.error)
        XCTAssertFalse(model.isLoading)
        let calls = await service.calls
        XCTAssertEqual(calls, [MediaID(kind: .movie, value: "1")])
    }

    @MainActor
    func testTVLoadsCountsAndStatusThroughTVEndpoint() async {
        let show = TVShow(id: "1", title: "Show", seasonCount: 3, episodeCount: 24, seriesStatus: "Ended")
        let service = DetailStubService(show: show)
        let model = makeModel(kind: .tvShow, service: service)
        await model.load()
        guard case .tvShow(let loaded)? = model.snapshot?.media else { return XCTFail("Expected TV details") }
        XCTAssertEqual(loaded, show)
        let calls = await service.calls
        XCTAssertEqual(calls, [MediaID(kind: .tvShow, value: "1")])
    }

    @MainActor
    func testMissingMetadataAndArtworkSkipConfigurationRequest() async {
        let service = DetailStubService()
        let model = makeModel(kind: .movie, service: service)
        await model.load()
        XCTAssertNotNil(model.snapshot)
        XCTAssertNil(model.snapshot?.imageResolver)
        let imageCalls = await service.imageCalls
        XCTAssertEqual(imageCalls, 0)
        XCTAssertEqual(DetailFormatting.runtime(nil), "Unavailable")
        XCTAssertEqual(DetailFormatting.runtime(0), "Unavailable")
        XCTAssertEqual(DetailFormatting.count(-1), "Unavailable")
        XCTAssertEqual(DetailFormatting.date(nil), "Unavailable")
    }

    @MainActor
    func testOfflineErrorHasNoInventedMetadata() async {
        let service = DetailStubService()
        await service.setFailure(.offline)
        let model = makeModel(kind: .movie, service: service)
        await model.load()
        XCTAssertEqual(model.error, .offline)
        XCTAssertNil(model.snapshot)
        XCTAssertEqual(model.destination.title, "Selected title")
    }

    @MainActor
    func testMissingConfigurationAndExplicitRetry() async {
        let model = makeModel(kind: .movie, service: nil)
        await model.load()
        XCTAssertEqual(model.error, .missingCredential)
        XCTAssertFalse(model.isLoading)
        let service = DetailStubService()
        await service.setFailure(.offline)
        let retryModel = makeModel(kind: .movie, service: service)
        await retryModel.load()
        await service.setFailure(nil)
        await retryModel.load()
        XCTAssertNil(retryModel.error)
        XCTAssertNotNil(retryModel.snapshot)
    }

    @MainActor
    func testPreviouslyLoadedSnapshotRemainsVisibleWhenReopenedOffline() async {
        let service = DetailStubService()
        let cache = MediaDetailCache()
        let first = makeModel(kind: .movie, service: service, cache: cache)
        await first.load()
        await service.setFailure(.offline)
        let reopened = makeModel(kind: .movie, service: service, cache: cache)
        XCTAssertNotNil(reopened.snapshot)
        await reopened.load()
        XCTAssertNotNil(reopened.snapshot)
        XCTAssertEqual(reopened.error, .offline)
        XCTAssertFalse(reopened.isLoading)
    }

    @MainActor
    func testOptionalCastAndArtworkFailuresDoNotDiscardMovie() async {
        let service = DetailStubService(movie: Movie(id: "1", title: "Movie", posterReference: "/poster.jpg"), extrasFail: true)
        let model = makeModel(kind: .movie, service: service)
        await model.load()
        XCTAssertNotNil(model.snapshot)
        XCTAssertNil(model.error)
        XCTAssertTrue(model.castUnavailable)
        XCTAssertTrue(model.artworkUnavailable)
        XCTAssertNil(model.snapshot?.imageResolver)
    }

    @MainActor
    func testArtworkConfigurationIsPublishedWithoutImageDownloads() async throws {
        let resolver = try MetadataImageResolver(baseURL: XCTUnwrap(URL(string: "https://image.tmdb.org/t/p/")),
                                                 posterSizes: ["w342"], backdropSizes: ["w780"])
        let movie = Movie(id: "1", title: "Movie", posterReference: "/poster.jpg", backdropReference: "/back.jpg")
        let service = DetailStubService(movie: movie, resolver: resolver)
        let model = makeModel(kind: .movie, service: service)
        await model.load()
        XCTAssertNotNil(model.snapshot?.imageResolver?.posterURL(reference: movie.posterReference, size: .card))
        XCTAssertNotNil(model.snapshot?.imageResolver?.backdropURL(reference: movie.backdropReference, size: .detail))
        XCTAssertFalse(model.artworkUnavailable)
        let calls = await service.imageCalls
        XCTAssertEqual(calls, 1)
    }

    @MainActor
    func testMismatchedIdentityIsRejectedBeforeCaching() async {
        let service = DetailStubService(movie: Movie(id: "wrong", title: "Wrong"))
        let cache = MediaDetailCache()
        let model = makeModel(kind: .movie, service: service, cache: cache)
        await model.load()
        XCTAssertEqual(model.error, .invalidPayload)
        XCTAssertNil(model.snapshot)
        XCTAssertNil(cache.snapshot(for: model.destination.id))
    }

    @MainActor
    func testBoundedCacheSeparatesMovieAndTVWithSameID() {
        let cache = MediaDetailCache(capacity: 2)
        let movie = Movie(id: "1", title: "Movie")
        let show = TVShow(id: "1", title: "TV")
        cache.save(.init(media: .movie(movie)), for: movie.id)
        cache.save(.init(media: .tvShow(show)), for: show.id)
        XCTAssertNotNil(cache.snapshot(for: movie.id))
        XCTAssertNotNil(cache.snapshot(for: show.id))
        let later = Movie(id: "2", title: "Later")
        cache.save(.init(media: .movie(later)), for: later.id)
        XCTAssertNil(cache.snapshot(for: movie.id))
        XCTAssertNotNil(cache.snapshot(for: show.id))
    }

    @MainActor
    func testCanceledLateResponseCannotPopulateDetails() async {
        let gate = DetailLoadGate()
        let service = DetailStubService(gate: gate)
        let model = makeModel(kind: .movie, service: service)
        let task = Task { await model.load() }
        await gate.waitUntilRequested()
        XCTAssertTrue(model.isLoading)
        task.cancel()
        await gate.complete()
        await task.value
        XCTAssertNil(model.snapshot)
        XCTAssertTrue(model.wasCancelled)
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testSearchRouteReusesServiceAndSessionCache() async {
        let service = DetailStubService()
        let search = SearchModel(service: service, debounce: {})
        let route = MediaDestination(id: MediaID(kind: .movie, value: "1"), title: "Movie", year: nil)
        let first = search.detailModel(for: route)
        await first.load()
        await service.setFailure(.offline)
        let second = search.detailModel(for: route)
        XCTAssertNotNil(second.snapshot)
        await second.load()
        XCTAssertEqual(second.error, .offline)
    }

    @MainActor
    private func makeModel(kind: MediaID.Kind, service: (any MediaMetadataService)?, cache: MediaDetailCache? = nil) -> MediaDetailModel {
        MediaDetailModel(destination: MediaDestination(id: MediaID(kind: kind, value: "1"), title: "Selected title", year: nil),
                         service: service, cache: cache ?? MediaDetailCache())
    }
}

private actor DetailStubService: MediaMetadataService {
    private let movie: Movie
    private let show: TVShow
    private let extrasFail: Bool
    private let gate: DetailLoadGate?
    private let resolver: MetadataImageResolver?
    private var failure: MetadataError?
    private(set) var calls: [MediaID] = []
    private(set) var imageCalls = 0

    init(movie: Movie = Movie(id: "1", title: "Movie"), show: TVShow = TVShow(id: "1", title: "Show"),
         extrasFail: Bool = false, gate: DetailLoadGate? = nil, resolver: MetadataImageResolver? = nil) {
        self.movie = movie; self.show = show; self.extrasFail = extrasFail; self.gate = gate; self.resolver = resolver
    }
    func setFailure(_ error: MetadataError?) { failure = error }
    func movieDetails(id: MediaID) async throws -> Movie {
        calls.append(id)
        if let gate { await gate.pause() }
        if let failure { throw failure }
        return movie
    }
    func tvShowDetails(id: MediaID) async throws -> TVShow {
        calls.append(id)
        if let failure { throw failure }
        return show
    }
    func castPreview(for id: MediaID) async throws -> [CastMember] {
        if extrasFail { throw MetadataError.server(status: 503) }
        return [CastMember(id: "person:1", name: "Performer", character: nil)]
    }
    func imageResolver() async throws -> MetadataImageResolver {
        imageCalls += 1
        if let resolver { return resolver }
        throw MetadataError.offline
    }
    func searchAll(query: String, page: Int) async throws -> MetadataPage<MediaSearchResult> { throw MetadataError.invalidQuery }
    func searchMovies(query: String, page: Int) async throws -> MetadataPage<Movie> { throw MetadataError.invalidQuery }
    func searchTVShows(query: String, page: Int) async throws -> MetadataPage<TVShow> { throw MetadataError.invalidQuery }
    func genres(for kind: MediaID.Kind) async throws -> [MediaGenre] { [] }
}

private actor DetailLoadGate {
    private var pending: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    func pause() async {
        await withCheckedContinuation { continuation in
            pending = continuation
            observer?.resume()
            observer = nil
        }
    }
    func waitUntilRequested() async {
        if pending != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
    func complete() { pending?.resume(); pending = nil }
}
