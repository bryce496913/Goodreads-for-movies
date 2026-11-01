import SwiftData
import XCTest
@testable import MovieTracker

final class DashboardTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_767_225_600)
    private let aired = Date(timeIntervalSince1970: 1_577_836_800)
    private func id(_ value: String = "1", _ kind: MediaID.Kind = .movie) -> MediaID { MediaID(kind: kind, value: "fixture:" + value) }
    private func title(_ media: MediaID, status: String = "none", favorite: Bool = false, units: Int? = nil,
                       legacy: Double? = nil, ratingDate: Date? = nil, review: String? = nil) -> DashboardInput.Title {
        DashboardInput.Title(recordID: UUID(), mediaID: media, title: "Title " + media.value, year: nil, posterURL: nil,
            status: status, favorite: favorite, addedAt: now, updatedAt: now, ratingUnits: units, legacyRating: legacy,
            ratingUpdatedAt: ratingDate, legacyReview: review, mediaData: nil)
    }
    private func event(_ media: MediaID, watched: Date? = nil, recorded: Date? = nil) -> DashboardInput.Viewing {
        DashboardInput.Viewing(id: UUID(), mediaID: media, title: "Saved watch", watchedDate: watched, recordedAt: recorded ?? now, mediaData: nil)
    }
    private func episode(_ number: Int, series: MediaID? = nil, date: Date? = nil, season: Int = 1) -> TVEpisode {
        TVEpisode(id: EpisodeID(seriesID: series ?? id("1", .tvShow), providerValue: "fixture:episode:\(number)"),
                  seasonNumber: season, number: number, title: "Episode \(number)", airDate: date ?? aired, overview: "", runtimeMinutes: nil)
    }
    private func progress(_ episode: TVEpisode, watched: Bool = true) throws -> DashboardInput.Progress {
        DashboardInput.Progress(id: UUID(), episodeID: episode.id, season: episode.seasonNumber,
            watched: watched, watchedAt: watched ? now : nil, episodeData: try JSONEncoder().encode(episode))
    }
    private func season(_ episodes: [TVEpisode], complete: Bool = true) throws -> DashboardInput.Season {
        let series = try XCTUnwrap(episodes.first?.id.seriesID)
        return DashboardInput.Season(id: UUID(), seriesID: series, title: "Series", number: 1,
            expectedEpisodes: episodes.count, expectedRegularSeasons: 1, listed: true, loaded: complete,
            episodesData: try JSONEncoder().encode(episodes), listedIDsData: try JSONEncoder().encode(episodes.map(\.id)),
            seriesData: nil, refreshedAt: now)
    }
    private func result(_ input: DashboardInput) throws -> DashboardSnapshot { try DashboardAggregator.aggregate(input, now: now) }

    func testEmptyProfileHasZeroCountsAndUnavailableAverage() throws {
        let value = try result(DashboardInput())
        XCTAssertEqual(value.statistics, ViewingStatistics(watchedMovies: 0, seriesWithProgress: 0, watchedEpisodes: 0,
            watchlist: 0, favorites: 0, ratings: 0, averageRating: nil, reviews: 0, viewingEvents: 0))
        XCTAssertFalse(value.hasPersonalData)
    }
    func testUniqueWatchedMoviesUnionStatusAndRepeatEvents() throws {
        let input = DashboardInput(titles: [title(id(), status: "watched"), title(id("2"), status: "watched")],
                                  viewings: [event(id()), event(id()), event(id("3"))])
        XCTAssertEqual(try result(input).statistics.watchedMovies, 3)
        XCTAssertEqual(try result(input).statistics.viewingEvents, 3)
    }
    func testMediaTypeAndProviderIdentityRemainDistinct() throws {
        let input = DashboardInput(titles: [title(id(), units: 2), title(id("1", .tvShow), units: 10),
            title(MediaID(kind: .movie, value: "other:1"), status: "watched")])
        XCTAssertEqual(try result(input).statistics.ratings, 2)
        XCTAssertEqual(try result(input).statistics.watchedMovies, 1)
    }
    func testDuplicateLogicalTitlesAndEventsAreNotCountedTwice() throws {
        let row = title(id(), status: "watchlist", favorite: true, units: 8), viewing = event(id())
        let input = DashboardInput(titles: [row, title(id(), status: "watchlist", favorite: true, units: 8)], viewings: [viewing, viewing])
        let value = try result(input)
        XCTAssertEqual(value.statistics.watchlist, 1); XCTAssertEqual(value.statistics.favorites, 1)
        XCTAssertEqual(value.statistics.ratings, 1); XCTAssertEqual(value.statistics.viewingEvents, 1)
        XCTAssertEqual(value.duplicateTitles, 1)
    }
    func testAverageExcludesUnratedZeroAndInvalidRatings() throws {
        let rows = [title(id("1"), units: 1), title(id("2"), units: 10), title(id("3")),
                    title(id("4"), legacy: 0), title(id("5"), units: 0), title(id("6"), legacy: 2.7)]
        let value = try result(DashboardInput(titles: rows))
        XCTAssertEqual(value.statistics.averageRating, 2.75)
        XCTAssertEqual(value.statistics.ratings, 2); XCTAssertEqual(value.invalidRatings, 2)
    }
    func testLegacyValidRatingCountsWithoutInventingRatingActivity() throws {
        let value = try result(DashboardInput(titles: [title(id(), legacy: 3.5)]))
        XCTAssertEqual(value.statistics.averageRating, 3.5); XCTAssertTrue(value.activity.isEmpty)
    }
    func testAllValidHalfStarValuesProducePreciseMean() throws {
        let rows = (1...10).map { title(id(String($0)), units: $0) }
        XCTAssertEqual(try result(DashboardInput(titles: rows)).statistics.averageRating, 2.75)
    }
    func testFavoritesIndependentOfStatusAndWatchlistUsesExactStatus() throws {
        let rows = [title(id(), status: "watched", favorite: true), title(id("2"), favorite: true), title(id("3"), status: "watchlist")]
        let value = try result(DashboardInput(titles: rows))
        XCTAssertEqual(value.statistics.favorites, 2); XCTAssertEqual(value.statistics.watchlist, 1)
    }
    func testReviewCountIncludesNonemptyLegacyRecordsAndDeduplicatesUUID() throws {
        let review = DashboardInput.Review(id: UUID(), mediaID: id(), title: "Title", text: "Private review", createdAt: aired, editedAt: now, imported: false)
        let empty = DashboardInput.Review(id: UUID(), mediaID: id(), title: "Title", text: " \n ", createdAt: now, editedAt: now, imported: false)
        let value = try result(DashboardInput(titles: [title(id(), review: "Older private text")], reviews: [review, review, empty]))
        XCTAssertEqual(value.statistics.reviews, 2); XCTAssertEqual(value.activity.first?.label, "Review edited")
    }
    func testOldWatchLoggedTodayDoesNotDisplaceRecentlyWatched() throws {
        let old = event(id(), watched: aired, recorded: now)
        let recent = event(id("2"), watched: now.addingTimeInterval(-86_400), recorded: now.addingTimeInterval(-86_400))
        let value = try result(DashboardInput(viewings: [old, recent]))
        XCTAssertEqual(value.recentlyWatched.first?.id, recent.id)
        XCTAssertEqual(value.activity.first?.id, "viewing:" + old.id.uuidString)
    }
    func testUndatedAndFutureWatchesAreNotPresentedAsRecentActualWatches() throws {
        let value = try result(DashboardInput(viewings: [event(id()), event(id("2"), watched: now.addingTimeInterval(86_400))]))
        XCTAssertTrue(value.recentlyWatched.isEmpty); XCTAssertEqual(value.recentDiary.count, 2)
        XCTAssertEqual(value.statistics.watchedMovies, 1)
    }
    func testActivityUsesPersistedRatingTimestampAndStableTies() throws {
        let input = DashboardInput(titles: [title(id(), units: 8, ratingDate: now), title(id("2"), ratingDate: now)],
                                   viewings: [event(id(), recorded: aired)])
        let a = try result(input), b = try result(input)
        XCTAssertEqual(a.activity.map(\.id), b.activity.map(\.id))
        XCTAssertEqual(a.activity.first?.date, now)
        XCTAssertTrue(a.activity.contains { $0.label == "Personal rating cleared" })
    }
    func testSeriesAndEpisodeCountsDeduplicateCurrentFlagsIncludingSpecials() throws {
        let first = try progress(episode(1)), special = try progress(episode(2, season: 0))
        let off = try progress(episode(3), watched: false)
        let value = try result(DashboardInput(progress: [first, first, special, off]))
        XCTAssertEqual(value.statistics.watchedEpisodes, 2); XCTAssertEqual(value.statistics.seriesWithProgress, 1)
    }
    func testContinueWatchingSelectsNextKnownAiredEpisode() throws {
        let episodes = [episode(1), episode(2), episode(3, date: now.addingTimeInterval(86_400))]
        let value = try result(DashboardInput(progress: [try progress(episodes[0])], seasons: [try season(episodes)]))
        XCTAssertEqual(value.continueWatching.first?.next?.number, 2)
        XCTAssertEqual(value.continueWatching.first?.progress.percentage, 50)
    }
    func testFutureOnlyRemainingDoesNotOfferContinueWatching() throws {
        let episodes = [episode(1), episode(2, date: now.addingTimeInterval(86_400))]
        let value = try result(DashboardInput(progress: [try progress(episodes[0])], seasons: [try season(episodes)]))
        XCTAssertTrue(value.continueWatching.isEmpty)
    }
    func testIncompleteCoverageShowsProgressWithoutInventingNext() throws {
        let episodes = [episode(1), episode(2)]
        let value = try result(DashboardInput(progress: [try progress(episodes[0])], seasons: [try season(episodes, complete: false)]))
        XCTAssertNil(value.continueWatching.first?.next); XCTAssertNil(value.continueWatching.first?.progress.percentage)
        XCTAssertEqual(value.continueWatching.first?.lastMarked?.number, 1)
    }
    func testUnknownAirDateWithholdsNextEpisode() throws {
        var unknown = episode(2); unknown.airDate = nil
        let episodes = [episode(1), unknown, episode(3)]
        let value = try result(DashboardInput(progress: [try progress(episodes[0])], seasons: [try season(episodes)]))
        XCTAssertNil(value.continueWatching.first?.next)
    }
    func testLargeOfflineFixtureHasExpectedCountsAndBoundedSections() throws {
        let input = try largeFixture()
        let value = try result(input)
        XCTAssertEqual(value.statistics.watchedMovies, 60)
        XCTAssertEqual(value.statistics.seriesWithProgress, 50); XCTAssertEqual(value.statistics.watchedEpisodes, 1_000)
        XCTAssertEqual(value.statistics.watchlist, 40); XCTAssertEqual(value.statistics.ratings, 30)
        XCTAssertEqual(value.statistics.averageRating, 4)
        XCTAssertEqual(value.continueWatching.count, 5); XCTAssertEqual(value.watchlist.count, 5)
        XCTAssertEqual(value.recentDiary.count, 5)
        XCTAssertEqual(try result(input).continueWatching.map(\.id), value.continueWatching.map(\.id))
    }
    func testLargeFixtureAggregationPerformance() throws {
        let input = try largeFixture()
        measure { XCTAssertNoThrow(try DashboardAggregator.aggregate(input, now: self.now)) }
    }
    @MainActor func testLiveSnapshotRefreshesAfterStoreRevision() async throws {
        let store = LibraryStore(container: try PersistenceController.makeContainer(inMemory: true))
        let model = DashboardModel()
        await model.refresh(DashboardInput.capture(store), revision: store.revision, now: now)
        XCTAssertEqual(model.snapshot?.statistics.watchlist, 0)
        try store.setStatus(.watchlist, media: .movie(Movie(id: "fixture:new", title: "New saved movie")))
        await model.refresh(DashboardInput.capture(store), revision: store.revision, now: now)
        XCTAssertEqual(model.snapshot?.statistics.watchlist, 1)
        XCTAssertFalse(model.needsRefresh(revision: store.revision, now: now))
        XCTAssertTrue(model.needsRefresh(revision: store.revision, now: now.addingTimeInterval(86_400)))
    }
    @MainActor func testRatingTimestampDoesNotChangeOnFavoriteOrStatusMutation() async throws {
        let store = LibraryStore(container: try PersistenceController.makeContainer(inMemory: true))
        let movie = MediaSearchResult.movie(Movie(id: "fixture:rating", title: "Rating"))
        try store.setPersonalRating(PersonalRating(halfStarUnits: 8), media: movie)
        let record = try XCTUnwrap(store.entry(for: SearchItem(movie).id)), date = try XCTUnwrap(record.ratingUpdatedAt)
        try store.setFavorite(true, for: SearchItem(movie).id)
        try store.setStatus(.watched, media: movie)
        XCTAssertEqual(store.entry(for: SearchItem(movie).id)?.ratingUpdatedAt, date)
    }
    @MainActor func testTimestampAndPersonalDataSurviveContainerReinitialization() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Dashboard.store")
        let movie = MediaSearchResult.movie(Movie(id: "fixture:persist", title: "Persistent title"))
        var timestamp: Date?
        try autoreleasepool {
            let store = LibraryStore(container: try PersistenceController.makeContainer(at: url))
            try store.setStatus(.watched, media: movie)
            try store.setPersonalRating(PersonalRating(halfStarUnits: 9), media: movie)
            timestamp = store.entries.first?.ratingUpdatedAt
        }
        let reopened = LibraryStore(container: try PersistenceController.makeContainer(at: url))
        let snapshot = try result(DashboardInput.capture(reopened))
        XCTAssertNotNil(timestamp); XCTAssertEqual(reopened.entries.first?.ratingUpdatedAt, timestamp)
        XCTAssertEqual(snapshot.statistics.watchedMovies, 1); XCTAssertEqual(snapshot.statistics.averageRating, 4.5)
    }
    @MainActor func testRepeatedRatingIsIdempotentAndClearingDoesNotEraseStatus() async throws {
        let store = LibraryStore(container: try PersistenceController.makeContainer(inMemory: true))
        let movie = MediaSearchResult.movie(Movie(id: "fixture:repeat", title: "Repeated rating"))
        try store.setStatus(.watched, media: movie)
        try store.setPersonalRating(PersonalRating(halfStarUnits: 8), media: movie)
        let timestamp = store.entries.first?.ratingUpdatedAt
        try store.setPersonalRating(PersonalRating(halfStarUnits: 8), media: movie)
        XCTAssertEqual(store.entries.first?.ratingUpdatedAt, timestamp)
        try store.setPersonalRating(nil, media: movie)
        let snapshot = try result(DashboardInput.capture(store))
        XCTAssertEqual(snapshot.statistics.ratings, 0); XCTAssertNil(snapshot.statistics.averageRating)
        XCTAssertEqual(snapshot.statistics.watchedMovies, 1)
        XCTAssertEqual(snapshot.activity.first?.label, "Personal rating cleared")
    }
    func testCanceledAggregationDoesNotProduceSnapshot() async {
        let work = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try DashboardAggregator.aggregate(DashboardInput())
        }
        do { _ = try await work.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
    private func largeFixture() throws -> DashboardInput {
        var input = DashboardInput()
        for number in 0..<100 {
            input.titles.append(title(id("movie:\(number)"), status: number < 60 ? "watched" : "watchlist", favorite: number < 10, units: number < 30 ? 8 : nil))
        }
        for number in 0..<50 {
            let series = id("series:\(number)", .tvShow)
            input.titles.append(title(series, status: "watching"))
            let episodes = (1...21).map { episode($0, series: series) }
            input.seasons.append(try season(episodes))
            input.progress += try episodes.prefix(20).map { try progress($0) }
        }
        input.viewings = (0..<8).map { event(id("movie:\($0 % 3)"), watched: now.addingTimeInterval(Double(-$0) * 86_400)) }
        return input
    }
}
