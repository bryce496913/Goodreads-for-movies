import SwiftData
import XCTest
@testable import MovieTracker

final class MovieWatchLogTests: XCTestCase {
    private let now = BackupFixtures.now
    private var movie: MediaSearchResult { .movie(Movie(id: "fixture:log", title: "Offline movie")) }
    private var id: MediaID { SearchItem(movie).id }
    @MainActor private func store() throws -> LibraryStore { try BackupFixtures.store() }
    private func log(date: Date? = nil, rating: MovieWatchLog.RatingChange = .unchanged, review: String? = nil, event: UUID = UUID(), reviewID: UUID = UUID()) -> MovieWatchLog {
        MovieWatchLog(eventID: event, reviewID: reviewID, watchedDate: date, rating: rating, review: review)
    }
    @MainActor func testDatedAndExplicitlyUndatedLogsHaveOneWatchedLibraryIdentity() throws {
        let store = try store(), day = DiaryDates.storageDate(from: now, timeZone: .gmt)
        try store.logMovieWatch(log(date: day), media: movie, now: now, timeZone: .gmt)
        try store.logMovieWatch(log(), media: movie, now: now, timeZone: .gmt)
        XCTAssertEqual(store.entries.count, 1); XCTAssertEqual(store.events(for: id).count, 2)
        XCTAssertEqual(store.events(for: id).filter { $0.watchedDate == nil }.count, 1)
        XCTAssertEqual(store.events(for: id).filter { $0.watchedDate == day }.count, 1)
        XCTAssertTrue(store.events(for: id).allSatisfy { $0.recordedAt == now })
        XCTAssertEqual(store.entry(for: id)?.status, "watched"); XCTAssertNil(try store.entry(for: id)?.validatedRating())
    }
    @MainActor func testEveryHalfStarCanBeLoggedAndExplicitlyClearedWithoutLosingHistory() throws {
        let store = try store()
        for value in PersonalRating.allValues {
            try store.logMovieWatch(log(rating: .set(value)), media: movie, now: now)
            XCTAssertEqual(try store.entry(for: id)?.validatedRating(), value)
        }
        try store.logMovieWatch(log(rating: .set(nil)), media: movie, now: now)
        XCTAssertNil(try store.entry(for: id)?.validatedRating()); XCTAssertNil(store.entry(for: id)?.rating)
        XCTAssertEqual(store.events(for: id).count, 11); XCTAssertEqual(store.entries.count, 1)
    }
    @MainActor func testOptionalReviewIsLinkedOnlyToItsExactNewEvent() throws {
        let store = try store(), command = log(review: "  A private review\nWith whitespace preserved  ")
        try store.logMovieWatch(command, media: movie, now: now)
        XCTAssertEqual(store.reviews(for: id).first?.viewingEventID, command.eventID)
        XCTAssertEqual(store.reviews(for: id).first?.id, command.reviewID)
        XCTAssertEqual(store.reviews(for: id).first?.text, command.review)
        XCTAssertEqual(store.reviews(for: id).first?.createdAt, now)
    }
    @MainActor func testRewatchPreservesRatingReviewsFavoriteAndCollectionWithoutDuplicatingLibrary() throws {
        let store = try store(), rating = try PersonalRating(halfStarUnits: 7)
        try store.logMovieWatch(log(rating: .set(rating), review: "First viewing"), media: movie, now: now)
        try store.setFavorite(true, media: movie)
        let list = try store.saveCollection(name: "Keep"), libraryID = store.entry(for: id)?.id
        try store.setCollectionMembership(true, collection: list, media: movie)
        let review = store.reviews(for: id).first?.id, ratedAt = store.entry(for: id)?.ratingUpdatedAt
        for _ in 0..<2 { try store.logMovieWatch(log(), media: movie, now: now.addingTimeInterval(1)) }
        XCTAssertEqual(store.events(for: id).count, 3); XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entry(for: id)?.id, libraryID); XCTAssertEqual(try store.entry(for: id)?.validatedRating(), rating)
        XCTAssertEqual(store.entry(for: id)?.ratingUpdatedAt, ratedAt); XCTAssertTrue(store.entry(for: id)?.isFavorite == true)
        XCTAssertTrue(store.isInCollection(list, mediaID: id)); XCTAssertEqual(store.reviews(for: id).map(\.id), [review!])
    }
    @MainActor func testOneLogicalSaveAndRepeatedCommandDoesNotOverwriteSubsequentPersonalEdits() throws {
        var saves = 0
        let store = LibraryStore(container: try PersistenceController.makeContainer(inMemory: true), save: { context in saves += 1; try context.save() })
        let command = log(rating: .set(try PersonalRating(halfStarUnits: 8)), review: "One event")
        try store.logMovieWatch(command, media: movie, now: now)
        XCTAssertEqual(saves, 1); XCTAssertEqual(store.revision, 2) // Initial reload plus one published transaction.
        try store.setPersonalRating(PersonalRating(halfStarUnits: 10), media: movie)
        let before = try store.capturePersonalBackup(at: now), count = saves
        try store.logMovieWatch(command, media: movie, now: now.addingTimeInterval(1))
        XCTAssertEqual(saves, count); XCTAssertEqual(try store.capturePersonalBackup(at: now).canonical(), before.canonical())
    }
    @MainActor func testFailedSaveRollsBackEventRatingStatusReviewAndAllowsExactRetry() throws {
        var fail = false
        let store = LibraryStore(container: try PersistenceController.makeContainer(inMemory: true), save: { context in
            if fail { throw LibraryStoreError.saveFailed }; try context.save()
        })
        try store.setStatus(.watchlist, media: movie)
        try store.setFavorite(true, media: movie)
        let before = try store.capturePersonalBackup(at: now)
        let command = log(rating: .set(try PersonalRating(halfStarUnits: 9)), review: "Atomic review")
        fail = true; XCTAssertThrowsError(try store.logMovieWatch(command, media: movie, now: now))
        XCTAssertEqual(try store.capturePersonalBackup(at: now).canonical(), before.canonical())
        fail = false; try store.logMovieWatch(command, media: movie, now: now)
        XCTAssertEqual(store.events(for: id).count, 1); XCTAssertEqual(store.reviews(for: id).count, 1)
        XCTAssertEqual(store.entry(for: id)?.status, "watched"); XCTAssertTrue(store.entry(for: id)?.isFavorite == true)
    }
    @MainActor func testReviewIdentityConflictAfterEventStagingLeavesNoPartialData() throws {
        let store = try store(), reviewID = UUID()
        try store.saveReview(id: reviewID, media: .movie(Movie(id: "fixture:other", title: "Other")), text: "Do not overwrite", now: now)
        let before = try store.capturePersonalBackup(at: now)
        XCTAssertThrowsError(try store.logMovieWatch(log(rating: .set(try PersonalRating(halfStarUnits: 5)), review: "New", reviewID: reviewID), media: movie, now: now))
        XCTAssertEqual(try store.capturePersonalBackup(at: now).canonical(), before.canonical())
        XCTAssertNil(store.entry(for: id)); XCTAssertTrue(store.events(for: id).isEmpty)
    }
    @MainActor func testEmptyOversizedReviewFutureAndInvalidDatesAndTVAreRejected() throws {
        let store = try store()
        for text in [" \n ", String(repeating: "x", count: 1_048_577)] {
            XCTAssertThrowsError(try store.logMovieWatch(log(review: text), media: movie, now: now))
        }
        XCTAssertThrowsError(try store.logMovieWatch(log(date: now.addingTimeInterval(3 * 86_400)), media: movie, now: now))
        XCTAssertThrowsError(try store.logMovieWatch(log(date: Date(timeIntervalSinceReferenceDate: .nan)), media: movie, now: now))
        XCTAssertThrowsError(try store.logMovieWatch(log(), media: .tvShow(TVShow(id: id.value, title: "Same number TV")), now: now))
        XCTAssertTrue(store.entries.isEmpty); XCTAssertTrue(store.viewingEvents.isEmpty)
    }
    @MainActor func testExistingEventIDForOtherMediaIsRejected() throws {
        let store = try store(), event = UUID(), other = MediaSearchResult.movie(Movie(id: "fixture:other", title: "Other"))
        try store.saveViewingEvent(id: event, media: other, watchedDate: nil, now: now)
        XCTAssertThrowsError(try store.logMovieWatch(log(event: event), media: movie, now: now))
        XCTAssertNil(store.entry(for: id)); XCTAssertEqual(store.viewingEvents.count, 1)
    }
    @MainActor func testDraftCancelAndDoubleSubmissionAndFailureFeedback() throws {
        let store = try store(), draft = MovieWatchLogModel(media: movie, now: now, timeZone: .gmt)
        draft.chooseRating(try PersonalRating(halfStarUnits: 6)); draft.writesReview = true; draft.review = "Draft only"
        XCTAssertTrue(draft.hasChanges); XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(draft.save(into: store, now: now)); XCTAssertTrue(draft.didSave)
        XCTAssertFalse(draft.save(into: store, now: now)); XCTAssertEqual(store.events(for: id).count, 1)
        let empty = MovieWatchLogModel(media: movie, now: now); empty.writesReview = true
        XCTAssertFalse(empty.canSave); XCTAssertFalse(empty.save(into: store, now: now))
        XCTAssertEqual(store.events(for: id).count, 1)
    }
    @MainActor func testDraftFailureRetainsInputsAndRetriesSameEventIdentity() throws {
        var fail = true
        let store = LibraryStore(container: try PersistenceController.makeContainer(inMemory: true), save: { context in
            if fail { throw LibraryStoreError.saveFailed }; try context.save()
        })
        let draft = MovieWatchLogModel(media: movie, now: now)
        draft.writesReview = true; draft.review = "Keep this draft"
        draft.chooseRating(try PersonalRating(halfStarUnits: 8))
        XCTAssertFalse(draft.save(into: store, now: now)); XCTAssertFalse(draft.didSave)
        XCTAssertNotNil(draft.errorMessage); XCTAssertEqual(draft.review, "Keep this draft")
        XCTAssertTrue(store.viewingEvents.isEmpty); XCTAssertTrue(store.entries.isEmpty)
        fail = false
        XCTAssertTrue(draft.save(into: store, now: now)); XCTAssertNil(draft.errorMessage)
        XCTAssertEqual(store.viewingEvents.first?.id, draft.eventID)
        XCTAssertEqual(store.personalReviews.first?.viewingEventID, draft.eventID)
    }
    @MainActor func testUneditedDraftDoesNotOverwriteConcurrentRatingChange() throws {
        let store = try store()
        let old = try PersonalRating(halfStarUnits: 4), newer = try PersonalRating(halfStarUnits: 9)
        try store.setPersonalRating(old, media: movie)
        let draft = MovieWatchLogModel(media: movie, rating: .success(old), now: now)
        try store.setPersonalRating(newer, media: movie)
        XCTAssertTrue(draft.save(into: store, now: now)); XCTAssertEqual(try store.entry(for: id)?.validatedRating(), newer)
    }
    @MainActor func testTimezoneDateUsesLocalCivilDayAndUndatedRemainsNil() throws {
        let store = try store(), zone = try XCTUnwrap(TimeZone(secondsFromGMT: 14 * 3_600))
        let draft = MovieWatchLogModel(media: movie, now: now, timeZone: zone)
        XCTAssertTrue(draft.save(into: store, now: now))
        XCTAssertEqual(store.events(for: id).first?.watchedDate, DiaryDates.storageDate(from: now, timeZone: zone))
        let undated = MovieWatchLogModel(media: movie, now: now, timeZone: zone); undated.dateKnown = false
        XCTAssertTrue(undated.save(into: store, now: now)); XCTAssertEqual(store.events(for: id).filter { $0.watchedDate == nil }.count, 1)
    }
    @MainActor func testDiaryOrderingUsesWatchedDayInsteadOfNewlyRecordedOldWatch() throws {
        let store = try store(), recent = UUID(), old = UUID()
        try store.logMovieWatch(log(date: now.addingTimeInterval(-86_400), event: recent), media: movie, now: now)
        try store.logMovieWatch(log(date: now.addingTimeInterval(-365 * 86_400), event: old), media: movie, now: now.addingTimeInterval(1))
        XCTAssertEqual(store.events(for: id).map(\.id), [recent, old])
    }
    @MainActor func testExpiredMetadataLoggingAndDiskRelaunchAndBackupRestoreRemainPersonalOnly() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Logging.store"), instant = now
        let media = MediaSearchResult.movie(Movie(id: "tmdb:expired", title: "EXPIRED_PROVIDER_TITLE", metadataRetrievedAt: now.addingTimeInterval(-MetadataPolicy.retention)))
        var expected: PersonalBackup?
        try autoreleasepool {
            let store = LibraryStore(container: try PersistenceController.makeContainer(at: url), clock: { instant })
            try store.logMovieWatch(log(rating: .set(try PersonalRating(halfStarUnits: 7)), review: "Offline review"), media: media, now: instant)
            expected = try store.capturePersonalBackup(at: instant)
            XCTAssertFalse(store.entry(for: SearchItem(media).id)?.displayTitle.contains("EXPIRED_PROVIDER_TITLE") == true)
        }
        try autoreleasepool {
            let reopened = LibraryStore(container: try PersistenceController.makeContainer(at: url), clock: { instant })
            XCTAssertEqual(try reopened.capturePersonalBackup(at: instant).canonical(), try XCTUnwrap(expected).canonical())
            let backup = try BackupCodec.decode(BackupCodec.encode(XCTUnwrap(expected)))
            let target = try BackupFixtures.store()
            try target.restorePersonalBackup(BackupFixtures.plan(backup, into: target))
            XCTAssertEqual(try target.capturePersonalBackup(at: instant).canonical(), backup.canonical())
        }
    }
}
