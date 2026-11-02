import SwiftData
import XCTest
@testable import MovieTracker

final class StabilizationTests: XCTestCase {
    @MainActor
    func testFullOfflinePersonalDataJourneySurvivesDiskReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Beta.store")
        let movie = MediaSearchResult.movie(Movie(id: "fixture:beta", title: "Offline Movie", overview: "Saved synopsis"))
        let date = Date(timeIntervalSince1970: 1_577_836_800)
        let show = TVShow(id: "fixture:beta", title: "Offline Series", seasons: [TVSeasonSummary(number: 1, providerID: nil, name: "Season 1", episodeCount: 2)])
        let episodes = (1...2).map { TVEpisode(id: EpisodeID(seriesID: show.id, providerValue: "fixture:episode:\($0)"),
            seasonNumber: 1, number: $0, title: "Episode \($0)", airDate: date, overview: "Saved episode", runtimeMinutes: nil) }
        let reviewID = UUID(), firstEvent = UUID(), repeatEvent = UUID()
        try autoreleasepool {
            let store = LibraryStore(container: try PersistenceController.makeContainer(at: url))
            try store.setStatus(.watchlist, media: movie)
            try store.setPersonalRating(PersonalRating(halfStarUnits: 7), media: movie)
            try store.setFavorite(true, media: movie)
            for status in [LibraryStatus.watched, .watchlist, .watched] { try store.setStatus(status, media: movie) }
            try store.saveViewingEvent(id: firstEvent, media: movie, watchedDate: date)
            try store.saveViewingEvent(id: repeatEvent, media: movie, watchedDate: nil)
            try store.saveReview(id: reviewID, media: movie, text: "Original", eventID: firstEvent)
            try store.saveReview(id: reviewID, media: movie, text: "Edited offline", eventID: firstEvent)
            try store.deleteViewingEvent(firstEvent)
            try store.cacheSeasonCatalog(show: show)
            try store.cacheSeason(TVSeasonDetails(seriesID: show.id, number: 1, name: "Season 1", episodes: episodes), show: show)
            try store.setEpisodeWatched(true, episode: episodes[0], show: show)
        }
        let store = LibraryStore(container: try PersistenceController.makeContainer(at: url))
        XCTAssertNil(store.loadError)
        let entry = try XCTUnwrap(store.entry(for: SearchItem(movie).id))
        XCTAssertEqual(entry.savedMedia, movie); XCTAssertEqual(entry.status, "watched")
        XCTAssertEqual(entry.ratingHalfStarUnits, 7); XCTAssertTrue(entry.isFavorite)
        XCTAssertEqual(store.personalReviews.first?.text, "Edited offline"); XCTAssertNil(store.personalReviews.first?.viewingEventID)
        XCTAssertEqual(store.viewingEvents.map(\.id), [repeatEvent]); XCTAssertTrue(store.isWatched(episodes[0].id))
        let model = SearchModel(service: nil).detailModel(for: SearchItem(movie).destination, savedMedia: entry.offlineMedia)
        await model.load()
        XCTAssertEqual(model.error, .missingCredential); XCTAssertEqual(model.snapshot?.media, movie)
        let season = try XCTUnwrap(store.seasons(for: show.id).first)
        try store.setSeasonWatched(true, season: season, show: show)
        XCTAssertEqual(store.seasonProgress(season).watched, 2)
        try store.setEpisodeWatched(false, episode: episodes[0], show: show)
        let snapshot = try DashboardAggregator.aggregate(DashboardInput.capture(store))
        XCTAssertEqual(snapshot.statistics.watchedMovies, 1); XCTAssertEqual(snapshot.statistics.viewingEvents, 1)
        XCTAssertEqual(snapshot.statistics.watchedEpisodes, 1); XCTAssertEqual(snapshot.statistics.averageRating, 3.5)
        XCTAssertEqual(snapshot.statistics.reviews, 1)
    }

    @MainActor
    func testFailedReviewDeletionAndEventInsertionKeepAllPersonalFields() async throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let movie = MediaSearchResult.movie(Movie(id: "fixture:rollback", title: "Keep all data"))
        let good = LibraryStore(container: container), review = UUID()
        try good.setPersonalRating(PersonalRating(halfStarUnits: 9), media: movie)
        try good.saveReview(id: review, media: movie, text: "Keep private text")
        let failing = LibraryStore(container: container, save: { _ in throw LibraryStoreError.saveFailed })
        XCTAssertThrowsError(try failing.deleteReview(review))
        XCTAssertThrowsError(try failing.saveViewingEvent(id: UUID(), media: movie, watchedDate: nil))
        XCTAssertEqual(failing.personalReviews.first?.text, "Keep private text")
        XCTAssertTrue(failing.viewingEvents.isEmpty); XCTAssertEqual(failing.entries.first?.ratingHalfStarUnits, 9)
    }

    @MainActor
    func testPreDashboardSchemaMigratesWithoutLosingExistingRecords() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Pre011.store")
        let movie = MediaSearchResult.movie(Movie(id: "fixture:legacy", title: "Legacy title"))
        let id = SearchItem(movie).id, reviewID = UUID(), eventID = UUID()
        try autoreleasepool {
            let schema = Schema([LibrarySchemaTVProgress.StoredLibraryEntry.self, StoredPersonalReview.self,
                StoredViewingEvent.self, StoredTVSeason.self, StoredEpisodeProgress.self])
            let old = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let row = LibrarySchemaTVProgress.StoredLibraryEntry(entry: UserLibraryEntry(mediaID: id, status: .watched,
                isFavorite: true, rating: try PersonalRating(halfStarUnits: 9), review: "Legacy reserved text"))
            row.savedTitle = "Legacy title"; row.snapshotData = try JSONEncoder().encode(movie)
            old.mainContext.insert(row)
            old.mainContext.insert(try StoredViewingEvent(id: eventID, media: movie, watchedDate: nil, recordedAt: .now))
            old.mainContext.insert(try StoredPersonalReview(id: reviewID, media: movie, text: "Separate review", createdAt: .now, viewingEventID: eventID))
            let show = TVShow(id: "fixture:legacy", title: "Legacy series")
            old.mainContext.insert(try StoredTVSeason(show: show, summary: TVSeasonSummary(number: 1, providerID: nil, name: "Season 1", episodeCount: 1)))
            let episode = TVEpisode(id: EpisodeID(seriesID: show.id, providerValue: "fixture:oldEpisode"), seasonNumber: 1,
                number: 1, title: "Old episode", airDate: nil, overview: "", runtimeMinutes: nil)
            old.mainContext.insert(try StoredEpisodeProgress(episode: episode, watched: true, now: .now))
            try old.mainContext.save()
        }
        let store = LibraryStore(container: try PersistenceController.makeContainer(at: url))
        let migrated = try XCTUnwrap(store.entry(for: id))
        XCTAssertNil(migrated.ratingUpdatedAt); XCTAssertEqual(migrated.ratingHalfStarUnits, 9)
        XCTAssertEqual(migrated.status, "watched"); XCTAssertTrue(migrated.isFavorite)
        XCTAssertEqual(migrated.review, "Legacy reserved text"); XCTAssertEqual(migrated.savedMedia, movie)
        XCTAssertEqual(store.viewingEvents.first?.id, eventID)
        XCTAssertEqual(store.personalReviews.first?.id, reviewID); XCTAssertEqual(store.personalReviews.first?.viewingEventID, eventID)
        XCTAssertEqual(store.tvSeasons.count, 1); XCTAssertTrue(store.episodeProgress.first?.isWatched == true)
    }
}
