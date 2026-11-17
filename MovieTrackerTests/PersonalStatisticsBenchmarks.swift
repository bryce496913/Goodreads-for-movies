import XCTest
@testable import MovieTracker

/// Deterministic fixtures and reproducible native measurements; no invented time thresholds.
final class PersonalStatisticsBenchmarks: XCTestCase {
    func testLargeDatasetHasAccurateDiaryRatingsAndEpisodeTotals() throws {
        let input = try fixture()
        let diary = try DashboardAggregator.personalStatistics(input, year: 2020, now: LargeLibraryFixtures.now, timeZone: .gmt)
        XCTAssertEqual(input.titles.count, 1_000); XCTAssertEqual(input.viewings.count, 5_000)
        XCTAssertEqual(input.episodes.count, 10_000)
        XCTAssertEqual(diary.movieEvents, 2_000); XCTAssertEqual(diary.seriesEvents, 2_000)
        XCTAssertEqual(diary.uniqueMovies, 40); XCTAssertEqual(diary.uniqueSeries, 40)
        XCTAssertEqual(diary.undatedEvents, 1_000); XCTAssertEqual(diary.missingGenreTitles, 0)
        XCTAssertEqual(diary.genres.map(\.titles), [80, 40])
        XCTAssertEqual(diary.ratingBuckets.reduce(0) { $0 + $1.count }, 800)
        let current = try DashboardAggregator.personalStatistics(input, year: 2026, now: LargeLibraryFixtures.now, timeZone: .gmt)
        XCTAssertEqual(current.episodeMarks, 5_000); XCTAssertEqual(current.overallWatchedEpisodes, 5_000)
    }
    func testBenchmarkStatistics1000Titles5000Diary10000Episodes() throws {
        let input = try fixture()
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            do {
                let result = try DashboardAggregator.personalStatistics(input, year: 2020, now: LargeLibraryFixtures.now, timeZone: .gmt)
                XCTAssertEqual(result.movieEvents, 2_000)
            } catch { XCTFail("Statistics fixture aggregation failed: \(error)") }
        }
    }
    private func fixture() throws -> PersonalStatisticsInput {
        let value = try LargeLibraryFixtures.dashboard(titles: 1_000, episodes: 10_000, events: 5_000)
        let titles = try value.titles.map { row -> PersonalStatisticsInput.Title in
            let id = try XCTUnwrap(row.mediaID)
            var genres = [MediaGenre(id: "fixture:drama", name: "Drama")]
            if id.kind == .tvShow { genres.append(MediaGenre(id: "fixture:comedy", name: "Comedy")) }
            let media: MediaSearchResult = id.kind == .movie
                ? .movie(Movie(id: id.value, title: "Fixture", genres: genres))
                : .tvShow(TVShow(id: id.value, title: "Fixture", genres: genres))
            return .init(recordID: row.recordID, mediaID: id, updatedAt: row.updatedAt,
                         ratingUnits: row.ratingUnits, legacyRating: row.legacyRating, mediaData: try JSONEncoder().encode(media))
        }
        return PersonalStatisticsInput(titles: titles, viewings: value.viewings.map {
            .init(id: $0.id, mediaID: $0.mediaID, watchedDate: $0.watchedDate, mediaData: $0.mediaData)
        }, episodes: value.progress.map { .init(id: $0.episodeID, watched: $0.watched, markedAt: $0.watchedAt) })
    }
}
