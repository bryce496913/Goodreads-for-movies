import SwiftData
import UIKit
import XCTest
@testable import MovieTracker

final class OfflineReliabilityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_767_225_600)
    private var movieID: MediaID { MediaID(kind: .movie, value: "tmdb:72") }
    private var showID: MediaID { MediaID(kind: .tvShow, value: "tmdb:72") }
    private func movie(fetched: Date? = nil, title: String = "Saved movie") -> Movie {
        Movie(id: movieID.value, title: title, overview: "Saved synopsis", posterReference: "/movie.png", metadataRetrievedAt: fetched ?? now)
    }
    private func show(fetched: Date? = nil) -> TVShow {
        TVShow(id: showID.value, title: "Saved series", overview: "Saved series synopsis",
            seasons: [TVSeasonSummary(number: 1, providerID: nil, name: "Season One", episodeCount: 1)], metadataRetrievedAt: fetched ?? now)
    }
    private func episode(fetched: Date? = nil) -> TVEpisode {
        TVEpisode(id: EpisodeID(seriesID: showID, providerValue: "tmdb:episode:1"), seasonNumber: 1, number: 1,
            title: "Saved episode", airDate: now.addingTimeInterval(-86_400), overview: "Episode synopsis", runtimeMinutes: 42,
            metadataRetrievedAt: fetched ?? now)
    }
    @MainActor private func makeStore() throws -> LibraryStore {
        let date = now
        return LibraryStore(container: try PersistenceController.makeContainer(inMemory: true), clock: { date })
    }
    @MainActor private func detailModel(_ id: MediaID, service: (any MediaMetadataService)? = nil) -> MediaDetailModel {
        let date = now
        return MediaDetailModel(destination: MediaDestination(id: id, title: "Selected", year: nil), service: service,
            cache: MediaDetailCache(clock: { date }), clock: { date })
    }
    @MainActor private func seed(_ store: LibraryStore) throws {
        let value = MediaSearchResult.movie(movie()), series = show(), item = episode()
        try store.setStatus(.watched, media: value)
        try store.setPersonalRating(PersonalRating(halfStarUnits: 8), media: value)
        try store.saveReview(id: LargeLibraryFixtures.uuid(1), media: value, text: "Private saved review", now: now)
        try store.saveViewingEvent(id: LargeLibraryFixtures.uuid(2), media: value, watchedDate: nil, now: now)
        try store.cacheSeasonCatalog(show: series)
        try store.cacheSeason(TVSeasonDetails(seriesID: series.id, number: 1, name: "Season One", episodes: [item], metadataRetrievedAt: now), show: series, now: now)
        try store.setEpisodeWatched(true, episode: item, show: series, now: now)
        try store.maintainMetadata(at: now)
    }

    @MainActor func testSavedMovieAndTVLoadWithoutAnyNetworkOrCredential() async throws {
        let store = try makeStore(); try seed(store)
        let service = OfflineFixtureService(movie: movie(), show: show())
        let movieModel = detailModel(movieID, service: service), tvModel = detailModel(showID, service: service)
        await movieModel.load(store: store); await tvModel.load(store: store)
        XCTAssertEqual(movieModel.snapshot?.media, .movie(movie()))
        XCTAssertEqual(tvModel.snapshot?.media, .tvShow(show()))
        XCTAssertNil(movieModel.error); XCTAssertNil(tvModel.error)
        XCTAssertEqual(movieModel.availability, .saved(now))
        XCTAssertFalse(movieModel.isLoading); XCTAssertFalse(tvModel.isLoadingExtras)
        let calls = await service.calls; XCTAssertEqual(calls, 0)
        let noCredential = detailModel(movieID)
        await noCredential.load(store: store)
        XCTAssertNil(noCredential.error); XCTAssertFalse(noCredential.canRefresh)
        XCTAssertEqual(noCredential.snapshot?.media, .movie(movie()))
    }

    @MainActor func testFreshPartialSeasonLoadsBeforeCredentialAndBackoffChecks() async throws {
        let store = try makeStore(); try seed(store)
        // Missing expected count is incomplete coverage, not a reason to require network to open the list.
        try store.writeTransaction { _ in store.tvSeasons.first?.expectedEpisodeCount = nil }
        try store.metadataRefreshFailed(showID, scope: "season:1", error: .offline, at: now)
        let model = TVProgressModel(show: show(), service: nil)
        await model.loadSeason(1, store: store)
        XCTAssertTrue(model.isUsingSavedSeason); XCTAssertFalse(model.isLoading); XCTAssertNil(model.errorMessage)
        let row = try XCTUnwrap(store.seasons(for: showID).first)
        XCTAssertEqual(store.episodes(for: row).first?.overview, "Episode synopsis")
        XCTAssertNil(store.seasonProgress(row, now: now).percentage)
    }

    @MainActor func testOfflineEditsAndMetadataSurviveDiskContainerReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Offline.store"), date = now
        try autoreleasepool {
            let first = LibraryStore(container: try PersistenceController.makeContainer(at: url), clock: { date })
            try seed(first)
            try first.setPersonalRating(PersonalRating(halfStarUnits: 9), media: .movie(movie()))
            try first.saveReview(id: LargeLibraryFixtures.uuid(1), media: .movie(movie()), text: "Edited offline", now: now)
            try first.saveViewingEvent(id: LargeLibraryFixtures.uuid(2), media: .movie(movie()), watchedDate: now, now: now)
            try first.setEpisodeWatched(false, episode: episode(), show: show(), now: now)
        }
        let reopened = LibraryStore(container: try PersistenceController.makeContainer(at: url), clock: { date })
        try reopened.maintainMetadata(at: now)
        let movieModel = detailModel(movieID), tvModel = detailModel(showID)
        await movieModel.load(store: reopened); await tvModel.load(store: reopened)
        let season = TVProgressModel(show: show(), service: nil)
        await season.loadSeason(1, store: reopened)
        XCTAssertEqual(movieModel.snapshot?.media, .movie(movie())); XCTAssertEqual(tvModel.snapshot?.media, .tvShow(show()))
        XCTAssertEqual(try reopened.entry(for: movieID)?.validatedRating()?.halfStarUnits, 9)
        XCTAssertEqual(reopened.reviews(for: movieID).first?.text, "Edited offline")
        XCTAssertEqual(reopened.events(for: movieID).first?.watchedDate, now)
        XCTAssertFalse(reopened.isWatched(episode().id)); XCTAssertEqual(reopened.episodeProgress.count, 1)
        XCTAssertTrue(season.isUsingSavedSeason)
        let dashboard = try DashboardAggregator.aggregate(DashboardInput.capture(reopened), now: now)
        XCTAssertEqual(dashboard.statistics.ratings, 1); XCTAssertEqual(dashboard.statistics.reviews, 1)
        XCTAssertEqual(dashboard.statistics.viewingEvents, 1); XCTAssertEqual(dashboard.statistics.watchedEpisodes, 0)
    }

    @MainActor func testOfflineRefreshPreservesSnapshotAndDoesNotExtendBackoffOnReopen() async throws {
        let store = try makeStore(), old = movie(fetched: now.addingTimeInterval(-31 * 86_400))
        try store.setPersonalRating(PersonalRating(halfStarUnits: 8), media: .movie(old))
        let service = OfflineFixtureService(movie: movie(), show: show())
        let first = detailModel(movieID, service: service)
        await first.load(store: store)
        XCTAssertEqual(first.error, .offline); XCTAssertEqual(first.snapshot?.media, .movie(old))
        XCTAssertEqual(first.availability, .refreshDue(old.metadataRetrievedAt!))
        let deadline = store.metadataState(for: movieID)?.retryAfter
        let reopened = detailModel(movieID, service: service)
        await reopened.load(store: store)
        XCTAssertEqual(reopened.error, .refreshDeferred)
        XCTAssertEqual(store.metadataState(for: movieID)?.retryAfter, deadline)
        let calls = await service.calls; XCTAssertEqual(calls, 1)
        XCTAssertFalse(reopened.isLoading); XCTAssertFalse(reopened.isLoadingExtras)
    }

    @MainActor func testExplicitReconnectRefreshKeepsOfflinePersonalEdits() async throws {
        let store = try makeStore(); try seed(store)
        let service = OfflineFixtureService(movie: movie(title: "Updated metadata"), show: show())
        let model = detailModel(movieID, service: service)
        await model.load(store: store, force: true)
        XCTAssertEqual(model.error, .offline)
        let originalID = store.entry(for: movieID)?.id
        try store.setPersonalRating(PersonalRating(halfStarUnits: 10), media: .movie(movie()))
        try store.saveReview(id: LargeLibraryFixtures.uuid(1), media: .movie(movie()), text: "Latest private edit", now: now)
        try store.setStatus(.watchlist, media: .movie(movie()))
        await service.reconnect()
        await model.load(store: store, force: true)
        XCTAssertNil(model.error); XCTAssertEqual(SearchItem(model.snapshot!.media).title, "Updated metadata")
        XCTAssertEqual(store.entry(for: movieID)?.id, originalID)
        XCTAssertEqual(store.entry(for: movieID)?.ratingHalfStarUnits, 10)
        XCTAssertEqual(store.entry(for: movieID)?.status, "watchlist")
        XCTAssertEqual(store.reviews(for: movieID).first?.text, "Latest private edit")
        XCTAssertEqual(store.events(for: movieID).count, 1); XCTAssertTrue(store.isWatched(episode().id))
    }

    @MainActor func testExpiryRemembersOriginalReceiptButNotProviderContentOrNewLease() async throws {
        let store = try makeStore(), old = movie(fetched: now.addingTimeInterval(-MetadataPolicy.retention))
        try store.setPersonalRating(PersonalRating(halfStarUnits: 7), media: .movie(old))
        try store.maintainMetadata(at: now)
        XCTAssertNil(store.entries.first?.snapshotData); XCTAssertNil(store.entries.first?.savedTitle)
        XCTAssertEqual(store.metadataState(for: movieID)?.lastSuccessfulFetch, old.metadataRetrievedAt)
        let model = detailModel(movieID)
        await model.load(store: store)
        XCTAssertEqual(model.availability, .expired(old.metadataRetrievedAt!))
        XCTAssertEqual(SearchItem(model.snapshot!.media).title, MetadataPolicy.placeholder(movieID))
        XCTAssertEqual(store.entries.first?.ratingHalfStarUnits, 7)
        XCTAssertEqual(store.entries.count, 1); XCTAssertFalse(model.isLoading)
    }

    @MainActor func testUncachedOfflineTitleDoesNotCreateOrDeletePersonalRecord() async throws {
        let store = try makeStore(), service = OfflineFixtureService(movie: movie(), show: show())
        let model = detailModel(movieID, service: service)
        await model.load(store: store)
        XCTAssertEqual(model.availability, .unavailable); XCTAssertEqual(model.error, .offline)
        XCTAssertTrue(store.entries.isEmpty); XCTAssertFalse(model.isLoading)
        XCTAssertEqual(SearchItem(model.snapshot!.media).id, movieID)
    }

    @MainActor func testReviewOnlyAndSeasonOnlyRecordsRemainNavigableLocally() async throws {
        let store = try makeStore(); try seed(store)
        try store.remove(movieID); try store.remove(showID)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertNotNil(store.cachedMedia(for: movieID)); XCTAssertNotNil(store.cachedMedia(for: showID))
        let movieModel = detailModel(movieID), showModel = detailModel(showID)
        await movieModel.load(store: store); await showModel.load(store: store)
        XCTAssertNil(movieModel.error); XCTAssertNil(showModel.error)
        XCTAssertEqual(store.reviews(for: movieID).first?.text, "Private saved review")
        XCTAssertTrue(store.isWatched(episode().id)); XCTAssertTrue(store.entries.isEmpty)
    }

    @MainActor func testExpiredEpisodeFlagsRemainEditableWithoutInventingEpisodeMetadata() throws {
        let store = try makeStore(), old = now.addingTimeInterval(-MetadataPolicy.retention), series = show(fetched: now.addingTimeInterval(-MetadataPolicy.retention))
        let item = episode(fetched: old)
        try store.setEpisodeWatched(true, episode: item, show: series, now: now)
        try store.maintainMetadata(at: now)
        let row = try XCTUnwrap(store.seasons(for: showID).first)
        let saved = try XCTUnwrap(store.episodes(for: row).first)
        XCTAssertEqual(saved.number, 0); XCTAssertNil(saved.airDate)
        try store.setEpisodeWatched(false, episode: saved, show: series, now: now)
        try store.setEpisodeWatched(true, episode: saved, show: series, now: now)
        XCTAssertTrue(store.isWatched(item.id)); XCTAssertEqual(store.episodeProgress.count, 1)
        XCTAssertNil(store.seriesProgress(showID, now: now).percentage)
    }

    @MainActor func testOlderResponsesAndOldScreenEditsCannotDowngradeMetadata() throws {
        let store = try makeStore(), older = movie(fetched: now.addingTimeInterval(-10), title: "Old metadata"), newest = movie(title: "Newest metadata")
        try store.setStatus(.watched, media: .movie(newest))
        try store.metadataRefreshSucceeded(.movie(newest), posterURL: URL(string: "https://image.tmdb.org/t/p/w185/movie.png"))
        try store.metadataRefreshSucceeded(.movie(older))
        try store.setPersonalRating(PersonalRating(halfStarUnits: 9), media: .movie(older))
        XCTAssertEqual(store.entries.first?.savedTitle, "Newest metadata")
        XCTAssertEqual(store.entries.first?.ratingHalfStarUnits, 9)
        XCTAssertEqual(store.metadataState(for: movieID)?.lastSuccessfulFetch, now)
        XCTAssertNotNil(store.entries.first?.thumbnailURL)
        try store.metadataRefreshSucceeded(.movie(newest)) // Failed optional artwork does not erase a matching saved URL.
        XCTAssertNotNil(store.entries.first?.thumbnailURL)
    }

    @MainActor func testSeasonReconnectPreservesOfflineToggleAndRecoversFailedRefresh() async throws {
        let store = try makeStore(); try seed(store)
        let details = TVSeasonDetails(seriesID: showID, number: 1, name: "Season One", episodes: [episode()], metadataRetrievedAt: now)
        let service = OfflineFixtureService(movie: movie(), show: show(), season: details)
        let model = TVProgressModel(show: show(), service: service)
        await model.loadSeason(1, store: store, force: true)
        XCTAssertEqual(model.lastError, .offline); XCTAssertFalse(model.isLoading)
        try store.setEpisodeWatched(false, episode: episode(), show: show(), now: now)
        await service.reconnect()
        await model.loadSeason(1, store: store, force: true)
        XCTAssertNil(model.errorMessage); XCTAssertFalse(model.isLoading)
        XCTAssertFalse(store.isWatched(episode().id)); XCTAssertEqual(store.episodeProgress.count, 1)
        XCTAssertEqual(store.tvSeasons.first?.refreshedAt, now)
        let calls = await service.calls; XCTAssertEqual(calls, 2)
    }

    @MainActor func testOlderSeasonRefreshCannotReplaceNewerListingOrWatchedFlags() throws {
        let store = try makeStore(); try seed(store)
        var oldEpisode = episode(fetched: now.addingTimeInterval(-10)); oldEpisode.title = "Old episode"
        try store.cacheSeason(TVSeasonDetails(seriesID: showID, number: 1, name: "Old season", episodes: [oldEpisode], metadataRetrievedAt: now.addingTimeInterval(-10)), show: show(), now: now)
        XCTAssertEqual(store.tvSeasons.first?.name, "Season One")
        XCTAssertEqual(store.episodes(for: store.tvSeasons[0]).first?.title, "Saved episode")
        XCTAssertTrue(store.isWatched(episode().id))
    }
}

private actor OfflineFixtureService: MediaMetadataService {
    let movie: Movie, show: TVShow
    let season: TVSeasonDetails?
    private var offline = true
    private(set) var calls = 0
    init(movie: Movie, show: TVShow, season: TVSeasonDetails? = nil) { self.movie = movie; self.show = show; self.season = season }
    func tvSeasonDetails(for id: MediaID, number: Int) async throws -> TVSeasonDetails {
        calls += 1; if offline { throw MetadataError.offline }
        guard let season, season.seriesID == id, season.number == number else { throw MetadataError.notFound }
        return season
    }
    func reconnect() { offline = false }
    func movieDetails(id: MediaID) async throws -> Movie { calls += 1; if offline { throw MetadataError.offline }; return movie }
    func tvShowDetails(id: MediaID) async throws -> TVShow { calls += 1; if offline { throw MetadataError.offline }; return show }
    func imageResolver() async throws -> MetadataImageResolver { calls += 1; throw MetadataError.offline }
    func castPreview(for id: MediaID) async throws -> [CastMember] { calls += 1; if offline { throw MetadataError.offline }; return [] }
    func searchMovies(query: String, page: Int) async throws -> MetadataPage<Movie> { throw MetadataError.offline }
    func searchTVShows(query: String, page: Int) async throws -> MetadataPage<TVShow> { throw MetadataError.offline }
    func searchAll(query: String, page: Int) async throws -> MetadataPage<MediaSearchResult> { throw MetadataError.offline }
    func genres(for kind: MediaID.Kind) async throws -> [MediaGenre] { [] }
}
