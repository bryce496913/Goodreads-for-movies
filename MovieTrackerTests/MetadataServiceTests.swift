import XCTest
@testable import MovieTracker

final class MetadataServiceTests: XCTestCase {
    @MainActor
    func testMovieSearchMapsMetadataAndEncodesRequest() async throws {
        let stub = StubMetadataTransport([.success(response(#"{"page":1,"total_pages":2,"total_results":21,"results":[{"id":123,"title":"A Movie","overview":"Story","release_date":"2024-02-29","poster_path":"/poster.jpg","genre_ids":[18]}]}"#))])
        let service = try makeService(stub)
        let page = try await service.searchMovies(query: "a & b", page: 1)
        let movie = try XCTUnwrap(page.items.first)
        XCTAssertEqual(movie.id, MediaID(kind: .movie, value: "tmdb:123"))
        XCTAssertEqual(movie.title, "A Movie")
        XCTAssertEqual(movie.overview, "Story")
        XCTAssertNotNil(movie.releaseDate)
        XCTAssertEqual(movie.posterReference, "/poster.jpg")
        XCTAssertEqual(movie.genreIDs, ["tmdb:18"])
        XCTAssertEqual(page.nextPage, 2)
        let requests = await stub.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.host, "api.themoviedb.org")
        XCTAssertEqual(request.url?.path, "/3/search/movie")
        let components = try XCTUnwrap(URLComponents(url: XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.first { $0.name == "query" }?.value, "a & b")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer local-test-credential")
        XCTAssertFalse(request.url?.absoluteString.contains("local-test-credential") ?? true)
    }

    @MainActor
    func testTVSearchAcceptsMissingMetadata() async throws {
        let stub = StubMetadataTransport([.success(response(#"{"page":1,"total_pages":1,"total_results":1,"results":[{"id":123,"name":"A Show","first_air_date":"","poster_path":null}]}"#))])
        let result = try await makeService(stub).searchTVShows(query: "show")
        let show = try XCTUnwrap(result.items.first)
        XCTAssertEqual(show.id, MediaID(kind: .tvShow, value: "tmdb:123"))
        XCTAssertEqual(show.overview, "")
        XCTAssertNil(show.firstAirDate)
        XCTAssertNil(show.posterReference)
        XCTAssertNil(show.seasonCount)
        XCTAssertNil(show.episodeRuntimeMinutes)
        XCTAssertNil(result.nextPage)
    }

    @MainActor
    func testCombinedSearchSeparatesMediaAndExcludesPeople() async throws {
        let stub = StubMetadataTransport([.success(response(#"{"page":1,"total_pages":1,"total_results":3,"results":[{"id":123,"title":"Movie","media_type":"movie"},{"id":123,"name":"Show","media_type":"tv"},{"id":7,"name":"Person","media_type":"person"}]}"#))])
        let page = try await makeService(stub).searchAll(query: "title")
        XCTAssertEqual(page.items.count, 2)
        guard case .movie(let movie) = page.items[0], case .tvShow(let show) = page.items[1] else {
            return XCTFail("Expected movie and TV results")
        }
        XCTAssertNotEqual(movie.id, show.id)
        XCTAssertEqual(Set([movie.id, show.id]).count, 2)
        // Pagination totals remain provider totals, including people filtered from displayed items.
        XCTAssertEqual(page.totalResults, 3)
    }

    @MainActor
    func testDetailsMapRuntimeBackdropAndGenres() async throws {
        let stub = StubMetadataTransport([
            .success(response(#"{"id":123,"title":"Movie","runtime":0,"release_date":"2023-02-30","backdrop_path":"/back.jpg","genres":[{"id":18,"name":"Drama"}]}"#)),
            .success(response(#"{"id":123,"name":"Show","number_of_seasons":4,"episode_run_time":[0,45],"backdrop_path":"/tv.jpg"}"#))
        ])
        let service = try makeService(stub)
        let movie = try await service.movieDetails(id: MediaID(kind: .movie, value: "tmdb:123"))
        XCTAssertNil(movie.runtimeMinutes)
        XCTAssertNil(movie.releaseDate)
        XCTAssertNil(movie.posterReference)
        XCTAssertEqual(movie.backdropReference, "/back.jpg")
        XCTAssertEqual(movie.genreIDs, ["tmdb:18"])
        let show = try await service.tvShowDetails(id: MediaID(kind: .tvShow, value: "tmdb:123"))
        XCTAssertEqual(show.seasonCount, 4)
        XCTAssertEqual(show.episodeRuntimeMinutes, 45)
        XCTAssertEqual(show.backdropReference, "/tv.jpg")
        let paths = await stub.requests.compactMap { $0.url?.path }
        XCTAssertEqual(paths, ["/3/movie/123", "/3/tv/123"])
    }

    @MainActor
    func testGenreEndpoints() async throws {
        let payload = response(#"{"genres":[{"id":18,"name":"Drama"}]}"#)
        let stub = StubMetadataTransport([.success(payload), .success(payload)])
        let service = try makeService(stub)
        let movie = try await service.genres(for: .movie)
        let tv = try await service.genres(for: .tvShow)
        XCTAssertEqual(movie, [MediaGenre(id: "tmdb:18", name: "Drama")])
        XCTAssertEqual(movie, tv)
        let paths = await stub.requests.compactMap { $0.url?.path }
        XCTAssertEqual(paths, ["/3/genre/movie/list", "/3/genre/tv/list"])
    }

    @MainActor
    func testMalformedPayloadsAreRejected() async throws {
        for payload in ["not JSON", "{}",
            #"{"page":1,"total_pages":1,"total_results":1,"results":[{"id":-1,"title":"Invalid"}]}"#,
            #"{"page":1,"total_pages":1,"total_results":1,"results":[{"id":1,"title":"  "}]}"#,
            #"{"page":2,"total_pages":1,"total_results":1,"results":[]}"#,
            #"{"page":1,"total_pages":1,"total_results":1,"results":[{"title":"Missing ID"}]}"#
        ] {
            let service = try makeService(StubMetadataTransport([.success(response(payload))]))
            await assertError(.invalidPayload) { _ = try await service.searchMovies(query: "a") }
        }
    }

    @MainActor
    func testHTTPFailuresDoNotRetry() async throws {
        let cases: [(Int, MetadataError)] = [
            (401, .unauthorized), (403, .unauthorized), (429, .rateLimited(retryAfter: "60")),
            (503, .server(status: 503)), (404, .http(status: 404)), (302, .http(status: 302))
        ]
        for (status, error) in cases {
            let stub = StubMetadataTransport([.success(response("{}", status: status, retryAfter: "60"))])
            let service = try makeService(stub)
            await assertError(error) { _ = try await service.searchMovies(query: "a") }
            let count = await stub.requests.count
            XCTAssertEqual(count, 1)
        }
    }

    @MainActor
    func testNetworkAndEmptyResponseErrors() async throws {
        for (code, expected) in [(URLError.timedOut, MetadataError.timedOut),
                                  (.notConnectedToInternet, .offline), (.networkConnectionLost, .offline),
                                  (.cannotConnectToHost, .transport)] {
            let service = try makeService(StubMetadataTransport([.failure(URLError(code))]))
            await assertError(expected) { _ = try await service.searchMovies(query: "a") }
        }
        let service = try makeService(StubMetadataTransport([.success(response(""))]))
        await assertError(.emptyResponse) { _ = try await service.searchMovies(query: "a") }
    }

    @MainActor
    func testPaginationAndValidationBeforeNetwork() async throws {
        let stub = StubMetadataTransport([
            .success(response(#"{"page":1,"total_pages":0,"total_results":0,"results":[]}"#)),
            .success(response(#"{"page":500,"total_pages":900,"total_results":18000,"results":[]}"#))
        ])
        let service = try makeService(stub)
        await assertError(.invalidPage) { _ = try await service.searchMovies(query: "a", page: 0) }
        await assertError(.invalidPage) { _ = try await service.searchMovies(query: "a", page: 501) }
        await assertError(.invalidQuery) { _ = try await service.searchMovies(query: "  ") }
        await assertError(.invalidIdentifier) {
            _ = try await service.movieDetails(id: MediaID(kind: .tvShow, value: "tmdb:123"))
        }
        await assertError(.invalidIdentifier) {
            _ = try await service.movieDetails(id: MediaID(kind: .movie, value: "other:123"))
        }
        let empty = try await service.searchMovies(query: "none")
        XCTAssertTrue(empty.items.isEmpty)
        XCTAssertNil(empty.nextPage)
        let last = try await service.searchMovies(query: "a", page: 500)
        XCTAssertNil(last.nextPage)
        let count = await stub.requests.count
        XCTAssertEqual(count, 2)
    }

    @MainActor
    func testCancellationRejectsLateSuccessfulResponse() async throws {
        let stub = SuspendedMetadataTransport()
        let service = try makeService(stub)
        let task = Task { try await service.searchMovies(query: "old query") }
        await stub.waitUntilRequested()
        task.cancel()
        await stub.complete(response(#"{"page":1,"total_pages":0,"total_results":0,"results":[]}"#))
        do {
            _ = try await task.value
            XCTFail("A canceled request must not return a stale result")
        } catch is CancellationError {
            // Expected even if a transport finishes successfully after cancellation.
        } catch { XCTFail("Expected cancellation, received \(error)") }
    }

    @MainActor
    func testCanceledTransportErrorIsCancellation() async throws {
        let service = try makeService(StubMetadataTransport([.failure(URLError(.cancelled))]))
        do {
            _ = try await service.searchMovies(query: "a")
            XCTFail("Expected cancellation")
        } catch is CancellationError {} catch { XCTFail("Expected cancellation") }
    }

    @MainActor
    func testImagesUseConfigurationSizesAndRejectUnsafePaths() async throws {
        let stub = StubMetadataTransport([.success(response(#"{"images":{"secure_base_url":"https://image.tmdb.org/t/p/","poster_sizes":["w185","w342"],"backdrop_sizes":["w300","w780"]}}"#))])
        let service = try makeService(stub)
        let resolver = try await service.imageResolver()
        _ = try await service.imageResolver()
        XCTAssertEqual(resolver.posterURL(reference: "/poster.jpg")?.absoluteString,
                       "https://image.tmdb.org/t/p/w185/poster.jpg")
        XCTAssertEqual(resolver.backdropURL(reference: "/back.jpg", size: .detail)?.absoluteString,
                       "https://image.tmdb.org/t/p/w780/back.jpg")
        XCTAssertNil(resolver.posterURL(reference: "/poster.jpg", size: .detail))
        for reference in [nil, "", "https://elsewhere/image.jpg", "//elsewhere/image.jpg", "/../image.jpg", "/%2e%2e", "/"] as [String?] {
            XCTAssertNil(resolver.posterURL(reference: reference))
        }
        let count = await stub.requests.count
        XCTAssertEqual(count, 1, "Configuration is reused; image content is not cached")
        XCTAssertThrowsError(try MetadataImageResolver(
            baseURL: XCTUnwrap(URL(string: "https://elsewhere.example/t/p/")), posterSizes: ["w185"], backdropSizes: []
        ))
    }

    @MainActor
    func testMovieDetailsMapsKnownRuntimeAndRejectsMismatchedID() async throws {
        let stub = StubMetadataTransport([
            .success(response(#"{"id":123,"title":"Movie","runtime":98}"#)),
            .success(response(#"{"id":999,"title":"Wrong movie"}"#))
        ])
        let service = try makeService(stub)
        let movie = try await service.movieDetails(id: MediaID(kind: .movie, value: "tmdb:123"))
        XCTAssertEqual(movie.runtimeMinutes, 98)
        await assertError(.invalidPayload) {
            _ = try await service.movieDetails(id: MediaID(kind: .movie, value: "tmdb:123"))
        }
    }

    @MainActor
    func testImageConfigurationCanBeRetriedAfterFailure() async throws {
        let stub = StubMetadataTransport([
            .success(response("{}", status: 503)),
            .success(response(#"{"images":{"secure_base_url":"https://image.tmdb.org/t/p/","poster_sizes":["w185"],"backdrop_sizes":["w300"]}}"#))
        ])
        let service = try makeService(stub)
        await assertError(.server(status: 503)) { _ = try await service.imageResolver() }
        let resolver = try await service.imageResolver()
        XCTAssertNotNil(resolver.posterURL(reference: "/image.jpg"))
        let count = await stub.requests.count
        XCTAssertEqual(count, 2, "Only an explicit second call retries configuration")
    }

    func testCredentialConfigurationRequiresLocalValue() throws {
        XCTAssertThrowsError(try TMDBConfiguration.localDevelopment(environment: [:]))
        XCTAssertThrowsError(try TMDBConfiguration(readAccessToken: "YOUR_TMDB_API_READ_ACCESS_TOKEN"))
        XCTAssertThrowsError(try TMDBConfiguration(readAccessToken: "bad\nheader"))
        _ = try TMDBConfiguration.localDevelopment(environment: ["TMDB_READ_ACCESS_TOKEN": "local-test-credential"])
    }

    @MainActor
    func testDetailGenresEpisodeCountsAndStatusMapping() async throws {
        let stub = StubMetadataTransport([.success(response(#"{"id":123,"name":"Series","number_of_seasons":3,"number_of_episodes":24,"status":"Returning Series","genres":[{"id":18,"name":"Drama"},{"id":18,"name":"Drama"}]}"#))])
        let show = try await makeService(stub).tvShowDetails(id: MediaID(kind: .tvShow, value: "tmdb:123"))
        XCTAssertEqual(show.episodeCount, 24)
        XCTAssertEqual(show.seasonCount, 3)
        XCTAssertEqual(show.seriesStatus, "Returning Series")
        XCTAssertEqual(show.genres, [MediaGenre(id: "tmdb:18", name: "Drama")])
    }

    @MainActor
    func testCastPreviewRoutesAndSkipsIncompletePeople() async throws {
        let payload = response(#"{"cast":[{"id":1,"name":"Performer","character":"Lead","order":0},{"id":1,"name":"Duplicate","order":1},{"id":2,"name":"Second","character":null},{"id":3,"name":" "},{"name":"No identifier"}]}"#)
        let stub = StubMetadataTransport([.success(payload), .success(payload)])
        let service = try makeService(stub)
        let movieCast = try await service.castPreview(for: MediaID(kind: .movie, value: "tmdb:123"))
        let tvCast = try await service.castPreview(for: MediaID(kind: .tvShow, value: "tmdb:123"))
        XCTAssertEqual(movieCast, tvCast)
        XCTAssertEqual(movieCast.count, 2)
        XCTAssertEqual(movieCast.first?.character, "Lead")
        XCTAssertNil(movieCast.last?.character)
        let paths = await stub.requests.compactMap { $0.url?.path }
        XCTAssertEqual(paths, ["/3/movie/123/credits", "/3/tv/123/credits"])
    }

    @MainActor
    func testUnknownTVCountsAndBlankStatusRemainUnavailable() async throws {
        let stub = StubMetadataTransport([.success(response(#"{"id":123,"name":"Series","number_of_seasons":0,"number_of_episodes":0,"status":" "}"#))])
        let show = try await makeService(stub).tvShowDetails(id: MediaID(kind: .tvShow, value: "tmdb:123"))
        XCTAssertNil(show.seasonCount)
        XCTAssertNil(show.episodeCount)
        XCTAssertNil(show.seriesStatus)
    }

    @MainActor
    func testTVSeasonCatalogMapsSpecialsAndUnknownCounts() async throws {
        let stub = StubMetadataTransport([.success(response(#"{"id":123,"name":"Series","seasons":[{"id":7,"season_number":0,"name":"Specials","episode_count":2},{"season_number":1,"name":null,"episode_count":null}]}"#))])
        let seasons = try await makeService(stub).tvSeasons(for: MediaID(kind: .tvShow, value: "tmdb:123"))
        XCTAssertEqual(seasons.map(\.number), [0, 1])
        XCTAssertEqual(seasons.first?.providerID, "tmdb:7")
        XCTAssertNil(seasons.last?.episodeCount)
        XCTAssertEqual(seasons.last?.name, "Season 1")
        let path = await stub.requests.first?.url?.path
        XCTAssertEqual(path, "/3/tv/123")
    }

    @MainActor
    func testSeasonEpisodesMapStableIDsAndMissingMetadata() async throws {
        let stub = StubMetadataTransport([.success(response(#"{"season_number":1,"name":"Season 1","episodes":[{"id":700,"episode_number":1,"season_number":1,"name":"Pilot","air_date":"2024-01-01","runtime":45},{"id":701,"episode_number":2,"name":null,"air_date":"","runtime":0}]}"#))])
        let id = MediaID(kind: .tvShow, value: "tmdb:123")
        let season = try await makeService(stub).tvSeasonDetails(for: id, number: 1)
        XCTAssertEqual(season.episodes.count, 2)
        XCTAssertEqual(season.episodes.first?.id, EpisodeID(seriesID: id, providerValue: "tmdb:700"))
        XCTAssertEqual(season.episodes.first?.runtimeMinutes, 45)
        XCTAssertEqual(season.episodes.last?.title, "Episode 2")
        XCTAssertNil(season.episodes.last?.airDate)
        XCTAssertNil(season.episodes.last?.runtimeMinutes)
        let path = await stub.requests.first?.url?.path
        XCTAssertEqual(path, "/3/tv/123/season/1")
    }

    @MainActor
    func testSeasonBoundariesAndDuplicateEpisodeIDsAreRejected() async throws {
        for payload in [#"{"season_number":2,"episodes":[]}"#,
            #"{"season_number":1,"episodes":[{"id":7,"episode_number":1},{"id":7,"episode_number":2}]}"#] {
            let service = try makeService(StubMetadataTransport([.success(response(payload))]))
            await assertError(.invalidPayload) { _ = try await service.tvSeasonDetails(for: MediaID(kind: .tvShow, value: "tmdb:123"), number: 1) }
        }
        let stub = StubMetadataTransport([])
        let service = try makeService(stub)
        await assertError(.invalidIdentifier) { _ = try await service.tvSeasonDetails(for: MediaID(kind: .movie, value: "tmdb:123"), number: 1) }
        await assertError(.invalidIdentifier) { _ = try await service.tvSeasonDetails(for: MediaID(kind: .tvShow, value: "tmdb:123"), number: -1) }
        let count = await stub.requests.count
        XCTAssertEqual(count, 0)
    }

    private func response(_ json: String, status: Int = 200, retryAfter: String? = nil) -> MetadataHTTPResponse {
        MetadataHTTPResponse(data: Data(json.utf8), status: status, retryAfter: retryAfter)
    }

    private func makeService(_ transport: any MetadataTransport) throws -> TMDBMetadataService {
        TMDBMetadataService(configuration: try TMDBConfiguration(readAccessToken: "local-test-credential"), transport: transport)
    }

    @MainActor
    private func assertError(_ expected: MetadataError, operation: () async throws -> Void) async {
        do { try await operation(); XCTFail("Expected \(expected)") }
        catch { XCTAssertEqual(error as? MetadataError, expected) }
    }
}

private actor StubMetadataTransport: MetadataTransport {
    private var responses: [Result<MetadataHTTPResponse, Error>]
    private(set) var requests: [URLRequest] = []

    init(_ responses: [Result<MetadataHTTPResponse, Error>]) { self.responses = responses }

    func send(_ request: URLRequest) async throws -> MetadataHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw MetadataError.transport }
        return try responses.removeFirst().get()
    }
}

private actor SuspendedMetadataTransport: MetadataTransport {
    private var pending: CheckedContinuation<MetadataHTTPResponse, Error>?
    private var observer: CheckedContinuation<Void, Never>?

    func send(_ request: URLRequest) async throws -> MetadataHTTPResponse {
        try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            observer?.resume()
            observer = nil
        }
    }

    func waitUntilRequested() async {
        if pending != nil { return }
        await withCheckedContinuation { observer = $0 }
    }

    func complete(_ response: MetadataHTTPResponse) {
        pending?.resume(returning: response)
        pending = nil
    }
}
