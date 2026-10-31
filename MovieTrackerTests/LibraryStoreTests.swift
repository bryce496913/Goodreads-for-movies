import SwiftData
import XCTest
@testable import MovieTracker

final class LibraryStoreTests: XCTestCase {
    private let movie = MediaSearchResult.movie(Movie(id: "tmdb:123", title: "Saved Movie", overview: "Offline synopsis"))
    private let show = MediaSearchResult.tvShow(TVShow(id: "tmdb:123", title: "Saved Show"))

    @MainActor
    func testMovieAndTVWatchlistsRemainDistinct() throws {
        let store = try makeStore()
        try store.setStatus(.watchlist, media: movie)
        try store.setStatus(.watchlist, media: show)
        XCTAssertEqual(store.entries.count, 2)
        XCTAssertEqual(store.entry(for: SearchItem(movie).id)?.status, "watchlist")
        XCTAssertEqual(store.entry(for: SearchItem(show).id)?.status, "watchlist")
    }

    @MainActor
    func testWatchingToWatchedUpdatesOneEntryAndPreservesFavorite() throws {
        let store = try makeStore()
        try store.setStatus(.watching, media: show)
        let id = try XCTUnwrap(store.entries.first).id
        let added = try XCTUnwrap(store.entries.first).addedAt
        try store.setFavorite(true, media: show)
        try store.setStatus(.watched, media: show)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.id, id)
        XCTAssertEqual(store.entries.first?.addedAt, added)
        XCTAssertEqual(store.entries.first?.status, "watched")
        XCTAssertTrue(store.entries.first?.isFavorite == true)
        XCTAssertThrowsError(try store.setStatus(.watching, media: movie))
    }

    @MainActor
    func testRepeatedSaveIsIdempotentAndNamespaceIsPartOfIdentity() throws {
        let store = try makeStore()
        try store.setStatus(.watchlist, media: movie)
        let updated = store.entries.first?.updatedAt
        try store.setStatus(.watchlist, media: movie)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.updatedAt, updated)
        try store.setStatus(.watchlist, media: .movie(Movie(id: "other:123", title: "Another provider")))
        XCTAssertEqual(store.entries.count, 2)
    }

    @MainActor
    func testClearStatusKeepsFavoriteAndNoStatusRoundTrips() throws {
        let store = try makeStore()
        try store.setStatus(.watchlist, media: movie)
        try store.setFavorite(true, media: movie)
        try store.setStatus(nil, media: movie)
        let record = try XCTUnwrap(store.entries.first)
        XCTAssertNil(try record.domainEntry().status)
        XCTAssertTrue(record.isFavorite)
        XCTAssertEqual(record.savedMedia, movie)
    }

    @MainActor
    func testRemovalTargetsOnlyOneMediaType() throws {
        let store = try makeStore()
        try store.setStatus(.watchlist, media: movie)
        try store.setStatus(.watchlist, media: show)
        try store.remove(SearchItem(movie).id)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.mediaKind, "tvShow")
        try store.remove(SearchItem(movie).id)
        XCTAssertEqual(store.entries.count, 1)
    }

    @MainActor
    func testSaveFailureRollsBackInsertAndStatusChanges() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let good = LibraryStore(container: container)
        try good.setStatus(.watchlist, media: movie)
        let failing = LibraryStore(container: container, save: { _ in throw LibraryStoreError.saveFailed })
        XCTAssertThrowsError(try failing.setStatus(.watched, media: movie))
        XCTAssertEqual(failing.entries.first?.status, "watchlist")
        XCTAssertThrowsError(try failing.setStatus(.watchlist, media: show))
        XCTAssertEqual(failing.entries.count, 1)
    }

    @MainActor
    func testExistingDuplicateRowsArePreservedAndNotSilentlyMerged() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        for _ in 0..<2 {
            container.mainContext.insert(StoredLibraryEntry(entry: UserLibraryEntry(mediaID: SearchItem(movie).id)))
        }
        try container.mainContext.save()
        let store = LibraryStore(container: container)
        XCTAssertThrowsError(try store.setStatus(.watched, media: movie))
        XCTAssertEqual(store.entries.count, 2)
    }

    @MainActor
    func testSnapshotSurvivesPersistentContainerReinitialization() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Library.store")
        try autoreleasepool {
            let store = LibraryStore(container: try PersistenceController.makeContainer(at: url))
            try store.setStatus(.watchlist, media: movie)
            try store.setFavorite(true, media: movie)
        }
        let reopened = LibraryStore(container: try PersistenceController.makeContainer(at: url))
        let record = try XCTUnwrap(reopened.entries.first)
        XCTAssertEqual(record.displayTitle, "Saved Movie")
        XCTAssertEqual(record.savedMedia, movie)
        XCTAssertTrue(record.isFavorite)
        XCTAssertEqual(record.status, "watchlist")
    }

    @MainActor
    func testLegacyMetadataAbsenceDoesNotDeleteRowOrReservedFields() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let record = StoredLibraryEntry(entry: UserLibraryEntry(mediaID: SearchItem(movie).id, rating: 4.5, review: "Reserved old data"))
        container.mainContext.insert(record)
        try container.mainContext.save()
        let store = LibraryStore(container: container)
        XCTAssertNil(store.entries.first?.savedMedia)
        try store.setStatus(.watched, media: movie)
        XCTAssertEqual(store.entries.first?.rating, 4.5)
        XCTAssertEqual(store.entries.first?.review, "Reserved old data")
    }

    @MainActor
    private func makeStore() throws -> LibraryStore {
        LibraryStore(container: try PersistenceController.makeContainer(inMemory: true))
    }
}
