import SwiftData
import XCTest
@testable import MovieTracker

final class TVProgressTests: XCTestCase {
    private let today = Date(timeIntervalSince1970: 1_767_225_600)
    private let aired = Date(timeIntervalSince1970: 1_577_836_800)

    func testEpisodeIdentityUsesProviderAndSeriesNotTitleOrPosition() {
        let first = episode("tmdb:1")
        var renamed = first; renamed.title = "Renamed"; renamed.number = 99; renamed.seasonNumber = 2
        XCTAssertEqual(first.id, renamed.id)
        XCTAssertNotEqual(first.id, episode("tmdb:2").id)
        let otherSeries = EpisodeID(seriesID: MediaID(kind: .tvShow, value: "other:series"), providerValue: "tmdb:1")
        XCTAssertNotEqual(first.id, otherSeries)
    }

    func testThreeOfTenThirtyPercentAndAllWatchedHundred() {
        let episodes = (1...10).map { episode("tmdb:\($0)", number: $0) }
        let partial = EpisodeProgressSummary.calculate(episodes: episodes, watchedIDs: Set(episodes.prefix(3).map(\.id)), coverageKnown: true, now: today)
        XCTAssertEqual(partial.percentage, 30)
        XCTAssertFalse(partial.isUpToDate)
        let complete = EpisodeProgressSummary.calculate(episodes: episodes, watchedIDs: Set(episodes.map(\.id)), coverageKnown: true, now: today)
        XCTAssertEqual(complete.percentage, 100)
        XCTAssertTrue(complete.isUpToDate)
        let zero = EpisodeProgressSummary.calculate(episodes: episodes, watchedIDs: [], coverageKnown: true, now: today)
        XCTAssertEqual(zero.percentage, 0)
    }

    @MainActor
    func testSingleEpisodeIdempotenceAndWatchingStatus() async throws {
        let store = try makeStore(), show = series()
        let value = episode("tmdb:1")
        try store.setEpisodeWatched(true, episode: value, show: show, now: today)
        let id = store.episodeProgress.first?.id
        try store.setEpisodeWatched(true, episode: value, show: show, now: today.addingTimeInterval(10))
        XCTAssertEqual(store.episodeProgress.count, 1)
        XCTAssertEqual(store.episodeProgress.first?.id, id)
        XCTAssertEqual(store.episodeProgress.first?.watchedAt, today)
        XCTAssertEqual(store.entries.first?.status, "watching")
        try store.setEpisodeWatched(false, episode: value, show: show)
        XCTAssertFalse(store.isWatched(value.id))
        XCTAssertEqual(store.episodeProgress.count, 1)
    }

    @MainActor
    func testFutureRejectedUnknownCanBeManuallyMarkedButExcluded() async throws {
        let store = try makeStore(), show = series()
        var future = episode("tmdb:future"); future.airDate = today.addingTimeInterval(86_400)
        var unknown = episode("tmdb:unknown"); unknown.airDate = nil
        XCTAssertThrowsError(try store.setEpisodeWatched(true, episode: future, show: show, now: today))
        try store.setEpisodeWatched(true, episode: unknown, show: show, now: today)
        let result = EpisodeProgressSummary.calculate(episodes: [future, unknown], watchedIDs: [unknown.id], coverageKnown: true, now: today)
        XCTAssertEqual(result.eligible, 0)
        XCTAssertEqual(result.totalWatched, 1)
        XCTAssertEqual(result.future, 1)
        XCTAssertEqual(result.unknownAirDate, 1)
        XCTAssertNil(result.percentage)
        XCTAssertFalse(result.isUpToDate)
    }

    @MainActor
    func testUnknownCountsNeverInventPercentage() async throws {
        let store = try makeStore()
        let show = series(count: nil)
        try store.cacheSeasonCatalog(show: show)
        try store.setEpisodeWatched(true, episode: episode("tmdb:1"), show: show, now: today)
        let season = try XCTUnwrap(store.seasons(for: show.id).first)
        XCTAssertNil(store.seasonProgress(season, now: today).percentage)
        XCTAssertNil(store.seriesProgress(show.id, now: today).percentage)
    }

    @MainActor
    func testSpecialsSeparateFromRegularSeriesProgress() async throws {
        let store = try makeStore()
        let show = TVShow(id: "tmdb:series", title: "Show", seasons: [summary(0, 1), summary(1, 1)])
        var special = episode("tmdb:special"); special.seasonNumber = 0
        let regular = episode("tmdb:regular")
        try store.cacheSeasonCatalog(show: show)
        try store.cacheSeason(TVSeasonDetails(seriesID: show.id, number: 0, name: "Specials", episodes: [special]), show: show)
        try store.cacheSeason(TVSeasonDetails(seriesID: show.id, number: 1, name: "Season 1", episodes: [regular]), show: show)
        try store.setEpisodeWatched(true, episode: special, show: show, now: today)
        XCTAssertEqual(store.seriesProgress(show.id, now: today).watched, 0)
        try store.setEpisodeWatched(true, episode: regular, show: show, now: today)
        XCTAssertTrue(store.seriesProgress(show.id, now: today).isUpToDate)
    }

    @MainActor
    func testSeasonBatchSkipsFutureAndUnknownAndCanReverse() async throws {
        let store = try makeStore(), show = series(count: 3)
        let one = episode("tmdb:one")
        var future = episode("tmdb:future"); future.airDate = today.addingTimeInterval(86_400)
        var unknown = episode("tmdb:unknown"); unknown.airDate = nil
        try store.cacheSeasonCatalog(show: show)
        try store.cacheSeason(TVSeasonDetails(seriesID: show.id, number: 1, name: "Season 1", episodes: [one, future, unknown]), show: show)
        let season = try XCTUnwrap(store.seasons(for: show.id).first)
        try store.setSeasonWatched(true, season: season, show: show, now: today)
        try store.setSeasonWatched(true, season: season, show: show, now: today)
        XCTAssertEqual(store.episodeProgress.count, 1)
        XCTAssertTrue(store.seasonProgress(season, now: today).isUpToDate)
        XCTAssertFalse(store.isWatched(unknown.id))
        XCTAssertFalse(store.isWatched(future.id))
        try store.setSeasonWatched(false, season: season, show: show)
        XCTAssertFalse(store.isWatched(one.id))
        XCTAssertEqual(store.seasonProgress(season, now: today).percentage, 0)
    }

    @MainActor
    func testOmittedEpisodeRemainsOfflineAndNeverLosesWatchedFlag() async throws {
        let store = try makeStore(), show = series(count: 2)
        let one = episode("tmdb:one"), two = episode("tmdb:two", number: 2)
        try store.cacheSeasonCatalog(show: show)
        try store.cacheSeason(TVSeasonDetails(seriesID: show.id, number: 1, name: "Season", episodes: [one, two]), show: show)
        try store.setEpisodeWatched(true, episode: two, show: show, now: today)
        try store.cacheSeason(TVSeasonDetails(seriesID: show.id, number: 1, name: "Season", episodes: [one]), show: show)
        let season = try XCTUnwrap(store.seasons(for: show.id).first)
        XCTAssertEqual(store.episodes(for: season).count, 2)
        XCTAssertTrue(store.isWatched(two.id))
        XCTAssertFalse(season.listedIDs.contains(two.id))
        XCTAssertNil(store.seasonProgress(season, now: today).percentage)
    }

    @MainActor
    func testStableProviderIDCanMoveSeasonsWithoutDuplicatingProgress() async throws {
        let store = try makeStore(), show = series()
        let original = episode("tmdb:one")
        try store.cacheSeasonCatalog(show: show)
        try store.cacheSeason(TVSeasonDetails(seriesID: show.id, number: 1, name: "One", episodes: [original]), show: show)
        try store.setEpisodeWatched(true, episode: original, show: show, now: today)
        var moved = original; moved.seasonNumber = 2; moved.number = 4; moved.title = "Updated title"
        try store.cacheSeason(TVSeasonDetails(seriesID: show.id, number: 2, name: "Two", episodes: [moved]), show: show)
        XCTAssertEqual(store.episodeProgress.count, 1)
        XCTAssertEqual(store.episodeProgress.first?.seasonNumber, 2)
        XCTAssertTrue(store.isWatched(moved.id))
        XCTAssertEqual(store.episodeProgress.first?.savedEpisode?.title, "Updated title")
    }

    @MainActor
    func testExistingWatchedRatingFavoriteAndDiaryArePreserved() async throws {
        let store = try makeStore(), show = series()
        try store.setStatus(.watched, media: .tvShow(show))
        try store.setPersonalRating(PersonalRating(halfStarUnits: 9), media: .tvShow(show))
        try store.setFavorite(true, media: .tvShow(show))
        try store.saveViewingEvent(id: UUID(), media: .tvShow(show), watchedDate: nil)
        try store.saveReview(id: UUID(), media: .tvShow(show), text: "Keep review")
        try store.setEpisodeWatched(true, episode: episode("tmdb:one"), show: show, now: today)
        XCTAssertEqual(store.entries.first?.status, "watched")
        XCTAssertEqual(store.entries.first?.ratingHalfStarUnits, 9)
        XCTAssertTrue(store.entries.first?.isFavorite == true)
        XCTAssertEqual(store.viewingEvents.count, 1)
        XCTAssertEqual(store.personalReviews.first?.text, "Keep review")
    }

    @MainActor
    func testOfflineMetadataAndProgressSurviveContainerReinitialization() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Episodes.store")
        let show = series(), value = episode("tmdb:one")
        try autoreleasepool {
            let store = LibraryStore(container: try PersistenceController.makeContainer(at: url))
            try store.cacheSeasonCatalog(show: show)
            try store.cacheSeason(TVSeasonDetails(seriesID: show.id, number: 1, name: "Season 1", episodes: [value]), show: show)
            try store.setEpisodeWatched(true, episode: value, show: show, now: today)
        }
        let reopened = LibraryStore(container: try PersistenceController.makeContainer(at: url))
        let season = try XCTUnwrap(reopened.seasons(for: show.id).first)
        XCTAssertEqual(reopened.episodes(for: season).first?.title, value.title)
        XCTAssertTrue(reopened.isWatched(value.id))
        try reopened.setEpisodeWatched(false, episode: value, show: show)
        XCTAssertFalse(reopened.isWatched(value.id))
    }

    @MainActor
    func testFailedWatchSaveRollsBackProgressAndImplicitLibraryRow() async throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let store = LibraryStore(container: container, save: { _ in throw LibraryStoreError.saveFailed })
        XCTAssertThrowsError(try store.setEpisodeWatched(true, episode: episode("tmdb:one"), show: series(), now: today))
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(store.episodeProgress.isEmpty)
    }

    @MainActor
    func testSeriesPercentageWaitsForEveryRegularSeasonListing() async throws {
        let store = try makeStore()
        let show = TVShow(id: "tmdb:series", title: "Show", seasons: [summary(1, 1), summary(2, 1)])
        try store.cacheSeasonCatalog(show: show)
        let first = episode("tmdb:one")
        try store.cacheSeason(TVSeasonDetails(seriesID: show.id, number: 1, name: "One", episodes: [first]), show: show)
        try store.setEpisodeWatched(true, episode: first, show: show, now: today)
        XCTAssertNil(store.seriesProgress(show.id, now: today).percentage)
        XCTAssertFalse(store.seriesProgress(show.id, now: today).isUpToDate)
    }

    @MainActor
    func testOlderSavedSnapshotCannotReplaceNewerPersistedCatalog() async throws {
        let store = try makeStore(), latest = series(count: 2)
        try store.cacheSeasonCatalog(show: latest)
        let old = TVShow(id: latest.id.value, title: latest.title, seasons: [])
        let model = TVProgressModel(show: old, service: nil)
        await model.loadCatalog(show: old, store: store, snapshotIsFresh: false)
        XCTAssertEqual(store.seasons(for: latest.id).count, 1)
        XCTAssertTrue(store.seasons(for: latest.id).first?.isListed == true)
    }

    @MainActor
    func testMovieIDsCannotBeUsedForEpisodeProgress() async throws {
        let store = try makeStore(), show = series()
        var invalid = episode("tmdb:one")
        invalid = TVEpisode(id: EpisodeID(seriesID: MediaID(kind: .movie, value: show.id.value), providerValue: invalid.id.providerValue),
            seasonNumber: 1, number: 1, title: "Invalid", airDate: aired, overview: "", runtimeMinutes: nil)
        XCTAssertThrowsError(try store.setEpisodeWatched(true, episode: invalid, show: show, now: today))
        XCTAssertTrue(store.episodeProgress.isEmpty)
        XCTAssertTrue(store.entries.isEmpty)
    }

    @MainActor
    func testCanceledLateSeasonResponseDoesNotReplaceCache() async throws {
        let store = try makeStore(), show = series()
        try store.cacheSeasonCatalog(show: show)
        let service = SuspendedSeasonService()
        let model = TVProgressModel(show: show, service: service)
        let task = Task { await model.loadSeason(1, store: store) }
        await service.waitUntilRequested()
        task.cancel()
        await service.complete(TVSeasonDetails(seriesID: show.id, number: 1, name: "Late", episodes: [episode("tmdb:late")]))
        await task.value
        XCTAssertTrue(store.seasons(for: show.id).first?.episodes.isEmpty == true)
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testLoadedSeasonMetadataRemainsReachableWithoutSavingLibraryTitle() async throws {
        let store = try makeStore(), show = series()
        try store.cacheSeasonCatalog(show: show)
        try store.cacheSeason(TVSeasonDetails(seriesID: show.id, number: 1, name: "Season 1", episodes: [episode("tmdb:one")]), show: show)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(store.savedTVShow(for: show.id)?.title, show.title)
        XCTAssertFalse(store.seasons(for: show.id).isEmpty)
        XCTAssertNil(store.savedTVShow(for: MediaID(kind: .movie, value: show.id.value)))
    }

    func testPreTrackingShowSnapshotDecodesWithoutNewSeasonField() throws {
        let old = Data(#"{"id":{"kind":"tvShow","value":"tmdb:123"},"title":"Saved Series","overview":"","genres":[],"genreIDs":[]}"#.utf8)
        let show = try JSONDecoder().decode(TVShow.self, from: old)
        XCTAssertNil(show.seasons)
        XCTAssertEqual(show.title, "Saved Series")
        XCTAssertEqual(show.id.kind, .tvShow)
    }

    @MainActor
    func testLargeSeasonCatalogKeepsNumericOrderAndStableIdentity() throws {
        let store = try makeStore()
        let seasons = (0...24).reversed().map { summary($0, nil) }
        let show = TVShow(id: "tmdb:series", title: "Large series", seasons: seasons)
        try store.cacheSeasonCatalog(show: show)
        let first = store.seasons(for: show.id)
        XCTAssertEqual(first.map(\.number), Array(0...24))
        let identities = first.map(\.id)
        try store.cacheSeasonCatalog(show: show)
        XCTAssertEqual(store.seasons(for: show.id).map(\.id), identities)
        XCTAssertEqual(store.episodeProgress.count, 0)
    }

    @MainActor
    func testDirectHomeActionIsIdempotentAndPreservesIndependentPersonalData() throws {
        let store = try makeStore()
        let (show, values) = try prepareHome(store)
        try store.setFavorite(true, media: .tvShow(show))
        try store.setPersonalRating(PersonalRating(halfStarUnits: 7), media: .tvShow(show))
        let review = UUID(), viewing = UUID()
        try store.saveReview(id: review, media: .tvShow(show), text: "Keep review", now: today)
        try store.saveViewingEvent(id: viewing, media: .tvShow(show), watchedDate: nil, now: today)
        let entry = try XCTUnwrap(store.entry(for: show.id)), updated = store.entry(for: show.id)?.updatedAt
        XCTAssertTrue(try store.markNextEpisodeWatched(values[1].id, now: today))
        let record = try XCTUnwrap(store.episodeProgress.first { $0.episodeID == values[1].id })
        let identity = record.id, marked = record.watchedAt
        XCTAssertFalse(try store.markNextEpisodeWatched(values[1].id, now: today.addingTimeInterval(1)))
        XCTAssertEqual(record.id, identity); XCTAssertEqual(record.watchedAt, marked)
        XCTAssertEqual(entry.status, "watchlist"); XCTAssertTrue(entry.isFavorite)
        XCTAssertEqual(entry.updatedAt, updated); XCTAssertEqual(try entry.validatedRating()?.halfStarUnits, 7)
        XCTAssertEqual(store.personalReviews.first?.text, "Keep review")
        XCTAssertEqual(store.viewingEvents.map(\.id), [viewing])
        XCTAssertEqual(store.seriesProgress(show.id, now: today).watched, 2)
        XCTAssertEqual(store.episodeProgress.count, 2)
    }

    @MainActor
    func testDirectHomeFailureRollsBackAndExplicitRetryRecovers() throws {
        var fail = false, writes = 0
        let store = LibraryStore(container: try PersistenceController.makeContainer(inMemory: true), save: { context in
            if fail { throw LibraryStoreError.saveFailed }
            writes += 1; try context.save()
        })
        let (show, values) = try prepareHome(store)
        let action = HomeEpisodeAction(), before = writes
        fail = true
        action.mark(values[1].id, store: store, now: today)
        XCTAssertNotNil(action.errorMessage); XCTAssertFalse(action.isSaving)
        XCTAssertFalse(store.isWatched(values[1].id)); XCTAssertEqual(writes, before)
        XCTAssertEqual(store.entry(for: show.id)?.status, "watchlist")
        fail = false
        action.mark(values[1].id, store: store, now: today)
        XCTAssertNil(action.errorMessage); XCTAssertTrue(store.isWatched(values[1].id))
        action.mark(values[1].id, store: store, now: today)
        XCTAssertEqual(writes, before + 1)
        XCTAssertTrue(store.viewingEvents.isEmpty)
    }

    @MainActor
    func testDirectHomeActionRejectsStaleCardsAndKeepsNamespacesIndependent() throws {
        let store = try makeStore()
        let (first, values) = try prepareHome(store, namespace: "fixture:1")
        let (other, others) = try prepareHome(store, namespace: "other:1")
        XCTAssertThrowsError(try store.markNextEpisodeWatched(values[2].id, now: today))
        XCTAssertTrue(try store.markNextEpisodeWatched(values[1].id, now: today))
        XCTAssertFalse(store.isWatched(others[1].id))
        XCTAssertEqual(store.seriesProgress(other.id, now: today).watched, 1)
        XCTAssertEqual(store.seriesProgress(first.id, now: today).watched, 2)
        let movie = EpisodeID(seriesID: MediaID(kind: .movie, value: first.id.value), providerValue: values[1].id.providerValue)
        XCTAssertThrowsError(try store.markNextEpisodeWatched(movie, now: today))
    }

    @MainActor
    func testDirectHomeProgressPersistsAcrossOfflineContainerReopening() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("HomeEpisodes.store")
        var target: EpisodeID?
        try autoreleasepool {
            let store = LibraryStore(container: try PersistenceController.makeContainer(at: url))
            let (_, values) = try prepareHome(store)
            target = values[1].id
            try store.markNextEpisodeWatched(values[1].id, now: today)
        }
        let reopened = LibraryStore(container: try PersistenceController.makeContainer(at: url))
        let exact = try XCTUnwrap(target)
        XCTAssertTrue(reopened.isWatched(exact))
        XCTAssertEqual(reopened.entry(for: exact.seriesID)?.status, "watchlist")
        XCTAssertTrue(reopened.viewingEvents.isEmpty)
        XCTAssertFalse(try reopened.markNextEpisodeWatched(exact, now: today))
    }

    @MainActor
    func testHomeActionRevalidatesAfterUnwatchAndMetadataRefresh() throws {
        let store = try makeStore()
        let (show, values) = try prepareHome(store)
        try store.markNextEpisodeWatched(values[1].id, now: today)
        try store.cacheSeason(TVSeasonDetails(seriesID: show.id, number: 1, name: "Season 1", episodes: values,
            metadataRetrievedAt: today), show: show)
        XCTAssertTrue(store.isWatched(values[1].id))
        try store.setEpisodeWatched(false, episode: values[0], show: show, now: today, updateViewingStatus: false)
        XCTAssertThrowsError(try store.markNextEpisodeWatched(values[2].id, now: today))
        XCTAssertFalse(store.isWatched(values[2].id))
        let incomplete = TVShow(id: show.id.value, title: show.title, seasons: [summary(1, 4)], metadataRetrievedAt: today)
        try store.cacheSeasonCatalog(show: incomplete)
        XCTAssertThrowsError(try store.markNextEpisodeWatched(values[0].id, now: today))
        XCTAssertTrue(store.isWatched(values[1].id))
        XCTAssertTrue(store.viewingEvents.isEmpty)
    }

    @MainActor private func prepareHome(_ store: LibraryStore, namespace: String = "fixture:home") throws -> (TVShow, [TVEpisode]) {
        let show = TVShow(id: namespace, title: "Home series", seasons: [summary(1, 3)], metadataRetrievedAt: today)
        let values = (1...3).map { number in
            TVEpisode(id: EpisodeID(seriesID: show.id, providerValue: "fixture:episode:\(number)"), seasonNumber: 1,
                number: number, title: "Episode \(number)", airDate: aired, overview: "", runtimeMinutes: nil, metadataRetrievedAt: today)
        }
        try store.cacheSeasonCatalog(show: show)
        try store.cacheSeason(TVSeasonDetails(seriesID: show.id, number: 1, name: "Season 1", episodes: values, metadataRetrievedAt: today), show: show)
        try store.setStatus(.watchlist, media: .tvShow(show))
        try store.setEpisodeWatched(true, episode: values[0], show: show, now: today, updateViewingStatus: false)
        return (show, values)
    }

    private func summary(_ number: Int, _ count: Int?) -> TVSeasonSummary {
        TVSeasonSummary(number: number, providerID: nil, name: "Season \(number)", episodeCount: count)
    }
    private func series(count: Int? = 1) -> TVShow { TVShow(id: "tmdb:series", title: "Show", seasons: [summary(1, count)]) }
    private func episode(_ id: String, number: Int = 1) -> TVEpisode {
        TVEpisode(id: EpisodeID(seriesID: MediaID(kind: .tvShow, value: "tmdb:series"), providerValue: id),
                  seasonNumber: 1, number: number, title: "Episode", airDate: aired, overview: "", runtimeMinutes: nil)
    }
    @MainActor private func makeStore() throws -> LibraryStore { LibraryStore(container: try PersistenceController.makeContainer(inMemory: true)) }
}

private actor SuspendedSeasonService: MediaMetadataService {
    private var pending: CheckedContinuation<TVSeasonDetails, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    func tvSeasonDetails(for id: MediaID, number: Int) async throws -> TVSeasonDetails {
        await withCheckedContinuation { pending = $0; observer?.resume(); observer = nil }
    }
    func waitUntilRequested() async { if pending == nil { await withCheckedContinuation { observer = $0 } } }
    func complete(_ value: TVSeasonDetails) { pending?.resume(returning: value); pending = nil }
    func searchMovies(query: String, page: Int) async throws -> MetadataPage<Movie> { throw MetadataError.invalidQuery }
    func searchTVShows(query: String, page: Int) async throws -> MetadataPage<TVShow> { throw MetadataError.invalidQuery }
    func searchAll(query: String, page: Int) async throws -> MetadataPage<MediaSearchResult> { throw MetadataError.invalidQuery }
    func movieDetails(id: MediaID) async throws -> Movie { throw MetadataError.invalidIdentifier }
    func tvShowDetails(id: MediaID) async throws -> TVShow { throw MetadataError.invalidIdentifier }
    func genres(for kind: MediaID.Kind) async throws -> [MediaGenre] { [] }
    func imageResolver() async throws -> MetadataImageResolver { throw MetadataError.invalidPayload }
}
