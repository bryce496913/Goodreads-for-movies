import XCTest
@testable import MovieTracker

/// Native-only reproducible measurements. Fixtures live exclusively in the test target;
/// setup is outside measurement and no arbitrary timing threshold or speedup is claimed.
final class V07PerformanceBenchmarks: XCTestCase {
    func testBenchmarkCalendarGrouping5000DiaryEvents() throws {
        let input = try LargeLibraryFixtures.dashboard(titles: 1_000, episodes: 0, events: 5_000)
        let stamps = input.viewings.map { ViewingCalendarStamp(id: $0.id, watchedDate: $0.watchedDate, recordedAt: $0.recordedAt) }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt; calendar.firstWeekday = 2
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            do {
                let result = try ViewingCalendarProjection.index(stamps, calendar: calendar)
                XCTAssertEqual(result.days.values.reduce(0) { $0 + $1.count }, 4_000)
                XCTAssertEqual(result.undated.count, 1_000)
            } catch { XCTFail("Calendar fixture aggregation failed") }
        }
    }
    @MainActor func testBenchmarkFastLoggingInto1000Titles5000DiaryEvents() throws {
        let store = try LargeLibraryFixtures.store(titles: 1_000, episodes: 0, events: 5_000)
        try store.maintainMetadata()
        let media = MediaSearchResult.movie(Movie(id: "fixture:v07-benchmark", title: "Fixture movie"))
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            let command = MovieWatchLog(eventID: UUID(), reviewID: UUID(), watchedDate: nil, rating: .unchanged, review: nil)
            do { try store.logMovieWatch(command, media: media, now: LargeLibraryFixtures.now, timeZone: .gmt) }
            catch { XCTFail("Fast-log fixture transaction failed") }
        }
        // Each iteration intentionally adds one independent undated event; no deletion/reset is timed.
        XCTAssertGreaterThan(store.viewingEvents.count, 5_000)
    }
}
