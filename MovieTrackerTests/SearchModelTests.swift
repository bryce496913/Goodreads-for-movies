import XCTest
@testable import MovieTracker

final class SearchModelTests: XCTestCase {
    @MainActor
    func testQueryNormalizationAndEmptyQueries() async {
        XCTAssertEqual(SearchModel.normalizedQuery("  movie \n  title\t"), "movie title")
        let service = ControlledSearchService()
        let model = SearchModel(service: service, debounce: {})
        model.query = "  \n "
        await model.waitForSearch()
        XCTAssertEqual(model.phase, .idle)
        let count = await service.calls.count
        XCTAssertEqual(count, 0)
    }

    @MainActor
    func testDebounceWaitsAndOnlyLatestTypingIsSent() async {
        let service = ControlledSearchService()
        let gate = SearchDebounceGate()
        let model = SearchModel(service: service, debounce: { try await gate.pause() })
        model.query = "s"
        await gate.waitForCount(1)
        model.query = "st"
        await gate.waitForCount(2)
        let before = await service.calls.count
        XCTAssertEqual(before, 0)
        await gate.releaseAll()
        await service.waitForCalls(1)
        let calls = await service.calls
        XCTAssertEqual(calls.map(\.query), ["st"])
        await service.succeed(0, items: [])
        await model.waitForSearch()
        XCTAssertEqual(model.phase, .loaded)
    }

    @MainActor
    func testStaleResponseCannotReplaceNewResults() async {
        let service = ControlledSearchService()
        let model = SearchModel(service: service, debounce: {})
        model.query = "old"
        await service.waitForCalls(1)
        let obsoleteTask = model.searchTask
        model.query = "new"
        XCTAssertTrue(obsoleteTask?.isCancelled == true)
        await service.waitForCalls(2)
        await service.succeed(1, items: [.movie(Movie(id: "new", title: "New"))])
        await model.waitForSearch()
        await service.succeed(0, items: [.movie(Movie(id: "old", title: "Old"))])
        await obsoleteTask?.value
        XCTAssertEqual(model.items.map(\.title), ["New"])
        XCTAssertEqual(model.phase, .loaded)
    }

    @MainActor
    func testClearingQueryImmediatelyClearsAndInvalidatesRequest() async {
        let service = ControlledSearchService()
        let model = SearchModel(service: service, debounce: {})
        model.query = "movie"
        await service.waitForCalls(1)
        model.query = ""
        XCTAssertEqual(model.phase, .idle)
        XCTAssertTrue(model.items.isEmpty)
        await service.succeed(0, items: [.movie(Movie(id: "old", title: "Old"))])
        await model.waitForSearch()
        XCTAssertEqual(model.phase, .idle)
        XCTAssertTrue(model.items.isEmpty)
    }

    @MainActor
    func testFiltersSelectCorrectEndpointAndKeepMovieTVSeparate() async {
        let service = ControlledSearchService()
        let model = SearchModel(service: service, debounce: {})
        let movie = Movie(id: "same", title: "Same title")
        let show = TVShow(id: "same", title: "Same title")
        model.query = "title"
        await service.waitForCalls(1)
        await service.succeed(0, items: [.movie(movie), .tvShow(show)])
        await model.waitForSearch()
        XCTAssertEqual(model.items.count, 2)
        XCTAssertNotEqual(model.items[0].id, model.items[1].id)
        model.filter = .movies
        await service.waitForCalls(2)
        await service.succeed(1, items: [.movie(movie)])
        await model.waitForSearch()
        XCTAssertEqual(model.items.map(\.mediaType), ["Movie"])
        model.filter = .tvShows
        await service.waitForCalls(3)
        await service.succeed(2, items: [.tvShow(show)])
        await model.waitForSearch()
        XCTAssertEqual(model.items.map(\.mediaType), ["TV Show"])
        let filters = await service.calls.map(\.filter)
        XCTAssertEqual(filters, [.all, .movies, .tvShows])
    }

    @MainActor
    func testPaginationDeduplicatesAndGuardsRepeatedLoad() async {
        let service = ControlledSearchService()
        let model = SearchModel(service: service, debounce: {})
        let movie = MediaSearchResult.movie(Movie(id: "1", title: "One"))
        let show = MediaSearchResult.tvShow(TVShow(id: "1", title: "One"))
        model.query = "one"
        await service.waitForCalls(1)
        await service.succeed(0, items: [movie, movie], totalPages: 2)
        await model.waitForSearch()
        XCTAssertEqual(model.items.count, 1)
        model.loadMore()
        model.loadMore()
        await service.waitForCalls(2)
        let before = await service.calls.count
        XCTAssertEqual(before, 2)
        await service.succeed(1, items: [movie, show], totalPages: 2)
        await model.waitForPage()
        XCTAssertEqual(model.items.count, 2)
        XCTAssertNil(model.nextPage)
        model.loadMore()
        let after = await service.calls.count
        XCTAssertEqual(after, 2)
    }

    @MainActor
    func testFirstPageErrorRetryAndEmptyStateAreDistinct() async {
        let service = ControlledSearchService()
        let model = SearchModel(service: service, debounce: {})
        model.query = "query"
        await service.waitForCalls(1)
        await service.fail(0, error: .offline)
        await model.waitForSearch()
        XCTAssertEqual(model.phase, .failed(.offline))
        model.retry()
        await service.waitForCalls(2)
        await service.succeed(1, items: [])
        await model.waitForSearch()
        XCTAssertEqual(model.phase, .loaded)
        XCTAssertTrue(model.items.isEmpty)
    }

    @MainActor
    func testPageErrorRetainsResultsAndRetriesOnlyOnAction() async {
        let service = ControlledSearchService()
        let model = SearchModel(service: service, debounce: {})
        model.query = "query"
        await service.waitForCalls(1)
        await service.succeed(0, items: [.movie(Movie(id: "1", title: "One"))], totalPages: 2)
        await model.waitForSearch()
        model.loadMore()
        await service.waitForCalls(2)
        await service.fail(1, error: .rateLimited(retryAfter: "60"))
        await model.waitForPage()
        XCTAssertEqual(model.items.count, 1)
        XCTAssertEqual(model.phase, .loaded)
        XCTAssertEqual(model.pageError, .rateLimited(retryAfter: "60"))
        let count = await service.calls.count
        XCTAssertEqual(count, 2)
        model.loadMore()
        await service.waitForCalls(3)
        await service.succeed(2, items: [], totalPages: 2)
        await model.waitForPage()
        XCTAssertNil(model.pageError)
        XCTAssertNil(model.nextPage)
    }

    @MainActor
    func testObsoletePageCannotAppendAfterQueryChange() async {
        let service = ControlledSearchService()
        let model = SearchModel(service: service, debounce: {})
        model.query = "first"
        await service.waitForCalls(1)
        await service.succeed(0, items: [.movie(Movie(id: "1", title: "First"))], totalPages: 2)
        await model.waitForSearch()
        model.loadMore()
        await service.waitForCalls(2)
        let obsoletePage = model.pageTask
        model.query = "second"
        await service.waitForCalls(3)
        await service.succeed(2, items: [.movie(Movie(id: "2", title: "Second"))])
        await model.waitForSearch()
        await service.succeed(1, items: [.movie(Movie(id: "old", title: "Obsolete"))], totalPages: 2)
        await obsoletePage?.value
        XCTAssertEqual(model.items.map(\.title), ["Second"])
        XCTAssertNil(model.nextPage)
        XCTAssertFalse(model.isLoadingMore)
    }

    @MainActor
    func testCurrentRequestCancellationDoesNotLeaveLoadingState() async {
        let service = ControlledSearchService()
        let model = SearchModel(service: service, debounce: {})
        model.query = "query"
        await service.waitForCalls(1)
        await service.cancel(0)
        await model.waitForSearch()
        XCTAssertEqual(model.phase, .cancelled)
        XCTAssertTrue(model.items.isEmpty)
    }

    @MainActor
    func testNormalizedEquivalentQueryDoesNotRefetch() async {
        let service = ControlledSearchService()
        let model = SearchModel(service: service, debounce: {})
        model.query = "movie title"
        await service.waitForCalls(1)
        await service.succeed(0, items: [])
        await model.waitForSearch()
        model.query = "  movie   title  "
        await model.waitForSearch()
        let count = await service.calls.count
        XCTAssertEqual(count, 1)
    }

    @MainActor
    func testMissingConfigurationShowsFailureWithoutFakeData() async {
        let model = SearchModel(service: nil, debounce: {})
        model.query = "movie"
        await model.waitForSearch()
        XCTAssertEqual(model.phase, .failed(.missingCredential))
        XCTAssertTrue(model.items.isEmpty)
    }

    @MainActor
    func testYearAndTypedDestinationUseCorrectIdentity() {
        let date = Date(timeIntervalSince1970: 1_704_067_200) // January 1 2024 UTC.
        let item = SearchItem(.tvShow(TVShow(id: "1", title: "Show", firstAirDate: date)))
        XCTAssertEqual(item.year, 2024)
        XCTAssertEqual(item.destination.id, MediaID(kind: .tvShow, value: "1"))
        XCTAssertEqual(item.destination.title, "Show")
        XCTAssertNil(SearchItem(.movie(Movie(id: "1", title: "Unknown"))).year)
    }
}

private actor ControlledSearchService: MediaMetadataService {
    struct Call: Sendable { let filter: SearchFilter; let query: String; let page: Int }
    private(set) var calls: [Call] = []
    private var pending: [Int: CheckedContinuation<MetadataPage<MediaSearchResult>, Error>] = [:]
    private var observers: [(Int, CheckedContinuation<Void, Never>)] = []

    func searchAll(query: String, page: Int) async throws -> MetadataPage<MediaSearchResult> {
        try await request(.all, query: query, page: page)
    }
    func searchMovies(query: String, page: Int) async throws -> MetadataPage<Movie> {
        let value = try await request(.movies, query: query, page: page)
        return MetadataPage(items: value.items.compactMap { if case .movie(let movie) = $0 { movie } else { nil } },
                            page: value.page, totalPages: value.totalPages, totalResults: value.totalResults)
    }
    func searchTVShows(query: String, page: Int) async throws -> MetadataPage<TVShow> {
        let value = try await request(.tvShows, query: query, page: page)
        return MetadataPage(items: value.items.compactMap { if case .tvShow(let show) = $0 { show } else { nil } },
                            page: value.page, totalPages: value.totalPages, totalResults: value.totalResults)
    }
    private func request(_ filter: SearchFilter, query: String, page: Int) async throws -> MetadataPage<MediaSearchResult> {
        let index = calls.count
        calls.append(Call(filter: filter, query: query, page: page))
        return try await withCheckedThrowingContinuation { continuation in
            pending[index] = continuation
            for (count, observer) in observers where calls.count >= count { observer.resume() }
            observers.removeAll { calls.count >= $0.0 }
        }
    }
    func waitForCalls(_ count: Int) async {
        if calls.count >= count { return }
        await withCheckedContinuation { observers.append((count, $0)) }
    }
    func succeed(_ index: Int, items: [MediaSearchResult], totalPages: Int = 1) {
        pending.removeValue(forKey: index)?.resume(returning: MetadataPage(
            items: items, page: calls[index].page, totalPages: totalPages, totalResults: items.count
        ))
    }
    func cancel(_ index: Int) { pending.removeValue(forKey: index)?.resume(throwing: CancellationError()) }
    func fail(_ index: Int, error: MetadataError) { pending.removeValue(forKey: index)?.resume(throwing: error) }
    func movieDetails(id: MediaID) async throws -> Movie { throw MetadataError.invalidIdentifier }
    func tvShowDetails(id: MediaID) async throws -> TVShow { throw MetadataError.invalidIdentifier }
    func genres(for kind: MediaID.Kind) async throws -> [MediaGenre] { [] }
    func imageResolver() async throws -> MetadataImageResolver { throw MetadataError.invalidPayload }
}

private actor SearchDebounceGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var observers: [(Int, CheckedContinuation<Void, Never>)] = []
    func pause() async throws {
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
            for (count, observer) in observers where waiters.count >= count { observer.resume() }
            observers.removeAll { waiters.count >= $0.0 }
        }
        try Task.checkCancellation()
    }
    func waitForCount(_ count: Int) async {
        if waiters.count >= count { return }
        await withCheckedContinuation { observers.append((count, $0)) }
    }
    func releaseAll() {
        let pending = waiters
        waiters = []
        pending.forEach { $0.resume() }
    }
}
