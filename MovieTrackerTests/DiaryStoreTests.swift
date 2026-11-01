import SwiftData
import XCTest
@testable import MovieTracker

final class DiaryStoreTests: XCTestCase {
    private let movie = MediaSearchResult.movie(Movie(id: "tmdb:42", title: "Private Movie"))
    private let show = MediaSearchResult.tvShow(TVShow(id: "tmdb:42", title: "Private Series"))

    @MainActor
    func testReviewCreationEditingAndStableIdentity() async throws {
        let store = try makeStore()
        let id = UUID()
        let created = Date(timeIntervalSince1970: 1_000)
        let edited = Date(timeIntervalSince1970: 2_000)
        try store.saveReview(id: id, media: movie, text: "First review", now: created)
        try store.saveReview(id: id, media: movie, text: "Edited review", now: edited)
        try store.saveReview(id: id, media: movie, text: "Edited review", now: Date(timeIntervalSince1970: 3_000))
        let review = try XCTUnwrap(store.personalReviews.first)
        XCTAssertEqual(store.personalReviews.count, 1)
        XCTAssertEqual(review.id, id)
        XCTAssertEqual(review.text, "Edited review")
        XCTAssertEqual(review.createdAt, created)
        XCTAssertEqual(review.editedAt, edited)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertNil(try store.entries.first?.domainEntry().status)
    }

    @MainActor
    func testWhitespaceOnlyReviewRejectedWithoutCreatingLibraryEntry() async throws {
        let store = try makeStore()
        for text in ["", "  ", "\n\t"] {
            XCTAssertThrowsError(try store.saveReview(id: UUID(), media: movie, text: text))
        }
        XCTAssertTrue(store.personalReviews.isEmpty)
        XCTAssertTrue(store.entries.isEmpty)
    }

    @MainActor
    func testUndatedAndDatedEventsHaveDistinctTimestampSemantics() async throws {
        let store = try makeStore()
        let oldWatch = Date(timeIntervalSince1970: 1_704_067_200)
        let recorded = Date(timeIntervalSince1970: 1_767_225_600)
        let undatedID = UUID()
        try store.saveViewingEvent(id: UUID(), media: movie, watchedDate: oldWatch, now: recorded)
        try store.saveViewingEvent(id: undatedID, media: movie, watchedDate: nil, now: recorded)
        XCTAssertEqual(store.viewingEvents.first?.id, undatedID)
        XCTAssertEqual(store.viewingEvents.first?.recordedAt, recorded)
        XCTAssertNil(store.viewingEvents.first?.watchedDate)
        XCTAssertTrue(store.viewingEvents.first?.dateLabel.hasPrefix("Date recorded") == true)
        XCTAssertEqual(store.viewingEvents.last?.sortDate, oldWatch)
    }

    @MainActor
    func testRepeatWatchesKeepOneTitleAndDoNotCopyReview() async throws {
        let store = try makeStore()
        try store.saveReview(id: UUID(), media: movie, text: "Overall thoughts")
        for yearOffset in 0..<3 {
            try store.saveViewingEvent(id: UUID(), media: movie,
                watchedDate: Date(timeIntervalSince1970: 1_704_067_200 + Double(yearOffset) * 366 * 86_400))
        }
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.viewingEvents.count, 3)
        XCTAssertEqual(store.personalReviews.count, 1)
        XCTAssertNil(store.personalReviews.first?.viewingEventID)
        XCTAssertTrue(store.viewingEvents[0].sortDate > store.viewingEvents[1].sortDate)
    }

    @MainActor
    func testDeletingReviewKeepsAssociatedEventAndPersonalData() async throws {
        let store = try makeStore()
        try store.setStatus(.watched, media: movie)
        try store.setPersonalRating(PersonalRating(halfStarUnits: 9), media: movie)
        let eventID = UUID(), reviewID = UUID()
        try store.saveViewingEvent(id: eventID, media: movie, watchedDate: nil)
        try store.saveReview(id: reviewID, media: movie, text: "Review", eventID: eventID)
        try store.deleteReview(reviewID)
        XCTAssertTrue(store.personalReviews.isEmpty)
        XCTAssertEqual(store.viewingEvents.count, 1)
        XCTAssertEqual(store.entries.first?.status, "watched")
        XCTAssertEqual(store.entries.first?.ratingHalfStarUnits, 9)
    }

    @MainActor
    func testDeletingOneEventDetachesReviewAndKeepsOtherWatchesRatingAndFavorite() async throws {
        let store = try makeStore()
        try store.setFavorite(true, media: movie)
        try store.setPersonalRating(PersonalRating(halfStarUnits: 7), media: movie)
        let first = UUID(), second = UUID()
        try store.saveViewingEvent(id: first, media: movie, watchedDate: nil)
        try store.saveViewingEvent(id: second, media: movie, watchedDate: nil)
        try store.saveReview(id: UUID(), media: movie, text: "Keep text", eventID: first)
        try store.deleteViewingEvent(first)
        XCTAssertEqual(store.viewingEvents.map(\.id), [second])
        XCTAssertEqual(store.personalReviews.first?.text, "Keep text")
        XCTAssertNil(store.personalReviews.first?.viewingEventID)
        XCTAssertEqual(store.entries.first?.ratingHalfStarUnits, 7)
        XCTAssertTrue(store.entries.first?.isFavorite == true)
    }

    @MainActor
    func testEventEditingPreservesRecordedDateAndDoesNotDuplicate() async throws {
        let store = try makeStore()
        let id = UUID(), recorded = Date(timeIntervalSince1970: 1_767_225_600)
        let watched = Date(timeIntervalSince1970: 1_704_067_200)
        try store.saveViewingEvent(id: id, media: show, watchedDate: nil, now: recorded)
        try store.saveViewingEvent(id: id, media: show, watchedDate: watched)
        XCTAssertEqual(store.viewingEvents.count, 1)
        XCTAssertEqual(store.viewingEvents.first?.recordedAt, recorded)
        XCTAssertEqual(store.viewingEvents.first?.watchedDate, watched)
        XCTAssertNil(try store.entries.first?.domainEntry().status, "Series logging must not imply episode completion or a Watched status")
    }

    @MainActor
    func testCrossMediaReviewAssociationAndIdentityReuseAreRejected() async throws {
        let store = try makeStore()
        let eventID = UUID(), reviewID = UUID()
        try store.saveViewingEvent(id: eventID, media: show, watchedDate: nil)
        XCTAssertThrowsError(try store.saveReview(id: reviewID, media: movie, text: "Wrong title", eventID: eventID))
        try store.saveReview(id: reviewID, media: movie, text: "Movie review")
        XCTAssertThrowsError(try store.saveReview(id: reviewID, media: show, text: "Wrong edit"))
        XCTAssertThrowsError(try store.saveViewingEvent(id: eventID, media: movie, watchedDate: nil))
        XCTAssertEqual(store.personalReviews.first?.text, "Movie review")
    }

    @MainActor
    func testOnlyOneExplicitReviewCanLinkToAnEvent() async throws {
        let store = try makeStore()
        let eventID = UUID()
        try store.saveViewingEvent(id: eventID, media: movie, watchedDate: nil)
        try store.saveReview(id: UUID(), media: movie, text: "Linked review", eventID: eventID)
        XCTAssertThrowsError(try store.saveReview(id: UUID(), media: movie, text: "Another", eventID: eventID))
        try store.saveReview(id: UUID(), media: movie, text: "Standalone review")
        XCTAssertEqual(store.personalReviews.count, 2)
    }

    @MainActor
    func testFailedSaveRollsBackReviewAndImplicitLibraryEntry() async throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let store = LibraryStore(container: container, save: { _ in throw LibraryStoreError.saveFailed })
        XCTAssertThrowsError(try store.saveReview(id: UUID(), media: movie, text: "Not saved"))
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(store.personalReviews.isEmpty)
        XCTAssertThrowsError(try store.saveViewingEvent(id: UUID(), media: movie, watchedDate: nil))
        XCTAssertTrue(store.viewingEvents.isEmpty)
    }

    @MainActor
    func testOfflineArchiveSurvivesExplicitLibraryRemovalAndMissingSnapshot() async throws {
        let store = try makeStore()
        try store.saveReview(id: UUID(), media: movie, text: "Always local")
        try store.saveViewingEvent(id: UUID(), media: movie, watchedDate: nil)
        try store.remove(SearchItem(movie).id)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(store.personalReviews.first?.text, "Always local")
        XCTAssertEqual(SearchItem(try XCTUnwrap(store.personalReviews.first?.savedMedia)).title, "Private Movie")
        let review = try XCTUnwrap(store.personalReviews.first)
        review.snapshotData = nil // A missing metadata archive must not hide private text.
        XCTAssertNotNil(review.savedMedia)
        XCTAssertEqual(review.text, "Always local")
        XCTAssertEqual(store.viewingEvents.count, 1)
    }

    @MainActor
    func testLegacyReviewExplicitImportPreservesOtherFields() async throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let legacy = StoredLibraryEntry(entry: UserLibraryEntry(mediaID: SearchItem(movie).id, status: .watched,
            isFavorite: true, rating: try PersonalRating(halfStarUnits: 8), review: "Earlier private text"))
        container.mainContext.insert(legacy)
        try container.mainContext.save()
        let store = LibraryStore(container: container)
        XCTAssertTrue(store.personalReviews.isEmpty, "Do not automatically duplicate legacy content")
        let entry = try XCTUnwrap(store.entries.first)
        try store.saveReview(id: UUID(), media: movie, text: "Edited private text", legacyEntryID: entry.id)
        XCTAssertNil(store.entries.first?.review)
        XCTAssertEqual(store.personalReviews.first?.text, "Edited private text")
        XCTAssertTrue(store.entries.first?.isFavorite == true)
        XCTAssertEqual(store.entries.first?.ratingHalfStarUnits, 8)
        XCTAssertEqual(store.entries.first?.status, "watched")
    }

    @MainActor
    func testReviewAndEventsPersistAcrossContainerReinitialization() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Diary.store")
        let reviewID = UUID(), eventID = UUID()
        try autoreleasepool {
            let store = LibraryStore(container: try PersistenceController.makeContainer(at: url))
            try store.setPersonalRating(PersonalRating(halfStarUnits: 9), media: movie)
            try store.saveViewingEvent(id: eventID, media: movie, watchedDate: nil)
            try store.saveReview(id: reviewID, media: movie, text: "Offline after relaunch", eventID: eventID)
        }
        let reopened = LibraryStore(container: try PersistenceController.makeContainer(at: url))
        XCTAssertEqual(reopened.personalReviews.first?.id, reviewID)
        XCTAssertEqual(reopened.personalReviews.first?.viewingEventID, eventID)
        XCTAssertEqual(reopened.personalReviews.first?.text, "Offline after relaunch")
        XCTAssertEqual(reopened.viewingEvents.first?.id, eventID)
        XCTAssertEqual(reopened.entries.first?.ratingHalfStarUnits, 9)
    }

    @MainActor
    func testLegacyReviewCanBeReadAndDeletedWithoutMetadata() async throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let record = StoredLibraryEntry(entry: UserLibraryEntry(mediaID: SearchItem(movie).id, review: "Earlier offline text"))
        container.mainContext.insert(record)
        try container.mainContext.save()
        let store = LibraryStore(container: container)
        XCTAssertNotNil(store.entries.first?.offlineMedia)
        try store.deleteLegacyReview(for: SearchItem(movie).id)
        XCTAssertNil(store.entries.first?.review)
        XCTAssertEqual(store.entries.count, 1)
    }

    @MainActor
    func testFailedEditAndEventDeletionRollBackTextAndAssociation() async throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let good = LibraryStore(container: container)
        let reviewID = UUID(), eventID = UUID()
        try good.saveViewingEvent(id: eventID, media: movie, watchedDate: nil)
        try good.saveReview(id: reviewID, media: movie, text: "Original text", eventID: eventID)
        let failing = LibraryStore(container: container, save: { _ in throw LibraryStoreError.saveFailed })
        XCTAssertThrowsError(try failing.saveReview(id: reviewID, media: movie, text: "Should roll back"))
        XCTAssertEqual(failing.personalReviews.first?.text, "Original text")
        XCTAssertThrowsError(try failing.deleteViewingEvent(eventID))
        XCTAssertEqual(failing.viewingEvents.count, 1)
        XCTAssertEqual(failing.personalReviews.first?.viewingEventID, eventID)
    }

    func testDateOnlyRoundTripAcrossTimezones() throws {
        let east = try XCTUnwrap(TimeZone(secondsFromGMT: 14 * 3600))
        let west = try XCTUnwrap(TimeZone(secondsFromGMT: -10 * 3600))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = east
        let selected = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 1, day: 1)))
        let stored = DiaryDates.storageDate(from: selected, timeZone: east)
        let reopened = DiaryDates.pickerDate(from: stored, timeZone: west)
        calendar.timeZone = west
        let components = calendar.dateComponents([.year, .month, .day], from: reopened)
        XCTAssertEqual(components.year, 2024)
        XCTAssertEqual(components.month, 1)
        XCTAssertEqual(components.day, 1)
    }

    @MainActor
    func testRemovingLegacyLibraryRowPreservesPrivateReviewArchive() async throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let record = StoredLibraryEntry(entry: UserLibraryEntry(mediaID: SearchItem(movie).id, review: "Keep this earlier review"))
        container.mainContext.insert(record)
        try container.mainContext.save()
        let store = LibraryStore(container: container)
        try store.remove(SearchItem(movie).id)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(store.personalReviews.count, 1)
        XCTAssertEqual(store.personalReviews.first?.text, "Keep this earlier review")
        XCTAssertTrue(store.personalReviews.first?.isLegacyImport == true)
        XCTAssertTrue(store.personalReviews.first?.dateLabel.hasPrefix("Imported") == true)
    }

    @MainActor
    private func makeStore() throws -> LibraryStore {
        LibraryStore(container: try PersistenceController.makeContainer(inMemory: true))
    }
}
