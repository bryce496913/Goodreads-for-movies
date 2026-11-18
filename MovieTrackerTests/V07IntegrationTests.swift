import SwiftData
import XCTest
@testable import MovieTracker

/// Cross-feature contracts on isolated stores; never opens the application user's database.
final class V07IntegrationTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-18T12:00:00Z")!
    private let watched = ISO8601DateFormatter().date(from: "2024-02-29T00:00:00Z")!
    private var movie: Movie {
        Movie(id: "tmdb:444", title: "Provider movie title", overview: "Provider synopsis", runtimeMinutes: 105,
              genres: [.init(id: "tmdb:18", name: "Drama")], metadataRetrievedAt: now)
    }
    private var show: TVShow { TVShow(id: "tmdb:444", title: "Provider series title", metadataRetrievedAt: now) }
    private var episode: TVEpisode {
        TVEpisode(id: .init(seriesID: show.id, providerValue: "tmdb:episode:444"), seasonNumber: 1, number: 1,
                  title: "Provider episode title", airDate: watched, overview: "Provider episode synopsis", runtimeMinutes: 42, metadataRetrievedAt: now)
    }
    private func command(_ index: Int, date: Date?, extras: Bool = false) throws -> MovieWatchLog {
        MovieWatchLog(eventID: LargeLibraryFixtures.uuid(430_000 + index), reviewID: LargeLibraryFixtures.uuid(431_000 + index),
                      watchedDate: date, rating: extras ? .set(try PersonalRating(halfStarUnits: 9)) : .unchanged,
                      review: extras ? "Private V07 review — never send to the provider" : nil)
    }
    @MainActor private func store(at url: URL? = nil, clock: Date? = nil) throws -> LibraryStore {
        let date = clock ?? now
        let container = try url.map { try PersistenceController.makeContainer(at: $0) } ?? PersistenceController.makeContainer(inMemory: true)
        return LibraryStore(container: container, clock: { date })
    }
    @MainActor private func backup(_ store: LibraryStore) throws -> PersonalBackup { try store.capturePersonalBackup(at: now).canonical() }
    @MainActor private func seed(_ store: LibraryStore) throws {
        let first = try command(1, date: watched, extras: true)
        try store.logMovieWatch(first, media: .movie(movie), now: now, timeZone: .gmt)
        try store.logMovieWatch(first, media: .movie(movie), now: now, timeZone: .gmt) // Same command must be idempotent.
        try store.logMovieWatch(command(2, date: watched), media: .movie(movie), now: now, timeZone: .gmt)
        try store.logMovieWatch(command(3, date: nil), media: .movie(movie), now: now, timeZone: .gmt)
        try store.setFavorite(true, media: .movie(movie))
        try store.setStatus(.watching, media: .tvShow(show))
        try store.setEpisodeWatched(true, episode: episode, show: show, now: now)
        let list = try store.saveCollection(id: LargeLibraryFixtures.uuid(432_000), name: "V07 manual order", now: now)
        try store.setCollectionMembership(true, collection: list, media: .movie(movie), now: now)
        try store.setCollectionMembership(true, collection: list, media: .tvShow(show), now: now)
        let order = store.members(of: list).map(\.id)
        try store.reorderCollection(list, memberships: Array(order.reversed()), original: order, now: now)
    }
    @MainActor private func assertPersonalProjections(_ store: LibraryStore, at reference: Date? = nil, file: StaticString = #filePath, line: UInt = #line) async throws {
        let date = reference ?? now
        let stats = try DashboardAggregator.personalStatistics(.capture(store), year: 2024, now: date, timeZone: .gmt)
        XCTAssertEqual(stats.movieEvents, 2, file: file, line: line)
        XCTAssertEqual(stats.uniqueMovies, 1, file: file, line: line)
        XCTAssertEqual(stats.months[1].movieEvents, 2, file: file, line: line)
        XCTAssertEqual(stats.undatedEvents, 1, file: file, line: line)
        XCTAssertEqual(stats.ratingBuckets[8].count, 1, file: file, line: line)
        XCTAssertEqual(stats.overallWatchedEpisodes, 1, file: file, line: line)
        XCTAssertEqual(stats.episodeMarks, 0, file: file, line: line) // The mark is in 2026, not the selected diary year.
        XCTAssertEqual(stats.seriesEvents, 0, file: file, line: line) // Watching/progress does not invent a series diary event.
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        calendar.firstWeekday = 2
        let model = ViewingCalendarModel(now: date, calendar: calendar, locale: Locale(identifier: "en_US"))
        await model.update(store.viewingEvents, source: .init(revision: store.revision, calendar: calendar, locale: Locale(identifier: "en_US")))
        let localDay = try XCTUnwrap(ViewingCalendarProjection.day(for: watched, calendar: calendar))
        model.select(localDay)
        XCTAssertEqual(model.selectedEvents.count, 2, file: file, line: line)
        XCTAssertEqual(model.undatedEvents.count, 1, file: file, line: line)
        XCTAssertEqual(Set(model.selectedEvents.map(\.id)), Set(store.viewingEvents.filter { $0.watchedDate == watched }.map(\.id)), file: file, line: line)
        XCTAssertEqual(store.entry(for: movie.id)?.status, "watched", file: file, line: line)
        XCTAssertEqual(store.entry(for: show.id)?.status, "watching", file: file, line: line)
        XCTAssertEqual(Set(store.entries.compactMap(\.mediaID)).count, store.entries.count, file: file, line: line)
    }

    @MainActor func testFastLoggingCalendarStatisticsAndV2BackupRoundTripOffline() async throws {
        let source = try store(); try seed(source)
        try await assertPersonalProjections(source)
        let bytes = try BackupCodec.encode(backup(source))
        let text = String(decoding: bytes, as: UTF8.self)
        XCTAssertFalse(text.contains("Provider synopsis")); XCTAssertFalse(text.contains("Provider movie title"))
        XCTAssertFalse(text.contains("Provider episode title")); XCTAssertFalse(text.contains("metadataRetrievedAt"))
        let imported = try BackupCodec.decode(bytes), restored = try store()
        let plan = try BackupMergePlanner.prepare(imported, local: backup(restored), revision: restored.revision)
        try restored.restorePersonalBackup(plan)
        XCTAssertEqual(try backup(restored), try backup(source))
        try await assertPersonalProjections(restored)
        let second = try BackupMergePlanner.prepare(imported, local: backup(restored), revision: restored.revision)
        XCTAssertEqual(second.counts.total, 0)
        try restored.restorePersonalBackup(second)
        XCTAssertEqual(try backup(restored), try backup(source))
        let stats = try DashboardAggregator.personalStatistics(.capture(restored), year: 2024, now: now, timeZone: .gmt)
        XCTAssertTrue(stats.genres.isEmpty); XCTAssertEqual(stats.missingGenreTitles, 1) // Personal backups do not invent provider metadata.
    }
    @MainActor func testFastLogFailureAndCancelLeaveCalendarStatsAndPortableBackupUnchanged() async throws {
        var fail = false, saves = 0
        let date = now
        let source = LibraryStore(container: try PersistenceController.makeContainer(inMemory: true), clock: { date }, save: { context in
            if fail { throw LibraryStoreError.saveFailed }
            try context.save(); saves += 1
        })
        try seed(source)
        let before = try backup(source), count = saves
        _ = MovieWatchLogModel(media: .movie(movie), now: now) // Canceling a draft has no write path.
        let draft = MovieWatchLogModel(media: .movie(movie), now: now, timeZone: .gmt)
        draft.writesReview = true; draft.review = "Unsaved private review"; draft.chooseRating(try PersonalRating(halfStarUnits: 2))
        fail = true
        XCTAssertFalse(draft.save(into: source, now: now))
        XCTAssertEqual(try backup(source), before); XCTAssertEqual(saves, count)
        try await assertPersonalProjections(source)
        fail = false
        XCTAssertTrue(draft.save(into: source, now: now))
        XCTAssertEqual(saves, count + 1)
        XCTAssertFalse(draft.save(into: source, now: now))
        XCTAssertEqual(saves, count + 1); XCTAssertEqual(source.viewingEvents.count, 4)
        XCTAssertEqual(source.personalReviews.count, 2)
    }
    @MainActor func testDiskReopenAndMetadataExpiryPreserveAllV07PersonalRecords() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("V07.store")
        var expected: PersonalBackup?
        try autoreleasepool {
            let first = try store(at: url); try seed(first)
            expected = try backup(first)
        }
        let later = now.addingTimeInterval(MetadataPolicy.retention)
        try await reopened(url, expected: XCTUnwrap(expected), later: later)
    }
    @MainActor private func reopened(_ url: URL, expected: PersonalBackup, later: Date) async throws {
        let reopened = try store(at: url, clock: later)
        try reopened.maintainMetadata(at: later)
        XCTAssertEqual(try backup(reopened), expected)
        XCTAssertNil(reopened.entry(for: movie.id)?.savedMedia)
        XCTAssertEqual(SearchItem(try XCTUnwrap(reopened.offlineMedia(for: movie.id))).displayTitle, "Title information unavailable")
        XCTAssertEqual(reopened.episodeProgress.first?.savedEpisode?.title, "Episode metadata unavailable")
        try await assertPersonalProjections(reopened, at: later)
        XCTAssertEqual(try BackupCodec.decode(BackupCodec.encode(backup(reopened))), expected)
    }
    @MainActor func testKeepExistingMergeAndFailedRestoreRollbackKeepLoggedReviewAndOrder() throws {
        let incomingStore = try store(); try seed(incomingStore)
        let incoming = try backup(incomingStore)
        var fail = false
        let date = now
        let local = LibraryStore(container: try PersistenceController.makeContainer(inMemory: true), clock: { date }, save: { context in
            if fail { throw LibraryStoreError.saveFailed }; try context.save()
        })
        try local.setStatus(.watchlist, media: .movie(movie))
        try local.setPersonalRating(PersonalRating(halfStarUnits: 3), media: .movie(movie))
        let before = try backup(local)
        let plan = try BackupMergePlanner.prepare(incoming, local: before, revision: local.revision)
        fail = true; XCTAssertThrowsError(try local.restorePersonalBackup(plan))
        XCTAssertEqual(try backup(local), before)
        fail = false
        let current = try BackupMergePlanner.prepare(incoming, local: backup(local), revision: local.revision)
        try local.restorePersonalBackup(current)
        XCTAssertEqual(local.entry(for: movie.id)?.status, "watchlist")
        XCTAssertEqual(try local.entry(for: movie.id)?.validatedRating()?.halfStarUnits, 3)
        XCTAssertEqual(local.viewingEvents.count, 3); XCTAssertEqual(local.personalReviews.count, 1)
        XCTAssertEqual(local.members(of: LargeLibraryFixtures.uuid(432_000)).map(\.mediaID), [show.id, movie.id])
        XCTAssertEqual(local.personalReviews.first?.viewingEventID, LargeLibraryFixtures.uuid(430_001))
    }
    @MainActor func testLegacyV1BackupRetainsNewLogEventsAndRatingsWithoutCollections() throws {
        let source = try store(); try seed(source)
        var legacy = try backup(source)
        legacy.version = 1; legacy.collections = []; legacy.collectionMemberships = []
        let decoded = try BackupCodec.decode(BackupCodec.encode(legacy)), destination = try store()
        let plan = try BackupMergePlanner.prepare(decoded, local: backup(destination), revision: destination.revision)
        try destination.restorePersonalBackup(plan)
        XCTAssertEqual(destination.viewingEvents.count, 3); XCTAssertEqual(destination.personalReviews.count, 1)
        XCTAssertEqual(destination.entry(for: movie.id)?.ratingHalfStarUnits, 9)
        XCTAssertTrue(destination.collections.isEmpty)
    }
}
