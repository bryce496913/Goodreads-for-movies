import SwiftData
import XCTest
@testable import MovieTracker

final class PersonalStatisticsTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-17T12:00:00Z")!
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text + "T00:00:00Z")! }
    private func mediaID(_ value: String = "1", kind: MediaID.Kind = .movie) -> MediaID { .init(kind: kind, value: "fixture:" + value) }
    private func event(_ index: Int, id: MediaID? = nil, date: Date? = nil, data: Data? = nil) -> PersonalStatisticsInput.Viewing {
        .init(id: LargeLibraryFixtures.uuid(index), mediaID: id ?? mediaID(), watchedDate: date, mediaData: data)
    }
    private func title(_ index: Int, id: MediaID? = nil, units: Int? = nil, legacy: Double? = nil, data: Data? = nil) -> PersonalStatisticsInput.Title {
        .init(recordID: LargeLibraryFixtures.uuid(index), mediaID: id ?? mediaID(String(index)), updatedAt: now,
              ratingUnits: units, legacyRating: legacy, mediaData: data)
    }
    private func result(_ input: PersonalStatisticsInput, year: Int = 2026, zone: TimeZone = .gmt) throws -> PersonalStatisticsSnapshot {
        try DashboardAggregator.personalStatistics(input, year: year, now: now, timeZone: zone)
    }
    private func episode(_ value: String, date: Date?, watched: Bool = true) -> PersonalStatisticsInput.Episode {
        .init(id: EpisodeID(seriesID: mediaID(kind: .tvShow), providerValue: "fixture:" + value), watched: watched, markedAt: date)
    }

    func testEmptyDataHasTwelveMonthsTenHalfStarBucketsAndNoInventedActivity() throws {
        let value = try result(.init())
        XCTAssertEqual(value.months.count, 12); XCTAssertEqual(value.ratingBuckets.map(\.units), Array(1...10))
        XCTAssertEqual(value.movieEvents, 0); XCTAssertEqual(value.episodeMarks, 0)
        XCTAssertTrue(value.genres.isEmpty); XCTAssertNil(value.busiestMovieMonth)
        XCTAssertEqual(value.years, [2026])
    }
    func testYearsMonthsRepeatWatchesAndTypedUniqueIdentity() throws {
        let input = PersonalStatisticsInput(viewings: [
            event(1, date: date("2026-01-01")), event(2, date: date("2026-01-31")),
            event(3, date: date("2025-12-31")),
            event(4, id: mediaID(kind: .tvShow), date: date("2026-02-01"))
        ])
        let value = try result(input)
        XCTAssertEqual(value.movieEvents, 2); XCTAssertEqual(value.uniqueMovies, 1)
        XCTAssertEqual(value.seriesEvents, 1); XCTAssertEqual(value.uniqueSeries, 1)
        XCTAssertEqual(value.months[0].movieEvents, 2); XCTAssertEqual(value.months[1].seriesEvents, 1)
        XCTAssertEqual(value.years, [2026, 2025])
        XCTAssertEqual(try result(input, year: 2025).movieEvents, 1)
    }
    func testUndatedAndFutureEventsAreNotAssignedRecordedTimeOrToday() throws {
        let input = PersonalStatisticsInput(viewings: [event(1), event(2, date: date("2027-01-01")),
                                                      event(3, date: date("2026-11-18"))])
        let value = try result(input)
        XCTAssertEqual(value.movieEvents, 0); XCTAssertEqual(value.undatedEvents, 1)
        XCTAssertEqual(value.excludedEvents, 2); XCTAssertFalse(value.years.contains(2027))
    }
    func testLeapDayIsInFebruaryAndDiaryCivilDayDoesNotShiftTimeZones() throws {
        let input = PersonalStatisticsInput(viewings: [event(1, date: date("2024-02-29")), event(2, date: date("2024-01-01"))])
        for identifier in ["America/Los_Angeles", "Pacific/Kiritimati", "UTC"] {
            let value = try result(input, year: 2024, zone: XCTUnwrap(TimeZone(identifier: identifier)))
            XCTAssertEqual(value.months[1].movieEvents, 1); XCTAssertEqual(value.months[0].movieEvents, 1)
            XCTAssertEqual(value.movieEvents, 2)
        }
    }
    func testEveryValidRatingAndUnratedAndInvalidValues() throws {
        var input = PersonalStatisticsInput(titles: (1...10).map { title($0, units: $0) })
        input.titles += [title(11), title(12, legacy: 0), title(13, units: 0), title(14, units: 11), title(15, legacy: 2.3)]
        let value = try result(input)
        XCTAssertEqual(value.ratingBuckets.map(\.count), Array(repeating: 1, count: 10))
        XCTAssertEqual(value.unratedTitles, 2); XCTAssertEqual(value.invalidRatings, 3)
    }
    func testCurrentRatingsAreAllTimeAndChangesNeverPretendToBeHistorical() throws {
        var input = PersonalStatisticsInput(titles: [title(1, units: 7), title(2, legacy: 4.5)])
        XCTAssertEqual(try result(input, year: 2024).ratingBuckets, try result(input, year: 2026).ratingBuckets)
        input.titles[0] = title(1, units: 10)
        let value = try result(input, year: 2024)
        XCTAssertEqual(value.ratingBuckets[6].count, 0); XCTAssertEqual(value.ratingBuckets[9].count, 1)
        XCTAssertEqual(value.movieEvents, 0)
    }
    func testCanonicalTitleRatingAndDuplicateEventDoNotDoubleCount() throws {
        let row = title(1, units: 8), watch = event(1, date: date("2026-01-01"))
        let value = try result(.init(titles: [row, row], viewings: [watch, watch]))
        XCTAssertEqual(value.ratingBuckets[7].count, 1); XCTAssertEqual(value.movieEvents, 1)
    }
    func testGenreCountsUniqueTitlesAndMultipleGenresNotRewatches() throws {
        let drama = MediaGenre(id: "genre:drama", name: "Drama"), comedy = MediaGenre(id: "genre:comedy", name: "Comedy")
        let data = try JSONEncoder().encode(MediaSearchResult.movie(Movie(id: "fixture:1", title: "Story", genres: [drama, drama, comedy])))
        let value = try result(.init(titles: [title(1, id: mediaID(), data: data)], viewings: [
            event(1, date: date("2026-01-01")), event(2, date: date("2026-02-01"))]))
        XCTAssertEqual(value.genres.map(\.name), ["Comedy", "Drama"])
        XCTAssertEqual(value.genres.map(\.titles), [1, 1]); XCTAssertEqual(value.genreEligibleTitles, 1)
        XCTAssertEqual(value.movieEvents, 2)
    }
    func testGenresCanUseEligibleDiarySnapshotWhenLibraryMetadataIsMissing() throws {
        let data = try JSONEncoder().encode(MediaSearchResult.tvShow(TVShow(id: "fixture:1", title: "Series", genres: [.init(id: "1", name: "Drama")])))
        let value = try result(.init(viewings: [event(1, id: mediaID(kind: .tvShow), date: date("2026-01-01"), data: data)]))
        XCTAssertEqual(value.genres.first?.titles, 1); XCTAssertEqual(value.uniqueSeries, 1)
    }
    func testExpiredUnknownReceiptAndWrongIdentityGenresAreExcluded() throws {
        let id = MediaID(kind: .movie, value: "tmdb:1")
        for receipt in [Date?.none, now.addingTimeInterval(-MetadataPolicy.retention), now.addingTimeInterval(1)] {
            let data = try JSONEncoder().encode(MediaSearchResult.movie(Movie(id: id.value, title: "Expired", genres: [.init(id: "tmdb:18", name: "Drama")], metadataRetrievedAt: receipt)))
            let value = try result(.init(titles: [title(1, id: id, data: data)], viewings: [event(1, id: id, date: date("2026-01-01"))]))
            XCTAssertTrue(value.genres.isEmpty); XCTAssertEqual(value.missingGenreTitles, 1)
        }
        let wrong = try JSONEncoder().encode(MediaSearchResult.movie(Movie(id: "fixture:999", title: "Wrong", genres: [.init(id: "1", name: "Drama")])))
        let value = try result(.init(titles: [title(1, data: wrong)], viewings: [event(1, date: date("2026-01-01"))]))
        XCTAssertTrue(value.genres.isEmpty)
    }
    func testEligibleMetadataExpiresAtActualReceiptPlusLease() throws {
        let id = MediaID(kind: .movie, value: "tmdb:1"), receipt = now.addingTimeInterval(-86_400)
        let data = try JSONEncoder().encode(MediaSearchResult.movie(Movie(id: id.value, title: "Story", genres: [.init(id: "tmdb:18", name: "Drama")], metadataRetrievedAt: receipt)))
        let input = PersonalStatisticsInput(titles: [title(1, id: id, data: data)], viewings: [event(1, id: id, date: date("2026-01-01"))])
        let value = try result(input)
        XCTAssertEqual(value.nextMetadataExpiry, receipt.addingTimeInterval(MetadataPolicy.retention))
        let expired = try DashboardAggregator.personalStatistics(input, year: 2026, now: receipt.addingTimeInterval(MetadataPolicy.retention), timeZone: .gmt)
        XCTAssertTrue(expired.genres.isEmpty); XCTAssertEqual(expired.movieEvents, 1)
    }
    func testTVUsesCurrentMarkingTimestampAndExcludesUnknownAndUnwatched() throws {
        let value = try result(.init(episodes: [episode("1", date: date("2026-02-01")), episode("2", date: nil),
            episode("3", date: date("2025-01-01")), episode("4", date: date("2026-02-01"), watched: false),
            episode("5", date: date("2027-01-01"))]))
        XCTAssertEqual(value.episodeMarks, 1); XCTAssertEqual(value.months[1].episodeMarks, 1)
        XCTAssertEqual(value.overallWatchedEpisodes, 4); XCTAssertEqual(value.unknownEpisodeDates, 1)
        XCTAssertEqual(value.excludedEpisodeDates, 1); XCTAssertEqual(value.uniqueSeries, 0)
    }
    func testTVTimestampGroupsInLocalZoneWithoutChangingDiaryYear() throws {
        let stamp = ISO8601DateFormatter().date(from: "2026-01-01T01:00:00Z")!
        let input = PersonalStatisticsInput(viewings: [event(1, date: date("2026-01-01"))], episodes: [episode("1", date: stamp)])
        let pacific = try result(input, year: 2025, zone: XCTUnwrap(TimeZone(identifier: "America/Los_Angeles")))
        XCTAssertEqual(pacific.episodeMarks, 1); XCTAssertEqual(pacific.months[11].episodeMarks, 1)
        XCTAssertEqual(pacific.movieEvents, 0)
        XCTAssertEqual(try result(input).episodeMarks, 1)
    }
    func testDuplicateEpisodeFlagsDoNotInventRewatchesAndConflictsAreExcluded() throws {
        let first = episode("1", date: date("2026-01-01"))
        let conflict = episode("2", date: date("2026-01-01"))
        let value = try result(.init(episodes: [first, first, conflict, episode("2", date: nil, watched: false)]))
        XCTAssertEqual(value.overallWatchedEpisodes, 1); XCTAssertEqual(value.episodeMarks, 1)
        XCTAssertEqual(value.conflictingEpisodes, 1)
    }
    func testBusiestMonthTiesUseEarliestAndMissingGenresStayMissing() throws {
        let value = try result(.init(viewings: [event(1, date: date("2026-02-01")), event(2, date: date("2026-01-01"))]))
        XCTAssertEqual(value.busiestMovieMonth?.number, 1); XCTAssertEqual(value.activeMovieMonths, 2)
        XCTAssertEqual(value.missingGenreTitles, 1); XCTAssertTrue(value.genres.isEmpty)
    }

    func testInvalidReferenceDateAndYearAreRejected() {
        XCTAssertThrowsError(try DashboardAggregator.personalStatistics(.init(), year: 0, now: now, timeZone: .gmt))
        XCTAssertThrowsError(try DashboardAggregator.personalStatistics(.init(), year: 2026,
            now: Date(timeIntervalSinceReferenceDate: .nan), timeZone: .gmt))
    }

    func testExpiredTitleMetadataCannotRemovePersonalEpisodeTotals() throws {
        let id = MediaID(kind: .tvShow, value: "tmdb:1")
        let data = try JSONEncoder().encode(MediaSearchResult.tvShow(TVShow(id: id.value, title: "Expired",
            genres: [.init(id: "tmdb:18", name: "Drama")], metadataRetrievedAt: now.addingTimeInterval(-MetadataPolicy.retention))))
        let input = PersonalStatisticsInput(titles: [title(1, id: id, units: 8, data: data)],
            viewings: [event(1, id: id, date: date("2026-01-01"))],
            episodes: [.init(id: EpisodeID(seriesID: id, providerValue: "tmdb:10"), watched: true, markedAt: date("2026-01-01"))])
        let value = try result(input)
        XCTAssertTrue(value.genres.isEmpty); XCTAssertEqual(value.episodeMarks, 1)
        XCTAssertEqual(value.overallWatchedEpisodes, 1); XCTAssertEqual(value.ratingBuckets[7].count, 1)
    }

    @MainActor func testOfflineCaptureUpdatesAfterPersonalEditsWithoutChangingStore() async throws {
        let capturedNow = now
        let store = LibraryStore(container: try PersistenceController.makeContainer(inMemory: true), clock: { capturedNow })
        let movie = MediaSearchResult.movie(Movie(id: "fixture:1", title: "Offline"))
        try store.setStatus(.watchlist, media: movie)
        let model = PersonalStatisticsModel(now: now, timeZone: .gmt)
        var source = PersonalStatisticsModel.Source(revision: store.revision, invalidation: 0, year: 2026, timeZone: .gmt, referenceDate: now)
        await model.refresh(.capture(store), source: source)
        XCTAssertEqual(model.snapshot?.movieEvents, 0)
        try store.setPersonalRating(try PersonalRating(halfStarUnits: 9), media: movie)
        try store.saveViewingEvent(id: LargeLibraryFixtures.uuid(700), media: movie, watchedDate: date("2026-01-01"), now: now)
        source = .init(revision: store.revision, invalidation: 0, year: 2026, timeZone: .gmt, referenceDate: now)
        let revision = store.revision
        await model.refresh(.capture(store), source: source)
        XCTAssertEqual(model.snapshot?.movieEvents, 1); XCTAssertEqual(model.snapshot?.ratingBuckets[8].count, 1)
        XCTAssertEqual(store.entries.count, 1); XCTAssertEqual(store.viewingEvents.count, 1)
        XCTAssertEqual(store.entries.first?.status, "watchlist"); XCTAssertEqual(store.revision, revision)
    }
}
