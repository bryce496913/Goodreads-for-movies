import XCTest
@testable import MovieTracker

/// Run locally in Release with the same destination/configuration for both revisions.
/// No baseline or arbitrary pass/fail time threshold is embedded in these tests.
final class LargeLibraryBenchmarks: XCTestCase {
    func testBenchmarkFilter100() throws { try benchmarkFilter(100) }
    func testBenchmarkFilter1000() throws { try benchmarkFilter(1_000) }
    func testBenchmarkFilter5000() throws { try benchmarkFilter(5_000) }
    func testBenchmarkSort100() throws { try benchmarkSort(100) }
    func testBenchmarkSort1000() throws { try benchmarkSort(1_000) }
    func testBenchmarkSort5000() throws { try benchmarkSort(5_000) }
    func testBenchmarkSearch100() throws { try benchmarkSearch(100) }
    func testBenchmarkSearch1000() throws { try benchmarkSearch(1_000) }
    func testBenchmarkSearch5000() throws { try benchmarkSearch(5_000) }

    func testBenchmarkDashboard5000Diary10000Progress() throws {
        let input = try LargeLibraryFixtures.dashboard()
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            do { XCTAssertEqual(try DashboardAggregator.aggregate(input, now: LargeLibraryFixtures.now).statistics.viewingEvents, 5_000) }
            catch { XCTFail("Aggregation failed: \(error)") }
        }
    }
    @MainActor
    func testBenchmarkEpisodeUpdate10000Progress() throws {
        let store = try LargeLibraryFixtures.store()
        let episode = LargeLibraryFixtures.episode(0), show = TVShow(id: episode.id.seriesID.value, title: "Saved title")
        var watched = false
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            do { try store.setEpisodeWatched(watched, episode: episode, show: show, now: LargeLibraryFixtures.now); watched.toggle() }
            catch { XCTFail("Update failed: \(error)") }
        }
        XCTAssertEqual(store.episodeProgress.count, 10_000)
    }
    @MainActor
    func testBenchmarkIndexedHistory5000() throws {
        let store = try LargeLibraryFixtures.store(episodes: 0), id = LargeLibraryFixtures.mediaID(1)
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            for _ in 0..<100 { XCTAssertEqual(store.events(for: id).count, 50) }
        }
    }
    @MainActor
    func testBenchmarkReferenceScanHistory5000() throws {
        let store = try LargeLibraryFixtures.store(episodes: 0), id = LargeLibraryFixtures.mediaID(1)
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            for _ in 0..<100 { XCTAssertEqual(store.viewingEvents.filter { $0.mediaID == id }.count, 50) }
        }
    }
    @MainActor
    func testBenchmarkIndexedEpisodeReads10000() throws {
        let store = try LargeLibraryFixtures.store(events: 0)
        let values = (0..<100).map { LargeLibraryFixtures.episode($0 * 101) }
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            XCTAssertEqual(values.filter { store.isWatched($0.id) }.count, 50)
        }
    }
    @MainActor
    func testBenchmarkReferenceScanEpisodeReads10000() throws {
        let store = try LargeLibraryFixtures.store(events: 0)
        let values = (0..<100).map { LargeLibraryFixtures.episode($0 * 101) }
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            XCTAssertEqual(values.filter { episode in store.episodeProgress.first { $0.episodeID == episode.id }?.isWatched == true }.count, 50)
        }
    }
    private func benchmarkFilter(_ count: Int) throws {
        let items = try LargeLibraryFixtures.items(count)
        let options = LibraryOptions(media: .tvShows, status: .watching, favoritesOnly: true)
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            do { XCTAssertFalse(try LibraryProjection.filter(items, query: "", options: options).isEmpty) }
            catch { XCTFail("Filter failed: \(error)") }
        }
    }
    private func benchmarkSort(_ count: Int) throws {
        let items = try LargeLibraryFixtures.items(count)
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            do { XCTAssertEqual(try LibraryProjection.sort(items, by: .rating).count, count) }
            catch { XCTFail("Sort failed: \(error)") }
        }
    }
    private func benchmarkSearch(_ count: Int) throws {
        let items = try LargeLibraryFixtures.items(count)
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            do { XCTAssertEqual(try LibraryProjection.filter(items, query: "  CAFE  ", options: LibraryOptions()).count, count / 4) }
            catch { XCTFail("Search failed: \(error)") }
        }
    }
}
