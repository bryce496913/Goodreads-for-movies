import SwiftData
import XCTest
@testable import MovieTracker

final class WatchDiscoveryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_767_225_600)
    private let drama = MediaGenre(id: "drama", name: "Drama")
    private let comedy = MediaGenre(id: "comedy", name: "Comedy")
    private func date(_ year: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt
        return calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
    }
    private func movie(_ id: String = "tmdb:1", year: Int? = 2020, minutes: Int? = 90, genres: [MediaGenre]? = nil, receipt: Date? = nil) -> MediaSearchResult {
        .movie(Movie(id: id, title: "Movie \(id)", releaseDate: year.map(date), genres: genres ?? [drama],
                     metadataRetrievedAt: receipt ?? now).withRuntime(minutes))
    }
    private func show(_ id: String = "tmdb:1") -> MediaSearchResult {
        .tvShow(TVShow(id: id, title: "Series \(id)", firstAirDate: date(2021), episodeRuntimeMinutes: 42, genres: [comedy], metadataRetrievedAt: now))
    }
    private func input(_ media: MediaSearchResult) throws -> DiscoveryInput {
        DiscoveryInput(id: SearchItem(media).id, library: nil, payloads: [try JSONEncoder().encode(media)], seriesPayloads: [])
    }
    private func pool(_ values: [MediaSearchResult]) throws -> [DiscoveryCandidate] {
        try WatchDiscoveryProjection.build(values.map(input), watchlist: false, at: now)
    }
    private func filter(_ values: [MediaSearchResult], _ options: DiscoveryFilters) throws -> [DiscoveryCandidate] {
        try WatchDiscoveryProjection.filter(pool(values), using: options, at: now)
    }
    @MainActor private func store() throws -> LibraryStore {
        let instant = now
        return LibraryStore(container: try PersistenceController.makeContainer(inMemory: true), clock: { instant })
    }
    @MainActor private func update(_ model: WatchDiscoveryModel, _ store: LibraryStore) async {
        await model.update(from: store, request: model.request(for: store))
    }

    @MainActor func testDefaultPoolOnlyWatchlistAndReadOnlyPicking() async throws {
        let store = try store(), model = WatchDiscoveryModel()
        try store.setStatus(.watchlist, media: movie())
        try store.setStatus(.watching, media: show())
        try store.setStatus(.watched, media: movie("tmdb:2"))
        try store.setPersonalRating(PersonalRating(halfStarUnits: 8), media: movie("tmdb:3"))
        let before = try store.capturePersonalBackup(at: now), revision = store.revision
        await update(model, store)
        XCTAssertEqual(model.candidates.map(\.id), [SearchItem(movie()).id])
        model.pick(request: model.request(for: store), index: { _ in 0 })
        XCTAssertEqual(model.picked?.id, SearchItem(movie()).id)
        XCTAssertTrue(model.showingResult)
        XCTAssertEqual(store.revision, revision)
        let after = try store.capturePersonalBackup(at: now)
        XCTAssertEqual(before.library, after.library); XCTAssertEqual(before.reviews, after.reviews)
        XCTAssertEqual(before.viewings, after.viewings); XCTAssertEqual(before.episodeProgress, after.episodeProgress)
    }

    func testMovieTVAndProviderNamespaceIdentityAreDistinct() throws {
        let values = [movie(), show(), movie("another:1")]
        XCTAssertEqual(try pool(values + values).count, 3)
        var options = DiscoveryFilters(); options.media = .movies
        XCTAssertEqual(try filter(values, options).count, 2)
        options.media = .tvShows
        XCTAssertEqual(try filter(values, options).map(\.id.kind), [.tvShow])
    }
    func testGenresUseORAndIgnoreMissingGenres() throws {
        let values = [movie(), show(), movie("tmdb:2", genres: [])]
        var options = DiscoveryFilters(); options.genres = [drama.id]
        XCTAssertEqual(try filter(values, options).count, 1)
        options.genres.insert(comedy.id)
        XCTAssertEqual(try filter(values, options).count, 2)
        options.genres = ["unavailable"]
        XCTAssertTrue(try filter(values, options).isEmpty)
    }
    func testYearRangeInclusiveBoundariesAndUnknownYear() throws {
        let values = [movie(year: 2019), movie("tmdb:2", year: 2020), movie("tmdb:3", year: 2021), movie("tmdb:4", year: nil)]
        var options = DiscoveryFilters(); options.firstYear = 2020; options.lastYear = 2021
        XCTAssertEqual(try filter(values, options).compactMap(\.item.year), [2020, 2021])
        options.lastYear = 2020
        XCTAssertEqual(try filter(values, options).count, 1)
        options.firstYear = nil
        XCTAssertEqual(try filter(values, options).count, 2)
    }
    func testRuntimeInclusiveBoundaryExcludesTVUnknownAndInvalidValues() throws {
        let values = [movie(minutes: 90), movie("tmdb:2", minutes: 91), show(), movie("tmdb:3", minutes: nil), movie("tmdb:4", minutes: 0), movie("tmdb:5", minutes: -1)]
        var options = DiscoveryFilters(); options.maximumMovieMinutes = 90
        XCTAssertEqual(try filter(values, options).map(\.id), [SearchItem(movie()).id])
        options.media = .tvShows
        XCTAssertTrue(try filter(values, options).isEmpty)
        options.maximumMovieMinutes = nil
        XCTAssertEqual(try filter(values, options).count, 1)
    }
    func testUnfilteredMissingMetadataRemainsEligible() throws {
        let unknown = DiscoveryInput(id: MediaID(kind: .movie, value: "tmdb:unknown"), library: nil, payloads: [], seriesPayloads: [])
        let result = try WatchDiscoveryProjection.build([unknown], watchlist: false, at: now)
        XCTAssertEqual(result.count, 1); XCTAssertFalse(result[0].metadataAvailable)
        XCTAssertNil(result[0].item.year); XCTAssertNil(result[0].movieMinutes); XCTAssertNil(result[0].posterURL)
        XCTAssertTrue(result[0].genres.isEmpty)
        var options = DiscoveryFilters(); options.firstYear = 1
        XCTAssertTrue(try WatchDiscoveryProjection.filter(result, using: options, at: now).isEmpty)
    }
    func testExpiredFutureAndMissingTMDBReceiptsStripAllProviderFields() throws {
        let expired = now.addingTimeInterval(-MetadataPolicy.retention)
        let future = now.addingTimeInterval(1)
        let missing = MediaSearchResult.movie(Movie(id: "tmdb:missing", title: "Must not display", runtimeMinutes: 100, genres: [drama]))
        let result = try pool([movie(receipt: expired), movie("tmdb:2", receipt: future), missing])
        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result.allSatisfy { !$0.metadataAvailable && $0.item.year == nil && $0.genres.isEmpty && $0.movieMinutes == nil })
        XCTAssertTrue(result.allSatisfy { $0.item.title.hasPrefix("Metadata unavailable") })
    }
    func testMissingRequiredMetadataDoesNotGetInventedFromOtherFields() throws {
        let values = [movie(year: nil, minutes: nil, genres: [])]
        XCTAssertEqual(try filter(values, DiscoveryFilters()).count, 1)
        var options = DiscoveryFilters(); options.genres = [drama.id]
        XCTAssertTrue(try filter(values, options).isEmpty)
        options.genres = []; options.lastYear = 9999
        XCTAssertTrue(try filter(values, options).isEmpty)
        options.lastYear = nil; options.maximumMovieMinutes = 180
        XCTAssertTrue(try filter(values, options).isEmpty)
    }
    func testInvalidRangesAreNotSilentlyNormalized() throws {
        for bounds in [(2021, 2020), (0, 2020), (2020, 10000)] {
            var options = DiscoveryFilters(); options.firstYear = bounds.0; options.lastYear = bounds.1
            XCTAssertFalse(options.isValid); XCTAssertTrue(try filter([movie()], options).isEmpty)
        }
    }
    func testCorruptAndMismatchedPayloadsAreNotUsed() throws {
        let id = SearchItem(movie()).id
        let raw = DiscoveryInput(id: id, library: nil, payloads: [Data("not JSON".utf8), try JSONEncoder().encode(show())], seriesPayloads: [])
        let result = try WatchDiscoveryProjection.build([raw], watchlist: false, at: now)
        XCTAssertEqual(result[0].id, id); XCTAssertFalse(result[0].metadataAvailable)
    }
    func testLatestValidMetadataWinsWithoutRenewingReceipt() throws {
        let older = movie(year: 2000, receipt: now.addingTimeInterval(-100))
        let newer = movie(year: 2020)
        let raw = DiscoveryInput(id: SearchItem(newer).id, library: nil, payloads: try [older, newer].map { try JSONEncoder().encode($0) }, seriesPayloads: [])
        let result = try WatchDiscoveryProjection.build([raw], watchlist: false, at: now)
        XCTAssertEqual(result[0].item.year, 2020); XCTAssertEqual(result[0].item.metadataRetrievedAt, now)
    }
    func testEmptySingleAndInjectedSelection() throws {
        XCTAssertNil(WatchDiscoveryProjection.pick([], index: { _ in XCTFail("Empty pool must not sample"); return 0 }))
        let one = try pool([movie()])
        XCTAssertEqual(WatchDiscoveryProjection.pick(one, index: { range in XCTAssertEqual(range, 0..<1); return 0 }), one[0])
        let mixed = try pool([movie(), show(), movie("tmdb:2")])
        for index in mixed.indices { XCTAssertEqual(WatchDiscoveryProjection.pick(mixed, index: { _ in index }), mixed[index]) }
        XCTAssertNil(WatchDiscoveryProjection.pick(mixed, index: { _ in 99 }))
    }
    func testSystemRandomOnlyReturnsEligibleUniqueCandidates() throws {
        var options = DiscoveryFilters(); options.media = .movies
        let candidates = try filter([movie(), show(), movie(), movie("tmdb:2")], options)
        XCTAssertEqual(candidates.count, 2)
        for _ in 0..<100 { XCTAssertTrue(candidates.contains(try XCTUnwrap(WatchDiscoveryProjection.pick(candidates)))) }
    }

    @MainActor func testExplicitCollectionIncludesWatchedAndPreservesManualOrderWithoutWrites() async throws {
        let store = try store(), model = WatchDiscoveryModel(), id = try store.saveCollection(name: "Tonight")
        try store.setStatus(.watched, media: movie())
        try store.setCollectionMembership(true, collection: id, media: movie())
        try store.setCollectionMembership(true, collection: id, media: show())
        let order = Array(store.members(of: id).map(\.id).reversed())
        try store.reorderCollection(id, memberships: order)
        model.source = .collection(id)
        let revision = store.revision
        await update(model, store)
        XCTAssertEqual(model.candidates.map(\.id), store.members(of: id).compactMap(\.mediaID))
        XCTAssertEqual(model.candidates.count, 2)
        XCTAssertEqual(store.revision, revision); XCTAssertEqual(store.members(of: id).map(\.id), order)
        model.source = .watchlist; await update(model, store)
        XCTAssertTrue(model.candidates.isEmpty)
    }
    @MainActor func testCollectionReferenceWithoutLibraryRowIsStillEligible() async throws {
        let store = try store(), model = WatchDiscoveryModel(), id = try store.saveCollection(name: "References")
        let value = movie()
        try store.setCollectionMembership(true, collection: id, media: value)
        try store.remove(SearchItem(value).id)
        model.source = .collection(id); await update(model, store)
        XCTAssertEqual(model.candidates.count, 1); XCTAssertFalse(model.candidates[0].metadataAvailable)
    }
    @MainActor func testFilterChangesPreservePickAndResetIsExplicit() async throws {
        let store = try store(), model = WatchDiscoveryModel()
        try store.setStatus(.watchlist, media: movie()); try store.setStatus(.watchlist, media: show())
        await update(model, store)
        model.pick(request: model.request(for: store), index: { _ in 0 })
        let picked = try XCTUnwrap(model.picked)
        model.showingResult = false; model.filters.genres = ["missing"]
        // Never sample the previous pool while replacement filtering is pending.
        model.pick(request: model.request(for: store), index: { _ in XCTFail("Stale pool"); return 0 })
        await update(model, store)
        XCTAssertTrue(model.candidates.isEmpty); XCTAssertEqual(model.picked, picked)
        model.resetFilters(); await update(model, store)
        XCTAssertEqual(model.candidates.count, 2); XCTAssertEqual(model.picked, picked)
        model.resetFlow(); XCTAssertNil(model.picked); XCTAssertEqual(model.source, .watchlist)
    }
    @MainActor func testOrdinaryNavigationRefreshKeepsSourceFiltersAndPick() async throws {
        let store = try store(), model = WatchDiscoveryModel(), id = try store.saveCollection(name: "Evening")
        try store.setCollectionMembership(true, collection: id, media: movie())
        model.source = .collection(id); model.filters.maximumMovieMinutes = 120
        await update(model, store); model.pick(request: model.request(for: store), index: { _ in 0 })
        let picked = model.picked
        await update(model, store)
        XCTAssertEqual(model.source, .collection(id)); XCTAssertEqual(model.filters.maximumMovieMinutes, 120)
        XCTAssertEqual(model.picked, picked); XCTAssertTrue(model.showingResult)
    }
    @MainActor func testExpiredCurrentPickRetainsIdentityButNotExpiredContent() async throws {
        let store = try store(), model = WatchDiscoveryModel()
        try store.setStatus(.watchlist, media: movie()); await update(model, store)
        model.pick(request: model.request(for: store), index: { _ in 0 })
        let id = model.picked?.id
        store.metadataReferenceDate = now.addingTimeInterval(MetadataPolicy.retention)
        await update(model, store)
        XCTAssertEqual(model.picked?.id, id); XCTAssertFalse(try XCTUnwrap(model.picked).metadataAvailable)
        XCTAssertNil(model.picked?.item.year)
    }
    @MainActor func testCancellationCannotPublishAnObsoletePoolAndCanRecover() async throws {
        let store = try store(), model = WatchDiscoveryModel()
        try store.setStatus(.watchlist, media: movie()); try store.setStatus(.watchlist, media: show())
        let request = model.request(for: store)
        let cancelled = Task { await model.update(from: store, request: request) }
        cancelled.cancel(); await cancelled.value
        XCTAssertNil(model.preparedRequest)
        model.filters.media = .tvShows; await update(model, store)
        XCTAssertEqual(model.candidates.map(\.id.kind), [.tvShow])
    }
    func testBlankTitleMissingArtworkAndSeriesSnapshotFallback() throws {
        let value = MediaSearchResult.movie(Movie(id: "tmdb:blank", title: "   ", metadataRetrievedAt: now))
        let result = try pool([value])
        XCTAssertEqual(result[0].item.title, MetadataPolicy.placeholder(result[0].id)); XCTAssertNil(result[0].posterURL)
        let series = TVShow(id: "tmdb:series", title: "Cached series", genres: [comedy], metadataRetrievedAt: now)
        let input = DiscoveryInput(id: series.id, library: nil, payloads: [], seriesPayloads: [try JSONEncoder().encode(series)])
        let fallback = try WatchDiscoveryProjection.build([input], watchlist: false, at: now)
        XCTAssertEqual(fallback[0].item.title, "Cached series"); XCTAssertNil(fallback[0].movieMinutes)
    }
    @MainActor func testOldRequestCannotReplaceNewFilters() async throws {
        let store = try store(), model = WatchDiscoveryModel()
        try store.setStatus(.watchlist, media: movie()); try store.setStatus(.watchlist, media: show())
        let old = model.request(for: store)
        model.filters.media = .tvShows; await update(model, store)
        let latest = model.preparedRequest
        await model.update(from: store, request: old)
        XCTAssertEqual(model.preparedRequest, latest); XCTAssertEqual(model.candidates.map(\.id.kind), [.tvShow])
    }
    @MainActor func testSourceRevisionUpdatesWatchlistAndDeletedCollectionIsEmpty() async throws {
        let store = try store(), model = WatchDiscoveryModel(), id = try store.saveCollection(name: "Shortlist")
        try store.setStatus(.watchlist, media: movie()); await update(model, store)
        XCTAssertEqual(model.candidates.count, 1)
        try store.setStatus(.watched, media: movie()); await update(model, store)
        XCTAssertTrue(model.candidates.isEmpty)
        try store.setCollectionMembership(true, collection: id, media: movie())
        model.source = .collection(id); await update(model, store)
        XCTAssertEqual(model.candidates.count, 1)
        try store.deleteCollection(id); await update(model, store)
        XCTAssertEqual(model.sourceCount, 0); XCTAssertTrue(model.candidates.isEmpty)
        XCTAssertEqual(model.source, .collection(id)) // No silent fallback to a different source.
    }
    @MainActor func testFreshDiarySnapshotCanSupplyMetadataAfterLibraryRemoval() async throws {
        let store = try store(), model = WatchDiscoveryModel(), id = try store.saveCollection(name: "Diary titles")
        let value = movie()
        try store.setCollectionMembership(true, collection: id, media: value)
        try store.saveViewingEvent(id: UUID(), media: value, watchedDate: nil, now: now)
        try store.remove(SearchItem(value).id)
        model.source = .collection(id); await update(model, store)
        XCTAssertEqual(model.candidates.first?.item.title, SearchItem(value).title)
        XCTAssertTrue(try XCTUnwrap(model.candidates.first).metadataAvailable)
    }
    @MainActor func testClearingProviderMetadataDoesNotResurrectPickedSnapshot() async throws {
        let store = try store(), model = WatchDiscoveryModel()
        try store.setStatus(.watchlist, media: movie()); await update(model, store)
        model.pick(request: model.request(for: store), index: { _ in 0 })
        let id = model.picked?.id
        try store.clearProviderMetadata(); await update(model, store)
        XCTAssertEqual(model.picked?.id, id); XCTAssertFalse(try XCTUnwrap(model.picked).metadataAvailable)
        XCTAssertTrue(try XCTUnwrap(model.picked).item.title.hasPrefix("Metadata unavailable"))
        XCTAssertNil(model.picked?.item.year); XCTAssertTrue(model.picked?.genres.isEmpty == true)
        XCTAssertEqual(store.entry(for: SearchItem(movie()).id)?.status, "watchlist")
    }
    @MainActor func testOfflinePersistentReopenNeedsNoProviderOrCredential() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Discovery.store"), instant = now
        do {
            let store = LibraryStore(container: try PersistenceController.makeContainer(at: url), clock: { instant })
            try store.setStatus(.watchlist, media: movie())
            try store.saveReview(id: UUID(), media: movie(), text: "Private offline review", now: now)
        }
        let reopened = LibraryStore(container: try PersistenceController.makeContainer(at: url), clock: { instant })
        let model = WatchDiscoveryModel(), revision = reopened.revision
        await update(model, reopened)
        XCTAssertEqual(model.candidates.first?.item.title, SearchItem(movie()).title)
        XCTAssertEqual(model.candidates.count, 1); XCTAssertEqual(reopened.revision, revision)
        XCTAssertEqual(reopened.personalReviews.first?.text, "Private offline review")
        // Neither model nor projection accepts a provider client or transport: all input is disk-backed local data.
    }
}

private extension Movie {
    func withRuntime(_ minutes: Int?) -> Self { var value = self; value.runtimeMinutes = minutes; return value }
}
