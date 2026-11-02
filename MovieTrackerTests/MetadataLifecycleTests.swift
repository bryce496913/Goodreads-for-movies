import SwiftData
import UIKit
import XCTest
@testable import MovieTracker

final class MetadataLifecycleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_767_225_600)
    private func media(_ value: String = "tmdb:72", fetched: Date) -> MediaSearchResult {
        .movie(Movie(id: value, title: "Provider-only movie title", overview: "Provider-only synopsis", posterReference: "/provider.jpg", metadataRetrievedAt: fetched))
    }
    func testFreshAndApproachingExpiryPolicy() {
        XCTAssertTrue(MetadataPolicy.isUsable(now, at: now))
        XCTAssertFalse(MetadataPolicy.refreshEligible(now, at: now.addingTimeInterval(29 * 86_400)))
        XCTAssertTrue(MetadataPolicy.refreshEligible(now, at: now.addingTimeInterval(30 * 86_400)))
        XCTAssertTrue(MetadataPolicy.isUsable(now, at: now.addingTimeInterval(149 * 86_400)))
    }
    func testExactExpiryBoundaryUnknownDatesAndClockRollback() {
        XCTAssertTrue(MetadataPolicy.isUsable(now, at: now.addingTimeInterval(MetadataPolicy.retention - 0.001)))
        XCTAssertFalse(MetadataPolicy.isUsable(now, at: now.addingTimeInterval(MetadataPolicy.retention)))
        XCTAssertFalse(MetadataPolicy.isUsable(nil, at: now))
        XCTAssertFalse(MetadataPolicy.isUsable(now.addingTimeInterval(1), at: now))
    }
    @MainActor func testIndependentRecordsExpireWithoutRemovingAnyPersonalContent() throws {
        let store = try makeStore()
        let old = media(fetched: now.addingTimeInterval(-151 * 86_400)), fresh = media("tmdb:73", fetched: now)
        try store.setStatus(.watched, media: old)
        try store.setPersonalRating(PersonalRating(halfStarUnits: 9), media: old)
        try store.setFavorite(true, media: old)
        let id = SearchItem(old).id, eventID = UUID(), reviewID = UUID()
        try store.saveViewingEvent(id: eventID, media: old, watchedDate: now, now: now)
        try store.saveReview(id: reviewID, media: old, text: "User text remains forever", eventID: eventID, now: now)
        try store.setStatus(.watchlist, media: fresh)
        let original = try XCTUnwrap(store.entry(for: id)), uuid = original.id, added = original.addedAt, edited = original.updatedAt, rated = original.ratingUpdatedAt
        try store.maintainMetadata(at: now)
        let row = try XCTUnwrap(store.entry(for: id))
        XCTAssertEqual(row.id, uuid); XCTAssertEqual(row.status, "watched"); XCTAssertTrue(row.isFavorite)
        XCTAssertEqual(row.ratingHalfStarUnits, 9); XCTAssertEqual(row.addedAt, added); XCTAssertEqual(row.updatedAt, edited); XCTAssertEqual(row.ratingUpdatedAt, rated)
        XCTAssertNil(row.snapshotData); XCTAssertNil(row.savedTitle); XCTAssertNil(row.savedPosterReference)
        XCTAssertTrue(row.displayTitle.contains(id.value))
        XCTAssertEqual(store.personalReviews.first?.text, "User text remains forever")
        XCTAssertEqual(store.personalReviews.first?.viewingEventID, eventID); XCTAssertNil(store.personalReviews.first?.snapshotData)
        XCTAssertEqual(store.viewingEvents.first?.watchedDate, now); XCTAssertNil(store.viewingEvents.first?.snapshotData)
        XCTAssertEqual(store.entry(for: SearchItem(fresh).id)?.savedTitle, "Provider-only movie title")
    }
    @MainActor func testUnknownLegacyRetrievalIsNotRenewedByPersonalEdits() throws {
        let store = try makeStore()
        let legacy = MediaSearchResult.movie(Movie(id: "tmdb:1", title: "Unknown age"))
        try store.setStatus(.watchlist, media: legacy)
        try store.maintainMetadata(at: now)
        try store.setFavorite(true, media: legacy)
        try store.setPersonalRating(PersonalRating(halfStarUnits: 7), media: legacy)
        let row = try XCTUnwrap(store.entries.first)
        XCTAssertNil(row.savedTitle); XCTAssertNil(row.snapshotData)
        XCTAssertEqual(row.ratingHalfStarUnits, 7); XCTAssertTrue(row.isFavorite)
        XCTAssertNil(store.metadataState(for: SearchItem(legacy).id))
    }
    @MainActor func testSuccessfulRefreshUpdatesAllSnapshotsButNotPersonalDates() throws {
        let store = try makeStore(), old = media(fetched: now.addingTimeInterval(-151 * 86_400))
        let id = SearchItem(old).id
        try store.setStatus(.watched, media: old)
        try store.saveReview(id: UUID(), media: old, text: "User review", now: now)
        try store.saveViewingEvent(id: UUID(), media: old, watchedDate: nil, now: now)
        try store.maintainMetadata(at: now)
        let edited = store.personalReviews.first?.editedAt, updated = store.entries.first?.updatedAt
        try store.metadataRefreshSucceeded(media(fetched: now))
        XCTAssertEqual(store.entries.first?.savedTitle, "Provider-only movie title")
        XCTAssertNotNil(store.personalReviews.first?.snapshotData); XCTAssertNotNil(store.viewingEvents.first?.snapshotData)
        XCTAssertEqual(store.personalReviews.first?.text, "User review"); XCTAssertEqual(store.personalReviews.first?.editedAt, edited)
        XCTAssertEqual(store.entries.first?.updatedAt, updated)
        XCTAssertEqual(store.metadataState(for: id)?.lastSuccessfulFetch, now)
    }
    @MainActor func testFailedRefreshKeepsOriginalLeaseAndUsesExplicitBackoff() throws {
        let store = try makeStore(), fetched = now.addingTimeInterval(-140 * 86_400)
        let saved = media(fetched: fetched), id = SearchItem(saved).id
        try store.setStatus(.watched, media: saved)
        try store.metadataRefreshSucceeded(saved)
        try store.metadataRefreshFailed(id, error: .offline, at: now)
        XCTAssertEqual(store.metadataState(for: id)?.lastSuccessfulFetch, fetched)
        XCTAssertEqual(store.metadataState(for: id)?.lastFailure, "offline")
        XCTAssertFalse(store.mayRefreshMetadata(id, at: now))
        XCTAssertTrue(store.mayRefreshMetadata(id, at: now, force: true))
        XCTAssertTrue(store.mayRefreshMetadata(id, at: now.addingTimeInterval(901)))
        try store.maintainMetadata(at: now.addingTimeInterval(11 * 86_400))
        XCTAssertNil(store.entries.first?.snapshotData)
    }
    @MainActor func testRateLimitBlocksRepeatedRetriesAndDoesNotRenewSuccess() throws {
        let store = try makeStore(), id = MediaID(kind: .movie, value: "tmdb:1")
        try store.metadataRefreshFailed(id, error: .rateLimited(retryAfter: "3600"), at: now)
        XCTAssertFalse(store.mayRefreshMetadata(id, at: now.addingTimeInterval(3599), force: true))
        XCTAssertTrue(store.mayRefreshMetadata(id, at: now.addingTimeInterval(3600)))
        XCTAssertNil(store.metadataState(for: id)?.lastSuccessfulFetch)
        XCTAssertTrue(store.entries.isEmpty)
    }
    @MainActor func testEpisodeExpiryKeepsStableFlagsAndWatchedDates() throws {
        let store = try makeStore(), id = MediaID(kind: .tvShow, value: "tmdb:5")
        let show = TVShow(id: id.value, title: "Provider series", seasons: [TVSeasonSummary(number: 1, providerID: nil, name: "Provider season", episodeCount: 1)], metadataRetrievedAt: now.addingTimeInterval(-151 * 86_400))
        let episode = TVEpisode(id: EpisodeID(seriesID: id, providerValue: "tmdb:episode:1"), seasonNumber: 1, number: 1,
            title: "Provider episode", airDate: now.addingTimeInterval(-1_000_000), overview: "Provider episode synopsis", runtimeMinutes: 42, metadataRetrievedAt: now.addingTimeInterval(-151 * 86_400))
        try store.cacheSeasonCatalog(show: show)
        try store.cacheSeason(TVSeasonDetails(seriesID: id, number: 1, name: "Provider season", episodes: [episode]), show: show, now: now.addingTimeInterval(-151 * 86_400))
        try store.setEpisodeWatched(true, episode: episode, show: show, now: now)
        let uuid = store.episodeProgress.first?.id
        try store.maintainMetadata(at: now)
        XCTAssertEqual(store.episodeProgress.first?.id, uuid); XCTAssertTrue(store.isWatched(episode.id))
        XCTAssertEqual(store.episodeProgress.first?.watchedAt, now)
        XCTAssertEqual(store.episodeProgress.first?.savedEpisode?.id, episode.id)
        XCTAssertEqual(store.episodeProgress.first?.savedEpisode?.title, "Episode metadata unavailable")
        XCTAssertNil(store.tvSeasons.first?.episodesData); XCTAssertNil(store.tvSeasons.first?.seriesData)
        XCTAssertNil(store.seasonProgress(try XCTUnwrap(store.tvSeasons.first)).percentage)
    }
    @MainActor func testSessionCacheExpiresUsingInjectedClock() {
        let clock = MetadataTestClock(now)
        let cache = MediaDetailCache(clock: { clock.date })
        let value = media(fetched: now), id = SearchItem(value).id
        cache.save(.init(media: value), for: id)
        XCTAssertNotNil(cache.snapshot(for: id))
        clock.advance(MetadataPolicy.retention)
        XCTAssertNil(cache.snapshot(for: id))
    }
    @MainActor func testOfflineDetailShowsIdentifierAndRetainsLocalActions() async throws {
        let clock = MetadataTestClock(now)
        let cache = MediaDetailCache(clock: { clock.date })
        let value = media(fetched: now), id = SearchItem(value).id
        cache.save(.init(media: value), for: id)
        let store = LibraryStore(container: try PersistenceController.makeContainer(inMemory: true), clock: { clock.date })
        try store.setPersonalRating(PersonalRating(halfStarUnits: 8), media: value)
        clock.advance(MetadataPolicy.retention)
        let model = MediaDetailModel(destination: SearchItem(value).destination, service: nil, cache: cache, clock: { clock.date })
        await model.load(store: store)
        XCTAssertEqual(model.error, .missingCredential)
        XCTAssertEqual(model.snapshot.map { SearchItem($0.media).title }, MetadataPolicy.placeholder(id))
        XCTAssertEqual(store.entries.first?.ratingHalfStarUnits, 8)
    }
    @MainActor func testExplicitClearRemovesFreshProviderContentButKeepsRating() throws {
        let store = try makeStore(), value = media(fetched: now)
        try store.setPersonalRating(PersonalRating(halfStarUnits: 10), media: value)
        try store.clearProviderMetadata()
        XCTAssertNil(store.entries.first?.snapshotData); XCTAssertEqual(store.entries.first?.ratingHalfStarUnits, 10)
    }
    @MainActor func testArtworkMemoryHasBoundedFreshnessWithoutDiskReads() throws {
        let cache = ProviderArtworkCache()
        let url = try XCTUnwrap(URL(string: "https://image.tmdb.org/t/p/w185/fixture.png"))
        let png = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGP4DwQACfsD/fteaysAAAAASUVORK5CYII="))
        cache.save(png, url: url, at: now)
        XCTAssertNotNil(cache.image(url, at: now))
        XCTAssertNil(cache.image(url, at: now.addingTimeInterval(MetadataPolicy.retention)))
    }
    @MainActor func testLifecycleStatePersistsAcrossDiskReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Leases.store"), value = media(fetched: now), id = SearchItem(value).id
        let date = now
        try autoreleasepool {
            let store = LibraryStore(container: try PersistenceController.makeContainer(at: url), clock: { date })
            try store.setStatus(.watchlist, media: value)
            try store.metadataRefreshSucceeded(value)
            try store.metadataRefreshFailed(id, error: .offline, at: date)
        }
        let reopened = LibraryStore(container: try PersistenceController.makeContainer(at: url), clock: { date })
        XCTAssertEqual(reopened.metadataState(for: id)?.lastSuccessfulFetch, date)
        XCTAssertEqual(reopened.metadataState(for: id)?.lastFailure, "offline")
        XCTAssertEqual(reopened.metadataState(for: id)?.retryAfter, date.addingTimeInterval(MetadataPolicy.retryInterval))
        XCTAssertEqual(reopened.entries.count, 1)
    }
    func testHTTPDateRetryAfterUsesInjectedReferenceTime() {
        XCTAssertEqual(MetadataPolicy.retryDelay("Thu, 01 Jan 2026 01:00:00 GMT", at: now), 3600)
        XCTAssertEqual(MetadataPolicy.retryDelay("not a date", at: now), MetadataPolicy.retryInterval)
    }

    @MainActor func testMockedRefreshPersistsThenReusesFreshDataAndCannotExtendOffline() async throws {
        let clock = MetadataTestClock(now), id = MediaID(kind: .movie, value: "tmdb:72")
        let fresh = Movie(id: id.value, title: "Fresh provider title", metadataRetrievedAt: now)
        let service = ReceiptMetadataService(movie: fresh)
        let store = LibraryStore(container: try PersistenceController.makeContainer(inMemory: true), clock: { clock.date })
        try store.setPersonalRating(PersonalRating(halfStarUnits: 8), media: media(fetched: now.addingTimeInterval(-151 * 86_400)))
        let cache = MediaDetailCache(clock: { clock.date })
        let destination = MediaDestination(id: id, title: "Selected", year: nil)
        let model = MediaDetailModel(destination: destination, service: service, cache: cache, clock: { clock.date })
        await model.load(store: store)
        XCTAssertEqual(store.entries.first?.savedTitle, "Fresh provider title")
        let reopened = MediaDetailModel(destination: destination, service: service, cache: cache, clock: { clock.date })
        await reopened.load(store: store)
        let firstCalls = await service.calls
        XCTAssertEqual(firstCalls, 1)
        clock.advance(151 * 86_400); await service.goOffline()
        await reopened.load(store: store, force: true)
        XCTAssertEqual(reopened.error, .offline)
        XCTAssertEqual(reopened.snapshot.map { SearchItem($0.media).title }, MetadataPolicy.placeholder(id))
        XCTAssertEqual(store.entries.first?.ratingHalfStarUnits, 8)
        XCTAssertNil(store.entries.first?.snapshotData)
        XCTAssertEqual(store.metadataState(for: id)?.lastSuccessfulFetch, now)
    }
    @MainActor func testCredentialEpochRejectsOldRequestsAndArchiveGateBlocksActivation() throws {
        let epoch = MetadataRuntimeGate.credentialEpoch, warning = MetadataRuntimeGate.blockingReason
        defer { MetadataRuntimeGate.credentialEpoch = epoch; MetadataRuntimeGate.blockingReason = warning }
        MetadataRuntimeGate.blockingReason = nil
        XCTAssertNoThrow(try MetadataRuntimeGate.authorize(epoch))
        MetadataRuntimeGate.credentialEpoch += 1
        XCTAssertThrowsError(try MetadataRuntimeGate.authorize(epoch))
        MetadataRuntimeGate.blockingReason = "An archive needs review"
        XCTAssertThrowsError(try MetadataRuntimeGate.authorize(MetadataRuntimeGate.credentialEpoch))
    }

    @MainActor private func makeStore() throws -> LibraryStore {
        LibraryStore(container: try PersistenceController.makeContainer(inMemory: true), clock: { Date(timeIntervalSince1970: 1_767_225_600) })
    }
}

private final class MetadataTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ date: Date) { value = date }
    var date: Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ interval: TimeInterval) { lock.lock(); defer { lock.unlock() }; value.addTimeInterval(interval) }
}

private actor ReceiptMetadataService: MediaMetadataService {
    let movie: Movie
    private var offline = false
    private(set) var calls = 0
    init(movie: Movie) { self.movie = movie }
    func goOffline() { offline = true }
    func movieDetails(id: MediaID) async throws -> Movie { calls += 1; if offline { throw MetadataError.offline }; return movie }
    func tvShowDetails(id: MediaID) async throws -> TVShow { throw MetadataError.invalidIdentifier }
    func searchMovies(query: String, page: Int) async throws -> MetadataPage<Movie> { throw MetadataError.invalidQuery }
    func searchTVShows(query: String, page: Int) async throws -> MetadataPage<TVShow> { throw MetadataError.invalidQuery }
    func searchAll(query: String, page: Int) async throws -> MetadataPage<MediaSearchResult> { throw MetadataError.invalidQuery }
    func genres(for kind: MediaID.Kind) async throws -> [MediaGenre] { [] }
    func imageResolver() async throws -> MetadataImageResolver { throw MetadataError.invalidPayload }
}
