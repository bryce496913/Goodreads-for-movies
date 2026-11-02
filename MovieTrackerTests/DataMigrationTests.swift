import SwiftData
import SQLite3
import XCTest
@testable import MovieTracker

final class DataMigrationTests: XCTestCase {
    @MainActor func testFoundationUnversionedStorePreservesAllAvailableContent() throws { try verify(.foundation) }
    @MainActor func testSnapshotUnversionedStorePreservesAllAvailableContent() throws { try verify(.snapshots) }
    @MainActor func testRatingUnversionedStorePreservesAllAvailableContent() throws { try verify(.ratings) }
    @MainActor func testDiaryUnversionedStorePreservesAllAvailableContent() throws { try verify(.diary) }
    @MainActor func testTVProgressUnversionedStorePreservesAllAvailableContent() throws { try verify(.tvProgress) }
    @MainActor func testCurrentUnversionedStoreAdoptsFrozenVersionWithoutContentChanges() throws { try verify(.current) }
    @MainActor func testExplicitOldVersionUsesTheDeclaredStages() throws { try verify(.foundation, versioned: true) }

    @MainActor private func verify(_ shape: MigrationFixtureShape, versioned: Bool = false) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Fixture.store")
        try MigrationFixtures.write(shape, at: url, versioned: versioned)
        for _ in 0..<2 {
            try autoreleasepool {
                let container = try PersistenceController.makeContainer(at: url)
                let store = LibraryStore(container: container)
                XCTAssertNil(store.loadError)
                XCTAssertEqual(store.integrityIssueCount, 0)
                XCTAssertEqual(store.entries.count, 3)
                XCTAssertEqual(Set(store.entries.map(\.id)), Set((1...3).map(MigrationFixtures.uuid)))
                XCTAssertEqual(Set(store.entries.compactMap(\.mediaID)), [MigrationFixtures.movieID, MigrationFixtures.tvID, MigrationFixtures.otherID])
                for (index, id) in [MigrationFixtures.movieID, MigrationFixtures.tvID, MigrationFixtures.otherID].enumerated() {
                    let row = try XCTUnwrap(store.entry(for: id))
                    XCTAssertEqual(row.rating, 4.5); XCTAssertEqual(try row.validatedRating()?.halfStarUnits, 9)
                    XCTAssertEqual(row.ratingHalfStarUnits, shape.hasUnits ? 9 : nil)
                    XCTAssertEqual(row.review, "Reserved legacy review \(index)"); XCTAssertTrue(row.isFavorite)
                    XCTAssertEqual(row.status, id.kind == .movie ? "watched" : "watching")
                    XCTAssertEqual(row.addedAt, MigrationFixtures.date); XCTAssertEqual(row.updatedAt, MigrationFixtures.date.addingTimeInterval(5))
                    XCTAssertEqual(row.ratingUpdatedAt, shape == .current ? MigrationFixtures.date.addingTimeInterval(40) : nil)
                    if shape.hasSnapshots {
                        XCTAssertEqual(row.savedTitle, id.kind == .movie ? "Saved Movie" : "Saved TV")
                        XCTAssertEqual(row.savedYear, 2024); XCTAssertEqual(row.savedPosterReference, "/poster.jpg")
                        XCTAssertEqual(row.savedPosterURL, "https://image.tmdb.org/t/p/w185/poster.jpg")
                        XCTAssertNotNil(row.savedMedia)
                    } else { XCTAssertNil(row.snapshotData); XCTAssertNil(row.savedTitle) }
                }
                XCTAssertEqual(store.personalReviews.count, shape.hasDiary ? 2 : 0)
                XCTAssertEqual(store.viewingEvents.count, shape.hasDiary ? 2 : 0)
                if shape.hasDiary {
                    let review = try XCTUnwrap(store.personalReviews.first { $0.id == MigrationFixtures.uuid(20) })
                    XCTAssertEqual(review.mediaID, MigrationFixtures.movieID)
                    XCTAssertEqual(review.text, "Private review preserved exactly\nSecond line")
                    XCTAssertEqual(review.viewingEventID, MigrationFixtures.uuid(10))
                    XCTAssertEqual(review.createdAt, MigrationFixtures.date); XCTAssertEqual(review.editedAt, MigrationFixtures.date.addingTimeInterval(30))
                    XCTAssertTrue(store.personalReviews.first { $0.id == MigrationFixtures.uuid(21) }?.isLegacyImport == true)
                    XCTAssertEqual(store.viewingEvents.first { $0.id == MigrationFixtures.uuid(10) }?.watchedDate, MigrationFixtures.date)
                    XCTAssertNil(store.viewingEvents.first { $0.id == MigrationFixtures.uuid(11) }?.watchedDate)
                    XCTAssertEqual(store.viewingEvents.first { $0.id == MigrationFixtures.uuid(11) }?.recordedAt, MigrationFixtures.date.addingTimeInterval(20))
                }
                XCTAssertEqual(store.tvSeasons.count, shape.hasEpisodes ? 1 : 0)
                XCTAssertEqual(store.episodeProgress.count, shape.hasEpisodes ? 2 : 0)
                if shape.hasEpisodes {
                    XCTAssertEqual(store.tvSeasons.first?.id, MigrationFixtures.uuid(30))
                    XCTAssertEqual(store.tvSeasons.first?.episodes, MigrationFixtures.episodes)
                    XCTAssertEqual(store.tvSeasons.first?.refreshedAt, MigrationFixtures.date)
                    XCTAssertTrue(store.isWatched(MigrationFixtures.episodes[0].id)); XCTAssertFalse(store.isWatched(MigrationFixtures.episodes[1].id))
                    XCTAssertEqual(store.episodeProgress.first { $0.id == MigrationFixtures.uuid(40) }?.watchedAt, MigrationFixtures.date)
                }
            }
        }
        try autoreleasepool {
            let store = LibraryStore(container: try PersistenceController.makeContainer(at: url))
            // A normal post-migration edit updates the same logical record, not a second row.
            try store.setFavorite(false, for: MigrationFixtures.movieID)
            try store.setFavorite(true, for: MigrationFixtures.movieID)
            XCTAssertEqual(store.entries.count, 3)
            XCTAssertEqual(store.entry(for: MigrationFixtures.movieID)?.id, MigrationFixtures.uuid(1))
        }
        let backups = try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("StoreSafetyBackups"), includingPropertiesForKeys: nil)
        XCTAssertEqual(backups.filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("COMPLETE").path) }.count, 3)
    }

    @MainActor func testCorruptedStoreIsNotReplacedWithEmptyDatabase() throws {
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Corrupted.store"), sentinel = Data("Preserve corrupted source bytes".utf8)
        try sentinel.write(to: url)
        XCTAssertThrowsError(try PersistenceController.makeContainer(at: url)) { error in
            XCTAssertEqual((error as? PersistenceOpenError)?.stage, .backup)
        }
        XCTAssertEqual(try Data(contentsOf: url), sentinel)
    }
    @MainActor func testEmptyExistingFileIsNotTreatedAsNewInstallation() throws {
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Empty.store")
        try Data().write(to: url)
        XCTAssertThrowsError(try PersistenceController.makeContainer(at: url))
        XCTAssertEqual(try Data(contentsOf: url), Data())
    }
    @MainActor func testMissingMainStoreWithJournalIsNotRecreated() throws {
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Missing.store"), journal = Data("Preserve remaining WAL".utf8)
        try journal.write(to: URL(fileURLWithPath: url.path + "-wal"))
        XCTAssertThrowsError(try PersistenceController.makeContainer(at: url)) { error in
            XCTAssertEqual((error as? PersistenceOpenError)?.stage, .incompleteStore)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: url.path + "-wal")), journal)
    }
    @MainActor func testBackupFailureStopsBeforeAnyMigration() throws {
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Blocked.store")
        try MigrationFixtures.write(.foundation, at: url)
        let original = try Data(contentsOf: url)
        try Data("Not a directory".utf8).write(to: directory.appendingPathComponent("StoreSafetyBackups"))
        XCTAssertThrowsError(try PersistenceController.makeContainer(at: url)) { error in
            XCTAssertEqual((error as? PersistenceOpenError)?.stage, .backup)
        }
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
    @MainActor func testExplicitMigrationFailureRetainsOriginalAndCoherentBackup() throws {
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Rejected.store")
        try MigrationFixtures.write(.foundation, at: url, versioned: true)
        let schema = Schema(versionedSchema: LibrarySchemaSnapshots.self)
        var backup: URL?
        XCTAssertThrowsError(try PersistenceController.open(schema: schema,
            configuration: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none), migrationPlan: RejectedMigrationPlan.self)) { error in
            XCTAssertEqual((error as? PersistenceOpenError)?.stage, .open)
            backup = (error as? PersistenceOpenError)?.backupDirectory
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("MIGRATION_ENTERED").path))
        let backupFile = try XCTUnwrap(backup).appendingPathComponent(url.lastPathComponent)
        try assertFoundationContent(at: backupFile)
        try assertFoundationContent(at: url)
    }
    @MainActor func testUnknownSchemaFailsWithoutErasingSourceOrBackup() throws {
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Unsupported.store")
        let schema = Schema([UnsupportedMigrationRecord.self])
        try autoreleasepool {
            let source = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            source.mainContext.insert(UnsupportedMigrationRecord())
            try source.mainContext.save()
        }
        var backup: URL?
        XCTAssertThrowsError(try PersistenceController.makeContainer(at: url)) { error in
            XCTAssertEqual((error as? PersistenceOpenError)?.stage, .schemaCheck)
            backup = (error as? PersistenceOpenError)?.backupDirectory
        }
        for sourceURL in [url, try XCTUnwrap(backup).appendingPathComponent(url.lastPathComponent)] {
            try autoreleasepool {
                let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: sourceURL, cloudKitDatabase: .none)])
                let rows = try container.mainContext.fetch(FetchDescriptor<UnsupportedMigrationRecord>())
                XCTAssertEqual(rows.count, 1); XCTAssertEqual(rows.first?.value, "Preserve unsupported content")
            }
        }
    }
    func testSafetyBackupIncludesUncheckpointedWALContent() throws {
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("WAL.store")
        var source: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &source), SQLITE_OK)
        defer { sqlite3_close_v2(source) }
        XCTAssertEqual(sqlite3_exec(source, "PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; CREATE TABLE fixture (value TEXT); INSERT INTO fixture VALUES ('committed WAL fixture');", nil, nil, nil), SQLITE_OK)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path + "-wal"))
        let backupURL = try StoreSafetyBackup.create(for: url).appendingPathComponent(url.lastPathComponent)
        var snapshot: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(backupURL.path, &snapshot, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { sqlite3_close_v2(snapshot) }
        var query: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(snapshot, "SELECT value FROM fixture", -1, &query, nil), SQLITE_OK)
        defer { sqlite3_finalize(query) }
        XCTAssertEqual(sqlite3_step(query), SQLITE_ROW)
        let value = sqlite3_column_text(query, 0).map { String(cString: $0) }
        XCTAssertEqual(value, "committed WAL fixture")
    }

    @MainActor private func assertFoundationContent(at url: URL) throws {
        try autoreleasepool {
            let schema = Schema(versionedSchema: LibrarySchemaFoundation.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let rows = try container.mainContext.fetch(FetchDescriptor<LibrarySchemaFoundation.StoredLibraryEntry>())
            XCTAssertEqual(rows.count, 3)
            XCTAssertTrue(rows.allSatisfy { $0.rating == 4.5 && $0.review?.hasPrefix("Reserved legacy review") == true })
        }
    }
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private enum RejectedMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [LibrarySchemaFoundation.self, LibrarySchemaSnapshots.self] }
    static var stages: [MigrationStage] {
        [.custom(fromVersion: LibrarySchemaFoundation.self, toVersion: LibrarySchemaSnapshots.self, willMigrate: { context in
            let url = try XCTUnwrap(context.container.configurations.first?.url)
            try Data("Test migration entered".utf8).write(to: url.deletingLastPathComponent().appendingPathComponent("MIGRATION_ENTERED"))
            throw NSError(domain: "MovieTracker.UnitTests.RejectedMigration", code: 13)
        }, didMigrate: nil)]
    }
}

@Model
private final class UnsupportedMigrationRecord {
    @Attribute(.unique) var id: UUID
    var value: String
    init() { id = UUID(); value = "Preserve unsupported content" }
}
