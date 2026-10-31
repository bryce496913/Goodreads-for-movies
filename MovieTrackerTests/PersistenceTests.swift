import SwiftData
import XCTest
@testable import MovieTracker

final class PersistenceTests: XCTestCase {
    @MainActor
    func testInMemoryContainerStartsEmpty() async throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let entries = try container.mainContext.fetch(FetchDescriptor<StoredLibraryEntry>())
        XCTAssertTrue(entries.isEmpty)
    }

    @MainActor
    func testLibraryEntryRoundTripThroughStore() async throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let added = Date(timeIntervalSince1970: 1_000)
        let updated = Date(timeIntervalSince1970: 2_000)
        let movieEntry = UserLibraryEntry(
            mediaID: MediaID(kind: .movie, value: "42"), status: .watched,
            isFavorite: true, rating: 4.5, review: "A thoughtful story.",
            addedAt: added, updatedAt: updated
        )
        let showEntry = UserLibraryEntry(mediaID: MediaID(kind: .tvShow, value: "42"), status: .watching)
        container.mainContext.insert(StoredLibraryEntry(entry: movieEntry))
        container.mainContext.insert(StoredLibraryEntry(entry: showEntry))
        try container.mainContext.save()

        // Read from a fresh context rather than relying on the inserted object instances.
        let context = ModelContext(container)
        let stored = try context.fetch(FetchDescriptor<StoredLibraryEntry>())
        let entries = try stored.map { try $0.domainEntry() }
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.first { $0.id == movieEntry.id }, movieEntry)
        XCTAssertEqual(entries.first { $0.id == showEntry.id }, showEntry)
    }

    @MainActor
    func testUnknownStoredValuesAreReportedInsteadOfSilentlyDefaulting() async {
        let stored = StoredLibraryEntry(entry: UserLibraryEntry(mediaID: MediaID(kind: .movie, value: "42")))
        stored.mediaKind = "unsupported"
        XCTAssertThrowsError(try stored.domainEntry()) { error in
            XCTAssertEqual(error as? StoredLibraryEntry.ConversionError, .unknownMediaKind)
        }
        stored.mediaKind = MediaID.Kind.movie.rawValue
        stored.status = "unsupported"
        XCTAssertThrowsError(try stored.domainEntry()) { error in
            XCTAssertEqual(error as? StoredLibraryEntry.ConversionError, .unknownLibraryStatus)
        }
    }

    @MainActor
    func testInMemoryContainersAreIsolated() async throws {
        let first = try PersistenceController.makeContainer(inMemory: true)
        first.mainContext.insert(StoredLibraryEntry(entry: UserLibraryEntry(
            mediaID: MediaID(kind: .tvShow, value: "42")
        )))
        try first.mainContext.save()
        let second = try PersistenceController.makeContainer(inMemory: true)
        XCTAssertEqual(try second.mainContext.fetchCount(FetchDescriptor<StoredLibraryEntry>()), 0)
    }
}
