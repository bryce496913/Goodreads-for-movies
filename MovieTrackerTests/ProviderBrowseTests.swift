import SwiftData
import XCTest
@testable import MovieTracker

@MainActor
final class ProviderBrowseTests: XCTestCase {
    func testCategoriesForBothMediaKindsAndMissingArtwork() async {
        let service = BrowseFixtureService()
        let model = ProviderBrowseModel(service: service)
        for kind in MediaID.Kind.allCases {
            for category in [ProviderBrowseModel.Category.trending, .popular, .topRated] {
                model.kind = kind; model.category = category
                await model.load()
                XCTAssertEqual(model.phase, .loaded)
                XCTAssertEqual(model.items.count, 1)
                XCTAssertEqual(model.items.first?.id.kind, kind)
                XCTAssertNil(model.items.first?.posterReference)
                XCTAssertNil(model.items.first?.year)
                XCTAssertNil(model.imageResolver)
            }
        }
        let calls = await service.calls
        XCTAssertEqual(calls.count, 6)
    }

    func testGenreSelectionIsTypedAndRequiresChoice() async {
        let service = BrowseFixtureService()
        let model = ProviderBrowseModel(service: service)
        model.category = .genres
        await model.load()
        XCTAssertEqual(model.phase, .chooseGenre)
        XCTAssertEqual(model.genres.first?.id, "movie-genre")
        var calls = await service.calls
        XCTAssertTrue(calls.isEmpty)
        model.selectedGenre = "movie-genre"
        await model.load()
        calls = await service.calls
        XCTAssertEqual(calls.last?.0.category, .genre("movie-genre"))
        model.kind = .tvShow
        await model.load()
        XCTAssertNil(model.selectedGenre)
        XCTAssertEqual(model.genres.first?.id, "tv-genre")
        XCTAssertTrue(model.items.isEmpty)
        model.selectedGenre = "tv-genre"
        await model.load()
        calls = await service.calls
        XCTAssertEqual(calls.last?.0, MetadataBrowseRequest(kind: .tvShow, category: .genre("tv-genre")))
    }

    func testPagingDeduplicatesAndDoubleTapDoesNotFetchTwice() async {
        let service = BrowseFixtureService()
        let model = ProviderBrowseModel(service: service)
        model.category = .popular
        await model.load()
        XCTAssertEqual(model.nextPage, 2)
        model.loadMore(); model.loadMore()
        await model.waitForPage()
        XCTAssertEqual(model.items.map(\.id.value), ["fixture:1", "fixture:2"])
        XCTAssertNil(model.nextPage)
        let calls = await service.calls
        XCTAssertEqual(calls.map(\.1), [1, 2])
    }

    func testPageFailurePreservesResultsAndCanRetrySamePage() async {
        let service = BrowseFixtureService()
        let model = ProviderBrowseModel(service: service)
        model.category = .popular
        await model.load()
        await service.setFailure(.offline)
        model.loadMore(); await model.waitForPage()
        XCTAssertEqual(model.pageError, .offline)
        XCTAssertEqual(model.items.count, 1)
        XCTAssertEqual(model.nextPage, 2)
        await service.setFailure(nil)
        model.loadMore(); await model.waitForPage()
        XCTAssertNil(model.pageError)
        XCTAssertEqual(model.items.count, 2)
        let pages = await service.calls.map(\.1)
        XCTAssertEqual(pages, [1, 2, 2])
    }

    func testTrendingAndSimilarAreBoundedPreviews() async {
        let service = BrowseFixtureService()
        let trending = ProviderBrowseModel(service: service)
        await trending.load()
        XCTAssertNil(trending.nextPage)
        let source = MediaID(kind: .movie, value: "fixture:1")
        let similar = ProviderBrowseModel(service: service, relatedTo: source)
        await similar.load()
        XCTAssertEqual(similar.items.map(\.id.value), ["fixture:2"]) // Source excluded.
        XCTAssertNil(similar.nextPage)
        let calls = await service.calls
        XCTAssertEqual(calls.last?.0.category, .similar(source))
    }

    func testBrowseCacheSurvivesTitleSearchModeAndDoesNotChangeSearch() async {
        let service = BrowseFixtureService()
        let search = SearchModel(service: service, debounce: {})
        await search.browseModel.load()
        search.query = "sample"
        await search.waitForSearch()
        XCTAssertEqual(search.phase, .loaded)
        search.query = ""
        await search.waitForSearch()
        await search.browseModel.load()
        let calls = await service.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(search.phase, .idle)
        XCTAssertEqual(search.browseModel.items.count, 1)
    }

    func testFailuresAreDistinctFromEmptyAndRetryIsExplicit() async {
        for error in [MetadataError.offline, .unauthorized, .rateLimited(retryAfter: "30"), .timedOut, .unsupportedDiscovery] {
            let service = BrowseFixtureService(failure: error)
            let model = ProviderBrowseModel(service: service)
            await model.load()
            XCTAssertEqual(model.phase, .failed(error))
            XCTAssertTrue(model.items.isEmpty)
            let calls = await service.calls
            XCTAssertEqual(calls.count, 1)
        }
        let model = ProviderBrowseModel(service: BrowseFixtureService(empty: true))
        await model.load()
        XCTAssertEqual(model.phase, .loaded)
        XCTAssertTrue(model.items.isEmpty)
        let missing = ProviderBrowseModel(service: nil)
        await missing.load()
        XCTAssertEqual(missing.phase, .failed(.missingCredential))
    }

    func testExpiryDoesNotRenewAndCredentialChangeClearsMemory() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let model = ProviderBrowseModel(service: BrowseFixtureService(tmdbDate: now), clock: { now })
        await model.load()
        XCTAssertEqual(model.items.first?.metadataRetrievedAt, now)
        model.expire(at: now.addingTimeInterval(MetadataPolicy.retention))
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertEqual(model.phase, .failed(.metadataExpired))
        await model.load()
        let oldEpoch = MetadataRuntimeGate.credentialEpoch
        defer { MetadataRuntimeGate.credentialEpoch = oldEpoch }
        MetadataRuntimeGate.credentialEpoch += 1
        XCTAssertTrue(model.items.isEmpty)
        model.invalidateSessionIfChanged()
        XCTAssertEqual(model.phase, .failed(.providerSessionChanged))
        XCTAssertTrue(model.genres.isEmpty)
    }

    func testBrowsingAndRelatedNavigationNeverCreatePersonalRecords() async throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let store = LibraryStore(container: container)
        let search = SearchModel(service: BrowseFixtureService())
        await search.browseModel.load()
        let destination = try XCTUnwrap(search.browseModel.items.first?.destination)
        let details = search.detailModel(for: destination)
        await details.relatedTitles.load()
        XCTAssertEqual(store.entries.count, 0)
        XCTAssertEqual(store.viewingEvents.count, 0)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<StoredLibraryEntry>()), 0)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<StoredPersonalReview>()), 0)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<StoredViewingEvent>()), 0)
    }

    func testCancelledLoadEndsAndCanRecover() async {
        let service = BrowseFixtureService(failure: .offline)
        let model = ProviderBrowseModel(service: service)
        let task = Task { await model.load() }
        task.cancel(); await task.value
        XCTAssertEqual(model.phase, .cancelled)
        model.replaceService(BrowseFixtureService())
        await model.load()
        XCTAssertEqual(model.phase, .loaded)
    }

    func testOldResponseCannotReplaceNewMediaSelection() async {
        let service = DelayedBrowseService()
        let model = ProviderBrowseModel(service: service, relatedTo: nil)
        let old = Task { await model.load() }
        await service.waitForCalls(1)
        model.kind = .tvShow
        let current = Task { await model.load() }
        await service.waitForCalls(2)
        await service.finish(1)
        await current.value
        await service.finish(0)
        await old.value
        XCTAssertEqual(model.items.first?.id.kind, .tvShow)
        XCTAssertEqual(model.phase, .loaded)
    }

    func testObsoletePageCannotAppendAfterCategorySwitch() async {
        let service = DelayedBrowseService()
        let model = ProviderBrowseModel(service: service)
        model.category = .popular
        let initial = Task { await model.load() }
        await service.waitForCalls(1); await service.finish(0); await initial.value
        model.loadMore()
        await service.waitForCalls(2)
        model.kind = .tvShow
        let replacement = Task { await model.load() }
        await service.waitForCalls(3); await service.finish(2); await replacement.value
        await service.finish(1)
        // Synchronize with the cancelled page task without timing-based waits.
        await model.waitForPage()
        XCTAssertEqual(model.items.map(\.id.kind), [.tvShow])
    }
}

private actor BrowseFixtureService: MediaMetadataService {
    var calls: [(MetadataBrowseRequest, Int)] = []
    var failure: MetadataError?
    let empty: Bool
    let tmdbDate: Date?
    init(failure: MetadataError? = nil, empty: Bool = false, tmdbDate: Date? = nil) {
        self.failure = failure; self.empty = empty; self.tmdbDate = tmdbDate
    }
    func setFailure(_ error: MetadataError?) { failure = error }
    func browse(_ request: MetadataBrowseRequest, page: Int) async throws -> MetadataPage<MediaSearchResult> {
        calls.append((request, page))
        if let failure { throw failure }
        let result = fixturePage(request.kind, page: page, empty: empty, date: tmdbDate)
        if case .similar = request.category {
            return MetadataPage(items: fixturePage(request.kind, page: 2).items, page: page, totalPages: 2, totalResults: 3)
        }
        return result
    }
    func genres(for kind: MediaID.Kind) async throws -> [MediaGenre] { [MediaGenre(id: kind == .movie ? "movie-genre" : "tv-genre", name: "Genre")] }
    func imageResolver() async throws -> MetadataImageResolver { throw MetadataError.invalidPayload }
    func searchAll(query: String, page: Int) async throws -> MetadataPage<MediaSearchResult> { fixturePage(.movie, page: page) }
    func searchMovies(query: String, page: Int) async throws -> MetadataPage<Movie> { throw MetadataError.unsupportedDiscovery }
    func searchTVShows(query: String, page: Int) async throws -> MetadataPage<TVShow> { throw MetadataError.unsupportedDiscovery }
    func movieDetails(id: MediaID) async throws -> Movie { throw MetadataError.notFound }
    func tvShowDetails(id: MediaID) async throws -> TVShow { throw MetadataError.notFound }
}

private func fixturePage(_ kind: MediaID.Kind, page: Int, empty: Bool = false, date: Date? = nil) -> MetadataPage<MediaSearchResult> {
    let ids = page == 1 ? [1] : [1, 2]
    let values: [MediaSearchResult] = empty ? [] : ids.map { id in
        let value = "\(date == nil ? "fixture" : "tmdb"):\(id)"
        return kind == .movie ? .movie(Movie(id: value, title: "Story \(id)", metadataRetrievedAt: date))
            : .tvShow(TVShow(id: value, title: "Story \(id)", metadataRetrievedAt: date))
    }
    return MetadataPage(items: values, page: page, totalPages: empty ? 0 : 2, totalResults: empty ? 0 : 3)
}

/// Deliberately ignores cancellation to verify the model's generation checks.
private actor DelayedBrowseService: MediaMetadataService {
    private var requests: [(MediaID.Kind, Int, CheckedContinuation<MetadataPage<MediaSearchResult>, Error>)] = []
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    func waitForCalls(_ count: Int) async {
        if requests.count >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
    func finish(_ index: Int) {
        let entry = requests[index]
        entry.2.resume(returning: fixturePage(entry.0, page: entry.1))
    }
    func browse(_ request: MetadataBrowseRequest, page: Int) async throws -> MetadataPage<MediaSearchResult> {
        try await withCheckedThrowingContinuation { continuation in
            requests.append((request.kind, page, continuation))
            let ready = waiters.filter { requests.count >= $0.0 }
            waiters.removeAll { requests.count >= $0.0 }
            ready.forEach { $0.1.resume() }
        }
    }
    func genres(for kind: MediaID.Kind) async throws -> [MediaGenre] { [] }
    func imageResolver() async throws -> MetadataImageResolver { throw MetadataError.invalidPayload }
    func searchAll(query: String, page: Int) async throws -> MetadataPage<MediaSearchResult> { throw MetadataError.unsupportedDiscovery }
    func searchMovies(query: String, page: Int) async throws -> MetadataPage<Movie> { throw MetadataError.unsupportedDiscovery }
    func searchTVShows(query: String, page: Int) async throws -> MetadataPage<TVShow> { throw MetadataError.unsupportedDiscovery }
    func movieDetails(id: MediaID) async throws -> Movie { throw MetadataError.notFound }
    func tvShowDetails(id: MediaID) async throws -> TVShow { throw MetadataError.notFound }
}
