import SwiftData
import UIKit
import XCTest
@testable import MovieTracker

final class ArtworkMetadataRecoveryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_767_225_600)
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGP4DwQACfsD/fteaysAAAAASUVORK5CYII=")!
    private var imageURL: URL { URL(string: "https://image.tmdb.org/t/p/w185/recovery.png")! }
    private func movie(sparse: Bool = false, old: Bool = false) -> Movie {
        Movie(id: "tmdb:72", title: "Saved title", overview: sparse ? "" : "Available synopsis",
              posterReference: sparse ? nil : "/recovery.png", runtimeMinutes: sparse ? nil : 98,
              genres: sparse ? [] : [.init(id: "tmdb:18", name: "Drama")],
              metadataRetrievedAt: old ? now.addingTimeInterval(-MetadataPolicy.retention) : now)
    }
    @MainActor private func model(_ service: (any MediaMetadataService)?) -> MediaDetailModel {
        let date = now
        return MediaDetailModel(destination: .init(id: movie().id, title: "Saved title", year: nil), service: service,
                                cache: MediaDetailCache(clock: { date }), clock: { date })
    }
    @MainActor private func store() throws -> LibraryStore {
        let date = now
        return LibraryStore(container: try PersistenceController.makeContainer(inMemory: true), clock: { date })
    }
    @MainActor private func personalBackup(_ store: LibraryStore) throws -> Data {
        try BackupCodec.encode(store.capturePersonalBackup(at: now))
    }
    @MainActor private func seed(_ store: LibraryStore, old: Bool = false) throws {
        let media = MediaSearchResult.movie(movie(sparse: true, old: old))
        try store.setStatus(.watchlist, media: media)
        try store.setFavorite(true, media: media)
        try store.setPersonalRating(PersonalRating(halfStarUnits: 8), media: media)
        let eventID = LargeLibraryFixtures.uuid(1)
        try store.saveViewingEvent(id: eventID, media: media, watchedDate: nil, now: now)
        try store.saveReview(id: LargeLibraryFixtures.uuid(2), media: media, text: "Private review", eventID: eventID, now: now)
        let list = try store.saveCollection(name: "Keep this order", now: now)
        try store.setCollectionMembership(true, collection: list, media: .movie(Movie(id: "fixture:other", title: "Other")), now: now)
        try store.setCollectionMembership(true, collection: list, media: media, now: now)
        let members = store.members(of: list).map(\.id)
        try store.reorderCollection(list, memberships: Array(members.reversed()), original: members, now: now)
        let show = TVShow(id: "tmdb:72", title: "Saved series", metadataRetrievedAt: now)
        let episode = TVEpisode(id: .init(seriesID: show.id, providerValue: "tmdb:episode:1"), seasonNumber: 1,
            number: 1, title: "Episode", airDate: now.addingTimeInterval(-86_400), overview: "", runtimeMinutes: nil, metadataRetrievedAt: now)
        try store.setEpisodeWatched(true, episode: episode, show: show, now: now)
    }

    @MainActor func testRightsGateKeepsBoundedMemoryOnlyAndRelaunchFallback() {
        XCTAssertFalse(ProviderArtworkPolicy.persistentStorageAuthorized)
        XCTAssertEqual(ProviderArtworkPolicy.memoryEntries, 40)
        XCTAssertEqual(ProviderArtworkPolicy.memoryBytes, 40_000_000)
        XCTAssertEqual(MetadataPolicy.refreshInterval, 30 * 86_400)
        XCTAssertEqual(MetadataPolicy.retention, 150 * 86_400)
        let cache = ProviderArtworkCache()
        XCTAssertTrue(cache.save(png, url: imageURL, at: now))
        XCTAssertNotNil(cache.image(imageURL, at: now))
        XCTAssertNil(ProviderArtworkCache().image(imageURL, at: now))
    }
    @MainActor func testInvalidOversizedArtworkDoesNotReplaceUsableMemoryEntry() {
        let cache = ProviderArtworkCache()
        XCTAssertTrue(cache.save(png, url: imageURL, at: now))
        let bytes = cache.byteCount
        XCTAssertFalse(cache.save(Data(), url: imageURL, at: now))
        XCTAssertFalse(cache.save(Data(repeating: 0, count: ProviderArtworkPolicy.maximumResponseBytes + 1), url: imageURL, at: now))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2_049, height: 1), format: format)
        let tooWide = renderer.pngData { context in UIColor.red.setFill(); context.cgContext.fill(CGRect(x: 0, y: 0, width: 2_049, height: 1)) }
        XCTAssertFalse(cache.save(tooWide, url: imageURL, at: now))
        XCTAssertEqual(cache.byteCount, bytes); XCTAssertNotNil(cache.image(imageURL, at: now))
    }
    func testFriendlyPlaceholderNeverChangesStableIdentityOrOrdinaryTitle() {
        let id = movie().id
        let placeholder = SearchItem(MetadataPolicy.placeholderMedia(id))
        XCTAssertEqual(placeholder.displayTitle, "Title information unavailable")
        XCTAssertEqual(placeholder.destination.id, id)
        XCTAssertEqual(placeholder.title, MetadataPolicy.placeholder(id))
        XCTAssertEqual(SearchItem(.movie(movie())).displayTitle, "Saved title")
    }
    func testMissingOptionalFieldsAreDescribedWithoutInventingValues() {
        XCTAssertEqual(DetailMetadataRecovery.missingFields(in: .movie(movie(sparse: true))), ["synopsis", "genres", "runtime", "artwork"])
        XCTAssertTrue(DetailMetadataRecovery.missingFields(in: .movie(movie())).isEmpty)
        let show = TVShow(id: "tmdb:72", title: "Series")
        XCTAssertTrue(DetailMetadataRecovery.missingFields(in: .tvShow(show)).contains("season list"))
    }
    @MainActor func testSparseFreshMetadataRequiresExplicitRefreshAndPreservesAllPersonalData() async throws {
        let store = try store(); try seed(store)
        let before = try personalBackup(store), service = RecoveryMetadataService(movie: movie())
        let details = model(service)
        await details.load(store: store)
        XCTAssertFalse(DetailMetadataRecovery.missingFields(in: try XCTUnwrap(details.snapshot?.media)).isEmpty)
        let beforeCalls = await service.calls; XCTAssertEqual(beforeCalls, 0)
        await details.load(store: store, force: true)
        XCTAssertEqual(details.snapshot?.media, .movie(movie()))
        XCTAssertEqual(try personalBackup(store), before)
        XCTAssertEqual(store.metadataState(for: movie().id)?.lastSuccessfulFetch, now)
        XCTAssertFalse(details.isLoading); XCTAssertFalse(details.isLoadingExtras)
    }
    @MainActor func testExpiredSavedPosterReferenceIsHiddenAtExactTitleExpiry() async throws {
        let store = try store()
        try store.setStatus(.watched, media: .movie(movie()))
        try store.metadataRefreshSucceeded(.movie(movie()), posterURL: imageURL)
        let details = model(nil)
        await details.load(store: store)
        XCTAssertEqual(details.posterURL(at: now), imageURL)
        XCTAssertNil(details.posterURL(at: now.addingTimeInterval(MetadataPolicy.retention)))
        let expired = try XCTUnwrap(details.snapshot(at: now.addingTimeInterval(MetadataPolicy.retention)))
        XCTAssertEqual(SearchItem(expired.media).displayTitle, "Title information unavailable")
    }
    @MainActor func testOfflineFailureDoesNotRenewLeaseAndManualRecoveryPreservesBackup() async throws {
        let store = try store(); try seed(store, old: true)
        let before = try personalBackup(store), service = RecoveryMetadataService(movie: movie(), failure: .offline)
        let details = model(service)
        await details.load(store: store)
        XCTAssertEqual(details.error, .offline); XCTAssertFalse(details.isLoading)
        XCTAssertNil(store.entry(for: movie().id)?.snapshotData)
        let oldReceipt = store.metadataState(for: movie().id)?.lastSuccessfulFetch
        await details.load(store: store)
        let calls = await service.calls; XCTAssertEqual(calls, 1)
        XCTAssertEqual(store.metadataState(for: movie().id)?.lastSuccessfulFetch, oldReceipt)
        await service.setFailure(nil)
        await details.load(store: store, force: true)
        XCTAssertNil(details.error); XCTAssertEqual(details.snapshot?.media, .movie(movie()))
        XCTAssertEqual(try personalBackup(store), before)
    }
    @MainActor func testRateLimitDefersEvenExplicitRetryWithoutTouchingPersonalRecords() async throws {
        let store = try store(); try seed(store, old: true)
        let before = try personalBackup(store)
        let service = RecoveryMetadataService(movie: movie(), failure: .rateLimited(retryAfter: "1800"))
        let details = model(service)
        await details.load(store: store); await details.load(store: store, force: true)
        let calls = await service.calls; XCTAssertEqual(calls, 1)
        XCTAssertEqual(store.metadataState(for: movie().id)?.retryAfter, now.addingTimeInterval(1800))
        XCTAssertEqual(try personalBackup(store), before)
    }
    @MainActor func testCancelledResponseCannotRestoreExpiredMetadataOrWritePersonalData() async throws {
        let store = try store(); try seed(store, old: true)
        let before = try personalBackup(store), service = RecoveryMetadataService(movie: movie(), suspended: true)
        let details = model(service)
        let task = Task { await details.load(store: store) }
        await service.waitForRequest(); task.cancel(); await service.complete(); await task.value
        XCTAssertTrue(details.wasCancelled); XCTAssertFalse(details.isLoading)
        XCTAssertNil(store.entry(for: movie().id)?.snapshotData)
        XCTAssertEqual(try personalBackup(store), before)
    }
    @MainActor func testChangedCredentialEpochRejectsLateMetadataResponse() async throws {
        let originalEpoch = MetadataRuntimeGate.credentialEpoch
        defer { MetadataRuntimeGate.credentialEpoch = originalEpoch }
        let store = try store(); try seed(store, old: true)
        let before = try personalBackup(store), service = RecoveryMetadataService(movie: movie(), suspended: true)
        let details = model(service)
        let task = Task { await details.load(store: store) }
        await service.waitForRequest(); MetadataRuntimeGate.credentialEpoch += 1
        await service.complete(); await task.value
        XCTAssertTrue(details.wasCancelled); XCTAssertNil(store.entry(for: movie().id)?.snapshotData)
        XCTAssertEqual(try personalBackup(store), before)
    }
    @MainActor func testCollectionOnlyPlaceholderRecoveryDoesNotRecreateLibraryEntry() async throws {
        let store = try store(), media = MediaSearchResult.movie(movie())
        let list = try store.saveCollection(name: "Reference only", now: now)
        try store.setCollectionMembership(true, collection: list, media: media, now: now)
        try store.remove(movie().id)
        let before = try personalBackup(store), service = RecoveryMetadataService(movie: movie())
        XCTAssertNotNil(store.offlineMedia(for: movie().id))
        await model(service).load(store: store, force: true)
        XCTAssertNil(store.entry(for: movie().id)); XCTAssertEqual(store.members(of: list).count, 1)
        XCTAssertEqual(try personalBackup(store), before)
    }
    @MainActor func testSeasonFailureAndSuccessfulRecoveryPreserveExactWatchedEpisode() async throws {
        let store = try store(); try seed(store)
        try store.maintainMetadata(at: now)
        let show = TVShow(id: "tmdb:72", title: "Recovered series", metadataRetrievedAt: now)
        let episode = TVEpisode(id: .init(seriesID: show.id, providerValue: "tmdb:episode:1"), seasonNumber: 1,
            number: 1, title: "Recovered episode details", airDate: now.addingTimeInterval(-86_400), overview: "Recovered synopsis",
            runtimeMinutes: 42, metadataRetrievedAt: now)
        let season = TVSeasonDetails(seriesID: show.id, number: 1, name: "Recovered season", episodes: [episode], metadataRetrievedAt: now)
        let service = RecoveryMetadataService(movie: movie(), failure: .offline, season: season)
        let before = try personalBackup(store)
        let progress = TVProgressModel(show: show, service: service)
        await progress.loadSeason(1, store: store, force: true)
        XCTAssertEqual(progress.lastError, .offline)
        XCTAssertEqual(try personalBackup(store), before)
        await service.setFailure(nil)
        await progress.loadSeason(1, store: store, force: true)
        XCTAssertNil(progress.lastError)
        XCTAssertEqual(store.episodeProgress.first?.savedEpisode?.title, "Recovered episode details")
        XCTAssertTrue(store.episodeProgress.first?.isWatched == true)
        XCTAssertEqual(try personalBackup(store), before)
    }
    @MainActor func testLocalSaveFailureIsNotReportedAsOfflineOrGivenProviderBackoff() async throws {
        let date = now
        let container = try PersistenceController.makeContainer(inMemory: true)
        let store = LibraryStore(container: container, clock: { date }, save: { _ in throw LibraryStoreError.saveFailed })
        let details = model(RecoveryMetadataService(movie: movie()))
        await details.load(store: store, force: true)
        XCTAssertNotNil(details.persistenceErrorMessage); XCTAssertNil(details.error)
        XCTAssertNil(store.metadataState(for: movie().id)?.lastFailure)
        XCTAssertFalse(details.isLoading); XCTAssertFalse(details.isLoadingExtras)
    }
}

private actor RecoveryMetadataService: MediaMetadataService {
    let movie: Movie
    var failure: MetadataError?
    let suspended: Bool
    let season: TVSeasonDetails?
    private(set) var calls = 0
    private var pending: CheckedContinuation<Movie, Error>?
    private var observer: CheckedContinuation<Void, Never>?
    init(movie: Movie, failure: MetadataError? = nil, suspended: Bool = false, season: TVSeasonDetails? = nil) { self.movie = movie; self.failure = failure; self.suspended = suspended; self.season = season }
    func setFailure(_ error: MetadataError?) { failure = error }
    func movieDetails(id: MediaID) async throws -> Movie {
        calls += 1
        if suspended {
            return try await withCheckedThrowingContinuation { pending = $0; observer?.resume(); observer = nil }
        }
        if let failure { throw failure }
        return movie
    }
    func waitForRequest() async {
        if pending != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
    func complete() { pending?.resume(returning: movie); pending = nil }
    func tvSeasonDetails(for id: MediaID, number: Int) async throws -> TVSeasonDetails {
        if let failure { throw failure }
        guard let season else { throw MetadataError.notFound }
        return season
    }
    func tvShowDetails(id: MediaID) async throws -> TVShow { throw MetadataError.notFound }
    func searchAll(query: String, page: Int) async throws -> MetadataPage<MediaSearchResult> { throw MetadataError.offline }
    func searchMovies(query: String, page: Int) async throws -> MetadataPage<Movie> { throw MetadataError.offline }
    func searchTVShows(query: String, page: Int) async throws -> MetadataPage<TVShow> { throw MetadataError.offline }
    func genres(for kind: MediaID.Kind) async throws -> [MediaGenre] { [] }
    func imageResolver() async throws -> MetadataImageResolver { throw MetadataError.offline }
}
