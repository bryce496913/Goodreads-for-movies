import SwiftData
import XCTest
@testable import MovieTracker

final class RatingPersistenceTests: XCTestCase {
    private let movie = MediaSearchResult.movie(Movie(id: "tmdb:42", title: "Movie"))
    private let show = MediaSearchResult.tvShow(TVShow(id: "tmdb:42", title: "Show"))

    @MainActor
    func testMovieAndTVRatingsWithoutViewingStatus() async throws {
        let store = try makeStore()
        try store.setPersonalRating(PersonalRating(halfStarUnits: 1), media: movie)
        try store.setPersonalRating(PersonalRating(halfStarUnits: 10), media: show)
        XCTAssertEqual(store.entries.count, 2)
        let movieEntry = try XCTUnwrap(store.entry(for: SearchItem(movie).id))
        let tvEntry = try XCTUnwrap(store.entry(for: SearchItem(show).id))
        XCTAssertNil(try movieEntry.domainEntry().status)
        XCTAssertNil(try tvEntry.domainEntry().status)
        XCTAssertEqual(try movieEntry.validatedRating()?.halfStarUnits, 1)
        XCTAssertEqual(try tvEntry.validatedRating()?.halfStarUnits, 10)
    }

    @MainActor
    func testEditingAndRepeatedRatingUseOneRecord() async throws {
        let store = try makeStore()
        try store.setPersonalRating(PersonalRating(halfStarUnits: 5), media: movie)
        let original = try XCTUnwrap(store.entries.first)
        let id = original.id
        let added = original.addedAt
        try store.setPersonalRating(PersonalRating(halfStarUnits: 9), media: movie)
        let updated = try XCTUnwrap(store.entries.first).updatedAt
        try store.setPersonalRating(PersonalRating(halfStarUnits: 9), media: movie)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.id, id)
        XCTAssertEqual(store.entries.first?.addedAt, added)
        XCTAssertEqual(store.entries.first?.updatedAt, updated)
        XCTAssertEqual(store.entries.first?.ratingHalfStarUnits, 9)
    }

    @MainActor
    func testClearingRatingPreservesStatusFavoriteAndSnapshot() async throws {
        let store = try makeStore()
        try store.setStatus(.watched, media: movie)
        try store.setFavorite(true, media: movie)
        try store.setPersonalRating(PersonalRating(halfStarUnits: 8), media: movie)
        let id = store.entries.first?.id
        try store.setPersonalRating(nil, media: movie)
        let entry = try XCTUnwrap(store.entries.first)
        XCTAssertEqual(entry.id, id)
        XCTAssertNil(entry.ratingHalfStarUnits)
        XCTAssertNil(entry.rating)
        XCTAssertNil(try entry.validatedRating())
        XCTAssertEqual(entry.status, "watched")
        XCTAssertTrue(entry.isFavorite)
        XCTAssertEqual(entry.savedMedia, movie)
    }

    @MainActor
    func testStatusChangesDoNotEraseRating() async throws {
        let store = try makeStore()
        try store.setPersonalRating(PersonalRating(halfStarUnits: 7), media: show)
        for status in [LibraryStatus.watchlist, .watching, .watched] {
            try store.setStatus(status, media: show)
            XCTAssertEqual(store.entries.first?.ratingHalfStarUnits, 7)
        }
        try store.setStatus(nil, media: show)
        XCTAssertEqual(store.entries.first?.ratingHalfStarUnits, 7)
    }

    @MainActor
    func testClearingUnratedMissingEntryIsNoOp() async throws {
        let store = try makeStore()
        try store.setPersonalRating(nil, media: movie)
        XCTAssertTrue(store.entries.isEmpty)
        try store.setStatus(.watchlist, media: movie)
        XCTAssertNil(try store.entries.first?.validatedRating())
    }

    @MainActor
    func testFailedRatingSaveRestoresPreviousValue() async throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let good = LibraryStore(container: container)
        try good.setPersonalRating(PersonalRating(halfStarUnits: 6), media: movie)
        let failing = LibraryStore(container: container, save: { _ in throw LibraryStoreError.saveFailed })
        XCTAssertThrowsError(try failing.setPersonalRating(PersonalRating(halfStarUnits: 10), media: movie))
        XCTAssertEqual(failing.entries.first?.ratingHalfStarUnits, 6)
        XCTAssertThrowsError(try failing.setPersonalRating(nil, media: movie))
        XCTAssertEqual(failing.entries.first?.ratingHalfStarUnits, 6)
    }

    @MainActor
    func testLegacyRatingCompatibilityAndInvalidDataPreservation() async throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let legacy = StoredLibraryEntry(entry: UserLibraryEntry(mediaID: SearchItem(movie).id, review: "Keep reserved data"))
        legacy.rating = 4.5
        container.mainContext.insert(legacy)
        try container.mainContext.save()
        XCTAssertEqual(try legacy.validatedRating()?.halfStarUnits, 9)
        XCTAssertNil(legacy.ratingHalfStarUnits, "Reading must not silently rewrite stored values")
        legacy.rating = 3.3
        XCTAssertThrowsError(try legacy.validatedRating())
        XCTAssertEqual(legacy.rating, 3.3)
        legacy.rating = 0
        XCTAssertNil(try legacy.validatedRating())
        try container.mainContext.save()
        let store = LibraryStore(container: container)
        try store.setPersonalRating(PersonalRating(halfStarUnits: 8), media: movie)
        XCTAssertEqual(store.entries.first?.review, "Keep reserved data")
        XCTAssertEqual(store.entries.first?.rating, 4)
        XCTAssertEqual(store.entries.first?.ratingHalfStarUnits, 8)
        try store.setPersonalRating(nil, media: movie)
        XCTAssertEqual(store.entries.first?.review, "Keep reserved data")
    }

    @MainActor
    func testRatingPersistsAcrossContainerReinitialization() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Ratings.store")
        try autoreleasepool {
            let store = LibraryStore(container: try PersistenceController.makeContainer(at: url))
            try store.setPersonalRating(PersonalRating(halfStarUnits: 9), media: movie)
        }
        let reopened = LibraryStore(container: try PersistenceController.makeContainer(at: url))
        let entry = try XCTUnwrap(reopened.entries.first)
        XCTAssertEqual(entry.ratingHalfStarUnits, 9)
        XCTAssertEqual(try entry.validatedRating()?.stars, 4.5)
        XCTAssertNil(try entry.domainEntry().status)
    }

    @MainActor
    func testDomainConversionUsesValidatedPersonalRating() async throws {
        let value = UserLibraryEntry(mediaID: SearchItem(movie).id, status: nil, rating: try PersonalRating(halfStarUnits: 3))
        let stored = StoredLibraryEntry(entry: value)
        XCTAssertEqual(try stored.domainEntry(), value)
        stored.ratingHalfStarUnits = 0
        XCTAssertThrowsError(try stored.domainEntry())
    }

    @MainActor
    private func makeStore() throws -> LibraryStore {
        LibraryStore(container: try PersistenceController.makeContainer(inMemory: true))
    }
}
