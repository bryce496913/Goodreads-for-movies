import SwiftData
import XCTest
@testable import MovieTracker

final class DataIntegrityTests: XCTestCase {
    @MainActor func testIdentitySafeguardsRejectDuplicateLibraryInsertion() throws {
        try withStore { store, _ in
            let movie = MigrationFixtures.movie
            try store.setPersonalRating(PersonalRating(halfStarUnits: 8), media: movie)
            let original = try XCTUnwrap(store.entry(for: MigrationFixtures.movieID))
            let originalID = original.id
            XCTAssertThrowsError(try store.writeTransaction { context in
                let duplicate = StoredLibraryEntry(entry: UserLibraryEntry(mediaID: MigrationFixtures.movieID, review: "Must not replace original"))
                context.insert(duplicate)
            })
            XCTAssertEqual(store.entries.count, 1); XCTAssertEqual(store.entries.first?.id, originalID)
            XCTAssertEqual(store.entries.first?.ratingHalfStarUnits, 8)
        }
    }
    @MainActor func testMovieTVAndNamespaceKeysRemainDistinctAcrossRepeatedWrites() throws {
        try withStore { store, _ in
            for _ in 0..<3 {
                try store.setStatus(.watchlist, media: MigrationFixtures.movie)
                try store.setStatus(.watching, media: .tvShow(MigrationFixtures.show))
                try store.setStatus(.watched, media: .movie(Movie(id: MigrationFixtures.otherID.value, title: "Other provider")))
            }
            XCTAssertEqual(store.entries.count, 3)
            XCTAssertEqual(Set(store.entries.compactMap(\.mediaID)), [MigrationFixtures.movieID, MigrationFixtures.tvID, MigrationFixtures.otherID])
            XCTAssertEqual(store.integrityIssueCount, 0)
        }
    }
    @MainActor func testPreexistingDuplicateEpisodeRowsCannotBeBulkUnwatchedOrRefreshed() throws {
        try withStore { store, container in
            let show = MigrationFixtures.show, episode = MigrationFixtures.episodes[0]
            try store.cacheSeasonCatalog(show: show)
            try store.setEpisodeWatched(true, episode: episode, show: show, now: MigrationFixtures.date)
            // Inject pre-existing corruption outside the writer, rather than pretending it was a supported mutation.
            container.mainContext.insert(try StoredEpisodeProgress(episode: episode, watched: true, now: MigrationFixtures.date))
            try container.mainContext.save(); store.reload()
            XCTAssertGreaterThan(store.integrityIssueCount, 0)
            let season = try XCTUnwrap(store.seasons(for: show.id).first)
            XCTAssertThrowsError(try store.setSeasonWatched(false, season: season, show: show))
            XCTAssertThrowsError(try store.cacheSeason(TVSeasonDetails(seriesID: show.id, number: 1, name: "Changed", episodes: [episode]), show: show))
            XCTAssertEqual(store.episodeProgress.count, 2)
            XCTAssertTrue(store.episodeProgress.allSatisfy { $0.isWatched && $0.watchedAt == MigrationFixtures.date })
        }
    }
    @MainActor func testNewDuplicateEpisodeAndSeasonKeysAreRejectedAtomically() throws {
        try withStore { store, _ in
            let show = MigrationFixtures.show, episode = MigrationFixtures.episodes[0]
            try store.setEpisodeWatched(true, episode: episode, show: show, now: MigrationFixtures.date)
            XCTAssertThrowsError(try store.writeTransaction { context in
                context.insert(try StoredEpisodeProgress(episode: episode, watched: false, now: MigrationFixtures.date))
            })
            XCTAssertThrowsError(try store.writeTransaction { context in
                context.insert(try StoredTVSeason(show: show, summary: try XCTUnwrap(show.seasons?.first)))
            })
            XCTAssertEqual(store.episodeProgress.count, 1); XCTAssertTrue(store.isWatched(episode.id))
            XCTAssertEqual(store.seasons(for: show.id).count, 1)
        }
    }
    @MainActor func testDanglingCrossMediaAndDoubleReviewAssociationsAreRejected() throws {
        try withStore { store, _ in
            let eventID = MigrationFixtures.uuid(10)
            try store.saveViewingEvent(id: eventID, media: MigrationFixtures.movie, watchedDate: nil, now: MigrationFixtures.date)
            for (media, link) in [(MigrationFixtures.movie, MigrationFixtures.uuid(99)), (.tvShow(MigrationFixtures.show), eventID)] {
                XCTAssertThrowsError(try store.writeTransaction { context in
                    context.insert(try StoredPersonalReview(id: UUID(), media: media, text: "Preserve no dangling link", createdAt: MigrationFixtures.date, viewingEventID: link))
                })
            }
            try store.saveReview(id: MigrationFixtures.uuid(20), media: MigrationFixtures.movie, text: "One linked review", eventID: eventID, now: MigrationFixtures.date)
            XCTAssertThrowsError(try store.writeTransaction { context in
                context.insert(try StoredPersonalReview(id: UUID(), media: MigrationFixtures.movie, text: "Second link forbidden", createdAt: MigrationFixtures.date, viewingEventID: eventID))
            })
            XCTAssertEqual(store.personalReviews.count, 1); XCTAssertEqual(store.viewingEvents.count, 1)
        }
    }
    @MainActor func testIndependentReviewsAndEventsNeedNoLibraryParentOrCascade() throws {
        try withStore { store, _ in
            let movie = MigrationFixtures.movie, id = MigrationFixtures.movieID
            try store.setPersonalRating(PersonalRating(halfStarUnits: 9), media: movie)
            try store.saveViewingEvent(id: MigrationFixtures.uuid(10), media: movie, watchedDate: nil, now: MigrationFixtures.date)
            try store.saveReview(id: MigrationFixtures.uuid(20), media: movie, text: "Kept review", eventID: MigrationFixtures.uuid(10), now: MigrationFixtures.date)
            try store.remove(id)
            XCTAssertTrue(store.entries.isEmpty)
            XCTAssertEqual(store.personalReviews.count, 1); XCTAssertEqual(store.viewingEvents.count, 1)
            XCTAssertEqual(store.integrityIssueCount, 0)
            try store.deleteViewingEvent(MigrationFixtures.uuid(10))
            XCTAssertEqual(store.personalReviews.first?.text, "Kept review")
            XCTAssertNil(store.personalReviews.first?.viewingEventID)
            XCTAssertTrue(store.entries.isEmpty, "Deleting an event must not recreate a title or rating")
        }
    }
    @MainActor func testMetadataAndStatusChangesPreserveEveryPersonalField() throws {
        try withStore { store, _ in
            let media = MigrationFixtures.movie, id = MigrationFixtures.movieID
            try store.setStatus(.watched, media: media)
            try store.setPersonalRating(PersonalRating(halfStarUnits: 7), media: media)
            try store.setFavorite(true, media: media)
            try store.saveReview(id: MigrationFixtures.uuid(20), media: media, text: "Private review", now: MigrationFixtures.date)
            let before = try XCTUnwrap(store.entry(for: id)), uuid = before.id, added = before.addedAt, rated = before.ratingUpdatedAt
            let fresh = MediaSearchResult.movie(Movie(id: id.value, title: "Updated metadata", overview: "New synopsis"))
            try store.setStatus(.watchlist, media: fresh)
            let row = try XCTUnwrap(store.entry(for: id))
            XCTAssertEqual(row.id, uuid); XCTAssertEqual(row.addedAt, added); XCTAssertEqual(row.ratingUpdatedAt, rated)
            XCTAssertEqual(row.ratingHalfStarUnits, 7); XCTAssertTrue(row.isFavorite)
            XCTAssertEqual(store.personalReviews.first?.text, "Private review")
            XCTAssertEqual(row.savedTitle, "Updated metadata")
        }
    }
    @MainActor func testFailedDiskWriteDoesNotLosePersonalRowsAfterReopening() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Failure.store")
        try autoreleasepool {
            let container = try PersistenceController.makeContainer(at: url)
            let good = LibraryStore(container: container)
            try good.saveReview(id: MigrationFixtures.uuid(20), media: MigrationFixtures.movie, text: "Original text", now: MigrationFixtures.date)
            let failing = LibraryStore(container: container, save: { _ in throw LibraryStoreError.saveFailed })
            XCTAssertThrowsError(try failing.saveReview(id: MigrationFixtures.uuid(20), media: MigrationFixtures.movie, text: "Lost edit"))
            XCTAssertThrowsError(try failing.setEpisodeWatched(true, episode: MigrationFixtures.episodes[0], show: MigrationFixtures.show))
        }
        let reopened = LibraryStore(container: try PersistenceController.makeContainer(at: url))
        XCTAssertEqual(reopened.personalReviews.first?.text, "Original text")
        XCTAssertTrue(reopened.episodeProgress.isEmpty); XCTAssertTrue(reopened.tvSeasons.isEmpty)
        XCTAssertEqual(reopened.entries.count, 1)
    }
    @MainActor private func withStore(_ operation: (LibraryStore, ModelContainer) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try autoreleasepool {
            let container = try PersistenceController.makeContainer(at: directory.appendingPathComponent("Integrity.store"))
            try operation(LibraryStore(container: container), container)
        }
    }
}
