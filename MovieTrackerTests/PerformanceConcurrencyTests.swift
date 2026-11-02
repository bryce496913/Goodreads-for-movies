import SwiftData
import XCTest
@testable import MovieTracker

final class PerformanceConcurrencyTests: XCTestCase {
    func testDeterministicFixtureSizesAndDashboardCounts() throws {
        for count in [100, 1_000, 5_000] {
            let items = try LargeLibraryFixtures.items(count)
            XCTAssertEqual(items.count, count); XCTAssertEqual(Set(items.map(\.id)).count, count)
            let ordered = try LibraryProjection.sort(items, by: .title)
            XCTAssertEqual(ordered.map(\.id), try LibraryProjection.sort(Array(items.reversed()), by: .title).map(\.id))
            XCTAssertEqual(try LibraryProjection.filter(ordered, query: "cafe", options: LibraryOptions()).count, count / 4)
        }
        let input = try LargeLibraryFixtures.dashboard()
        XCTAssertEqual(input.progress.count, 10_000); XCTAssertEqual(input.viewings.count, 5_000)
        let result = try DashboardAggregator.aggregate(input, now: LargeLibraryFixtures.now)
        XCTAssertEqual(result.statistics.watchedEpisodes, 5_000)
        XCTAssertEqual(result.statistics.seriesWithProgress, 100)
        XCTAssertEqual(result.statistics.viewingEvents, 5_000)
        XCTAssertEqual(result.statistics.ratings, 4_000)
        XCTAssertEqual(result.statistics.favorites, 715)
        XCTAssertEqual(result.statistics.watchedMovies, 866) // 833 odd multiples of 3, plus 33 other watched diary titles.
    }

    @MainActor
    func testRapidQueryFilterSortReplacementPublishesOnlyNewestProjection() async throws {
        let model = LibraryOrganizationModel(), values = try LargeLibraryFixtures.items(5_000)
        model.replaceItems(values)
        for i in 0..<30 {
            model.query = i.isMultiple(of: 2) ? "Title" : "Café"
            model.options.sort = i.isMultiple(of: 2) ? .year : .rating
            model.options.media = i.isMultiple(of: 2) ? .movies : .tvShows
        }
        await model.waitForUpdates()
        let expected = try LibraryProjection.project(source: values, sorted: nil, query: model.query, options: model.options)
        XCTAssertEqual(model.visible.map(\.id), expected.visible.map(\.id))
        XCTAssertFalse(model.isUpdating)
    }

    @MainActor
    func testCanceledProjectionCannotPublishAndCanRecoverWithSameSourceRevision() async throws {
        let store = try LargeLibraryFixtures.store(titles: 100, episodes: 0, events: 0)
        let model = LibraryOrganizationModel()
        model.replaceEntries(store.entries, revision: store.libraryRevision)
        model.cancelUpdates()
        await model.waitForUpdates()
        XCTAssertFalse(model.sourceReady); XCTAssertTrue(model.visible.isEmpty)
        model.replaceEntries(store.entries, revision: store.libraryRevision)
        await model.waitForUpdates()
        XCTAssertTrue(model.sourceReady); XCTAssertEqual(model.visible.count, 100)
    }

    @MainActor
    func testReplacingSourceDuringWorkCannotRestoreOldRows() async throws {
        let model = LibraryOrganizationModel()
        model.replaceItems(try LargeLibraryFixtures.items(5_000))
        model.replaceItems(try LargeLibraryFixtures.items(100))
        await model.waitForUpdates()
        XCTAssertEqual(model.totalCount, 100); XCTAssertEqual(model.visible.count, 100)
        XCTAssertTrue(model.visible.allSatisfy { Int($0.mediaID!.value.split(separator: ":").last!)! < 100 })
    }

    @MainActor
    func testDashboardReplacementCancelsSupersededWorkerAndRejectsLateCompletion() async throws {
        let gate = DashboardComputationGate()
        let model = DashboardModel { input, now in
            await gate.hold(input.titles.count)
            return try DashboardAggregator.aggregate(input, now: now)
        }
        let firstInput = try LargeLibraryFixtures.dashboard(titles: 1, episodes: 0, events: 0)
        let secondInput = try LargeLibraryFixtures.dashboard(titles: 2, episodes: 0, events: 0)
        let first = Task { await model.refresh(firstInput, revision: 1, now: LargeLibraryFixtures.now) }
        await gate.waitForEntry(1)
        let second = Task { await model.refresh(secondInput, revision: 2, now: LargeLibraryFixtures.now) }
        await gate.waitForEntry(2)
        await gate.release(2); await second.value
        XCTAssertEqual(model.snapshot?.statistics.ratings, 1)
        await gate.release(1); await first.value
        let canceled = await gate.wasCanceled(1)
        XCTAssertTrue(canceled); XCTAssertEqual(model.snapshot?.statistics.ratings, 1)
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testIndexedHistoryAndReviewsRetainOrderAndIndependentLinks() throws {
        let store = try LargeLibraryFixtures.store(titles: 100, episodes: 0, events: 5_000)
        let id = LargeLibraryFixtures.mediaID(1)
        XCTAssertEqual(store.events(for: id).map(\.id), store.viewingEvents.filter { $0.mediaID == id }.map(\.id))
        let event = try XCTUnwrap(store.events(for: id).first)
        let reviewID = UUID(), media = MediaSearchResult.movie(Movie(id: id.value, title: "Saved title"))
        try store.saveReview(id: reviewID, media: media, text: "Private fixture", eventID: event.id)
        XCTAssertTrue(store.hasReview(for: event.id)); XCTAssertEqual(store.reviews(for: id).count, 1)
        try store.deleteViewingEvent(event.id)
        XCTAssertFalse(store.hasReview(for: event.id)); XCTAssertEqual(store.reviews(for: id).first?.id, reviewID)
        XCTAssertEqual(store.events(for: id).count, 49)
        XCTAssertEqual(store.viewingEvents.count, 4_999)
        XCTAssertEqual(store.entries.count, 100)
    }

    @MainActor
    func testTenThousandProgressRecordsRapidTogglesKeepExactIdentityAndTotals() async throws {
        let store = try LargeLibraryFixtures.store(titles: 100, events: 0)
        let episode = LargeLibraryFixtures.episode(0), show = TVShow(id: episode.id.seriesID.value, title: "Show")
        let recordID = try XCTUnwrap(store.episodeProgress.first { $0.episodeID == episode.id }?.id)
        try store.setPersonalRating(try PersonalRating(halfStarUnits: 7), media: .tvShow(show))
        for i in 0..<20 {
            try store.setEpisodeWatched(i.isMultiple(of: 2), episode: episode, show: show, now: LargeLibraryFixtures.now)
            // Reads after each write must see the committed current flag, including cached summaries.
            XCTAssertEqual(store.isWatched(episode.id), i.isMultiple(of: 2))
            XCTAssertEqual(store.seriesProgress(show.id, now: LargeLibraryFixtures.now).watched, i.isMultiple(of: 2) ? 50 : 49)
        }
        XCTAssertEqual(store.episodeProgress.count, 10_000)
        XCTAssertEqual(store.episodeProgress.first { $0.episodeID == episode.id }?.id, recordID)
        XCTAssertEqual(try store.entry(for: show.id)?.validatedRating()?.halfStarUnits, 7)
        XCTAssertEqual(store.entries.filter { $0.mediaID == show.id }.count, 1)
        store.reload()
        XCTAssertFalse(store.isWatched(episode.id)); XCTAssertEqual(store.episodeProgress.count, 10_000)
    }

    @MainActor
    func testSerializedConcurrentCallersDoNotDuplicateProgressOrLoseUnrelatedRatings() async throws {
        let store = try LargeLibraryFixtures.store(titles: 100, episodes: 0, events: 0)
        let show = TVShow(id: LargeLibraryFixtures.mediaID(0).value, title: "Show")
        try store.setPersonalRating(try PersonalRating(halfStarUnits: 9), media: .tvShow(show))
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<40 {
                group.addTask { @MainActor in
                    try store.setEpisodeWatched(true, episode: LargeLibraryFixtures.episode(i % 10), show: show, now: LargeLibraryFixtures.now)
                }
            }
            try await group.waitForAll()
        }
        XCTAssertEqual(store.episodeProgress.count, 10)
        XCTAssertEqual(Set(store.episodeProgress.map(\.episodeID)).count, 10)
        XCTAssertEqual(store.seriesProgress(show.id, now: LargeLibraryFixtures.now).watched, 10)
        XCTAssertEqual(try store.entry(for: show.id)?.validatedRating()?.halfStarUnits, 9)
    }

    @MainActor
    func testFailedSaveRestoresIndexesAndDoesNotPublishPendingInsert() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let good = LibraryStore(container: container)
        let episode = LargeLibraryFixtures.episode(0), show = TVShow(id: episode.id.seriesID.value, title: "Show")
        try good.setEpisodeWatched(true, episode: episode, show: show, now: LargeLibraryFixtures.now)
        let failing = LibraryStore(container: container, save: { _ in throw LibraryStoreError.saveFailed })
        XCTAssertThrowsError(try failing.setEpisodeWatched(false, episode: episode, show: show, now: LargeLibraryFixtures.now))
        XCTAssertTrue(failing.isWatched(episode.id)); XCTAssertEqual(failing.episodeProgress.count, 1)
        XCTAssertEqual(failing.entry(for: show.id)?.status, "watching")
    }

    @MainActor
    func testDiaryAndProgressEditsDoNotInvalidateLibraryRowsUnlessTitleChanges() throws {
        let store = try LargeLibraryFixtures.store(titles: 100, episodes: 100, events: 0)
        let revision = store.libraryRevision, episode = LargeLibraryFixtures.episode(0)
        let show = TVShow(id: episode.id.seriesID.value, title: "Show") // Title already has Watching status.
        try store.setEpisodeWatched(false, episode: episode, show: show, now: LargeLibraryFixtures.now)
        XCTAssertEqual(store.libraryRevision, revision)
        try store.saveViewingEvent(id: UUID(), media: .tvShow(show), watchedDate: nil)
        XCTAssertEqual(store.libraryRevision, revision)
        try store.setFavorite(true, for: LargeLibraryFixtures.mediaID(1))
        XCTAssertGreaterThan(store.libraryRevision, revision)
    }

    @MainActor
    func testDayBoundaryInvalidatesCachedEpisodeEligibility() throws {
        let store = try LargeLibraryFixtures.store(titles: 100, episodes: 0, events: 0)
        var episode = LargeLibraryFixtures.episode(0)
        episode.airDate = LargeLibraryFixtures.now.addingTimeInterval(86_400)
        let summary = TVSeasonSummary(number: 1, providerID: nil, name: "Season 1", episodeCount: 1)
        let show = TVShow(id: episode.id.seriesID.value, title: "Show", seasons: [summary])
        try store.cacheSeasonCatalog(show: show)
        try store.cacheSeason(TVSeasonDetails(seriesID: show.id, number: 1, name: "Season 1", episodes: [episode]), show: show)
        let season = try XCTUnwrap(store.seasons(for: show.id).first)
        XCTAssertEqual(store.seasonProgress(season, now: LargeLibraryFixtures.now).eligible, 0)
        XCTAssertEqual(store.seriesProgress(show.id, now: LargeLibraryFixtures.now).future, 1)
        XCTAssertEqual(store.seasonProgress(season, now: LargeLibraryFixtures.now.addingTimeInterval(86_400)).eligible, 1)
        XCTAssertEqual(store.seriesProgress(show.id, now: LargeLibraryFixtures.now.addingTimeInterval(86_400)).future, 0)
    }

    @MainActor
    func testCanceledDashboardRefreshCanRetrySameRevision() async throws {
        let gate = DashboardComputationGate()
        let model = DashboardModel { input, now in
            await gate.hold(input.titles.count)
            return try DashboardAggregator.aggregate(input, now: now)
        }
        let input = try LargeLibraryFixtures.dashboard(titles: 1, episodes: 0, events: 0)
        let canceled = Task { await model.refresh(input, revision: 1, now: LargeLibraryFixtures.now) }
        await gate.waitForEntry(1)
        canceled.cancel(); await gate.release(1); await canceled.value
        XCTAssertNil(model.snapshot); XCTAssertTrue(model.needsRefresh(revision: 1, now: LargeLibraryFixtures.now))
        // The gate's entered flag is retained, so use a different fixture size for explicit synchronization.
        let replacement = try LargeLibraryFixtures.dashboard(titles: 2, episodes: 0, events: 0)
        let retry = Task { await model.refresh(replacement, revision: 1, now: LargeLibraryFixtures.now) }
        await gate.waitForEntry(2); await gate.release(2); await retry.value
        XCTAssertEqual(model.snapshot?.statistics.ratings, 1); XCTAssertFalse(model.isLoading)
    }

    func testSinglePassEpisodeSummaryMatchesReferenceWithUnknownFutureAndDuplicates() {
        var episodes = (0..<100).map(LargeLibraryFixtures.episode)
        for i in episodes.indices {
            if i.isMultiple(of: 7) { episodes[i].airDate = nil }
            else if i.isMultiple(of: 5) { episodes[i].airDate = LargeLibraryFixtures.now.addingTimeInterval(86_400) }
        }
        episodes += episodes.prefix(10)
        let watched = Set(episodes.enumerated().filter { $0.offset.isMultiple(of: 2) }.map { $0.element.id })
        let value = EpisodeProgressSummary.calculate(episodes: episodes, watchedIDs: watched, coverageKnown: true, now: LargeLibraryFixtures.now)
        var seen = Set<EpisodeID>(); let unique = episodes.filter { seen.insert($0.id).inserted }
        let eligible = unique.filter { $0.airDate.map { $0 <= LargeLibraryFixtures.now } == true }
        XCTAssertEqual(value.watched, eligible.filter { watched.contains($0.id) }.count)
        XCTAssertEqual(value.totalWatched, unique.filter { watched.contains($0.id) }.count)
        XCTAssertEqual(value.eligible, eligible.count)
        XCTAssertEqual(value.future, unique.filter { $0.airDate.map { $0 > LargeLibraryFixtures.now } == true }.count)
        XCTAssertEqual(value.unknownAirDate, unique.filter { $0.airDate == nil }.count)
    }
}

private actor DashboardComputationGate {
    private var entered = Set<Int>(), canceled = Set<Int>()
    private var work: [Int: CheckedContinuation<Void, Never>] = [:]
    private var arrivals: [Int: CheckedContinuation<Void, Never>] = [:]
    func hold(_ key: Int) async {
        await withCheckedContinuation { work[key] = $0; entered.insert(key); arrivals.removeValue(forKey: key)?.resume() }
        if Task.isCancelled { canceled.insert(key) }
    }
    func waitForEntry(_ key: Int) async {
        if entered.contains(key) { return }
        await withCheckedContinuation { arrivals[key] = $0 }
    }
    func release(_ key: Int) { work.removeValue(forKey: key)?.resume() }
    func wasCanceled(_ key: Int) -> Bool { canceled.contains(key) }
}
