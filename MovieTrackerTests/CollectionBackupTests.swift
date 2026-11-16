import SwiftData
import XCTest
@testable import MovieTracker

final class CollectionBackupTests: XCTestCase {
    @MainActor func testV06DiskReopenOfflineEditsExpiryRefreshAndBackupRestorePreservePersonalData() throws {
        let files = FileManager.default, instant = BackupFixtures.now
        let directory = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: directory) }
        let sourceURL = directory.appendingPathComponent("Source.store"), targetURL = directory.appendingPathComponent("Restored.store")
        let movie = MediaSearchResult.movie(Movie(id: BackupFixtures.movieID.value, title: "Locally retained movie", runtimeMinutes: 90,
            genres: [MediaGenre(id: "tmdb:18", name: "Drama")], metadataRetrievedAt: instant))
        let show = MediaSearchResult.tvShow(TVShow(id: BackupFixtures.showID.value, title: "Locally retained series", metadataRetrievedAt: instant))
        var expected = try BackupFixtures.populated().capturePersonalBackup(at: instant)
        var firstList = UUID(), otherList = UUID()
        try autoreleasepool {
            let store = try BackupFixtures.store(at: sourceURL)
            try store.restorePersonalBackup(BackupFixtures.plan(expected, into: store))
            try store.setStatus(.watchlist, media: movie)
            firstList = try store.saveCollection(name: "Tonight", now: instant)
            otherList = try store.saveCollection(name: "Keep separately", now: instant)
            for value in [movie, show] { try store.setCollectionMembership(true, collection: firstList, media: value, now: instant) }
            try store.setCollectionMembership(true, collection: otherList, media: movie, now: instant)
            let before = store.members(of: firstList).map(\.id)
            try store.reorderCollection(firstList, memberships: Array(before.reversed()), original: before, now: instant)
            expected = try store.capturePersonalBackup(at: instant)
            XCTAssertFalse(String(decoding: try BackupCodec.encode(expected), as: UTF8.self).contains("Locally retained"))
        }
        // Reopen actual on-disk stores, not just a second in-memory context. No provider client is involved.
        for pass in 0..<2 {
            try autoreleasepool {
                let store = try BackupFixtures.store(at: sourceURL)
                XCTAssertNil(store.loadError)
                XCTAssertEqual(try store.capturePersonalBackup(at: instant).canonical(), expected.canonical())
                XCTAssertEqual(store.members(of: firstList).map(\.position), [0, 1])
                XCTAssertEqual(store.members(of: firstList).compactMap(\.mediaID), [BackupFixtures.showID, BackupFixtures.movieID])
                if pass == 0 {
                    try store.setPersonalRating(PersonalRating(halfStarUnits: 10), media: movie)
                    try store.saveViewingEvent(id: LargeLibraryFixtures.uuid(900), media: movie, watchedDate: nil, now: instant)
                    try store.setEpisodeWatched(false, episode: BackupFixtures.episode, show: TVShow(id: BackupFixtures.showID.value, title: "Series"), now: instant)
                    try store.setEpisodeWatched(true, episode: BackupFixtures.episode, show: TVShow(id: BackupFixtures.showID.value, title: "Series"), now: instant)
                    expected = try store.capturePersonalBackup(at: instant)
                }
            }
        }
        try autoreleasepool {
            let later = instant.addingTimeInterval(MetadataPolicy.retention)
            let store = LibraryStore(container: try PersistenceController.makeContainer(at: sourceURL), clock: { later })
            XCTAssertEqual(try store.capturePersonalBackup(at: instant).canonical(), expected.canonical())
            try store.maintainMetadata()
            XCTAssertNil(store.cachedMedia(for: BackupFixtures.movieID))
            XCTAssertEqual(try store.capturePersonalBackup(at: instant).canonical(), expected.canonical())
            let refreshedMovie = MediaSearchResult.movie(Movie(id: BackupFixtures.movieID.value, title: "Refreshed movie", metadataRetrievedAt: later))
            let refreshedShow = MediaSearchResult.tvShow(TVShow(id: BackupFixtures.showID.value, title: "Refreshed series", metadataRetrievedAt: later))
            try store.metadataRefreshSucceeded(refreshedMovie)
            try store.metadataRefreshSucceeded(refreshedShow)
            XCTAssertEqual(store.cachedMedia(for: BackupFixtures.movieID)?.metadataRetrievedAt, later)
            XCTAssertEqual(store.cachedMedia(for: BackupFixtures.showID)?.metadataRetrievedAt, later)
            XCTAssertEqual(try store.capturePersonalBackup(at: instant).canonical(), expected.canonical())
            // Deleting one list leaves the shared title and other list, review, repeats and flags unchanged.
            try store.deleteCollection(firstList)
            let after = try store.capturePersonalBackup(at: instant)
            XCTAssertEqual(after.library, expected.library); XCTAssertEqual(after.reviews, expected.reviews)
            XCTAssertEqual(after.viewings, expected.viewings); XCTAssertEqual(after.episodeProgress, expected.episodeProgress)
            XCTAssertEqual(store.members(of: otherList).count, 1)
            expected = after
        }
        let bytes = try BackupCodec.encode(expected)
        let decoded = try BackupCodec.decode(bytes)
        try autoreleasepool {
            let target = try BackupFixtures.store(at: targetURL)
            try target.restorePersonalBackup(BackupFixtures.plan(decoded, into: target))
            let again = try BackupFixtures.plan(decoded, into: target)
            XCTAssertEqual(again.counts.total, 0)
            try target.restorePersonalBackup(again)
        }
        try autoreleasepool {
            let reopened = try BackupFixtures.store(at: targetURL)
            XCTAssertEqual(try reopened.capturePersonalBackup(at: instant).canonical(), expected.canonical())
            XCTAssertEqual(reopened.entry(for: BackupFixtures.movieID)?.ratingHalfStarUnits, 10)
            XCTAssertEqual(reopened.personalReviews.first?.text, BackupFixtures.text)
            XCTAssertEqual(reopened.viewingEvents.count, 3)
            XCTAssertTrue(reopened.isWatched(BackupFixtures.episode.id))
            XCTAssertNil(reopened.cachedMedia(for: BackupFixtures.movieID)) // Restore never reinstates provider content.
        }
    }

    private let now = Date(timeIntervalSince1970: 1_767_225_600)
    @MainActor private func populated() throws -> LibraryStore {
        let store = try BackupFixtures.store()
        let a = try store.saveCollection(name: "私の映画 🎬"), b = try store.saveCollection(name: "Together")
        for n in 1...3 {
            let value = MediaSearchResult.movie(Movie(id: "fixture:\(n)", title: "PROVIDER_TITLE"))
            try store.setCollectionMembership(true, collection: a, media: value)
            try store.setCollectionMembership(true, collection: b, media: value)
        }
        try store.reorderCollection(a, memberships: Array(store.members(of: a).map(\.id).reversed()))
        return store
    }

    @MainActor func testV2ExportRestorePreservesUUIDsMembershipsOrderAndRepeatImport() throws {
        let source = try populated(), target = try BackupFixtures.store()
        let backup = try source.capturePersonalBackup(at: now)
        XCTAssertEqual(backup.version, 2)
        let bytes = try BackupCodec.encode(backup)
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("PROVIDER_TITLE"))
        let decoded = try BackupCodec.decode(bytes)
        try target.restorePersonalBackup(BackupFixtures.plan(decoded, into: target))
        let restored = try target.capturePersonalBackup(at: now)
        XCTAssertEqual(restored.canonical(), backup.canonical())
        let again = try BackupFixtures.plan(decoded, into: target)
        XCTAssertEqual(again.counts.total, 0)
        try target.restorePersonalBackup(again)
        XCTAssertEqual(target.collectionMemberships.count, 6)
    }

    @MainActor func testActualV1JSONWithoutCollectionKeysRestoresEmptyCollections() throws {
        var backup = try BackupFixtures.populated().capturePersonalBackup(at: now)
        backup.version = 1
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: BackupCodec.encode(backup)) as? [String: Any])
        object.removeValue(forKey: "collections"); object.removeValue(forKey: "collectionMemberships")
        let decoded = try BackupCodec.decode(JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(decoded.collections.isEmpty); XCTAssertTrue(decoded.collectionMemberships.isEmpty)
        let target = try BackupFixtures.store()
        try target.restorePersonalBackup(BackupFixtures.plan(decoded, into: target))
        XCTAssertEqual(target.personalReviews.count, backup.reviews.count)
        XCTAssertTrue(target.collections.isEmpty)
    }

    @MainActor func testExistingCollectionUUIDKeepsLocalNameMembershipsAndOrder() throws {
        let source = try populated(), target = try BackupFixtures.store()
        let backup = try source.capturePersonalBackup(at: now)
        try target.restorePersonalBackup(BackupFixtures.plan(backup, into: target))
        let owner = try XCTUnwrap(target.collections.first)
        try target.saveCollection(id: owner.id, name: "Local name")
        let first = try XCTUnwrap(target.members(of: owner.id).first)
        try target.removeCollectionMembers(owner.id, memberships: [first.id])
        let before = target.members(of: owner.id).map(\.id)
        let plan = try BackupFixtures.plan(backup, into: target)
        XCTAssertFalse(plan.conflicts.isEmpty)
        try target.restorePersonalBackup(plan)
        XCTAssertEqual(target.collections.first(where: { $0.id == owner.id })?.name, "Local name")
        XCTAssertEqual(target.members(of: owner.id).map(\.id), before)
    }

    @MainActor func testNameConflictSkipsWholeIncomingCollectionWithoutRenaming() throws {
        let source = try populated(), target = try BackupFixtures.store()
        let existing = try target.saveCollection(name: "TOGETHER")
        let plan = try BackupFixtures.plan(source.capturePersonalBackup(at: now), into: target)
        XCTAssertTrue(plan.conflicts.contains { $0.contains("Collection") })
        try target.restorePersonalBackup(plan)
        XCTAssertEqual(target.collections.filter { CollectionName.key($0.name) == "together" }.map(\.id), [existing])
        XCTAssertTrue(target.members(of: existing).isEmpty)
    }

    @MainActor func testMalformedReferencesDuplicateNamesPositionsAndFutureVersionsReject() throws {
        let backup = try populated().capturePersonalBackup(at: now)
        let row = try XCTUnwrap(backup.collectionMemberships.first)
        var bad = backup
        bad.collectionMemberships[0] = .init(id: row.id, collectionID: UUID(), mediaID: row.mediaID, position: row.position, addedAt: row.addedAt)
        XCTAssertThrowsError(try BackupCodec.encode(bad))
        bad = backup
        bad.collectionMemberships[0] = .init(id: row.id, collectionID: row.collectionID, mediaID: row.mediaID, position: 99, addedAt: row.addedAt)
        XCTAssertThrowsError(try BackupCodec.encode(bad))
        bad = backup
        bad.collections.append(.init(id: UUID(), name: backup.collections[0].name.uppercased(), createdAt: now, updatedAt: now))
        XCTAssertThrowsError(try BackupCodec.encode(bad))
        bad = backup; bad.version = 99
        XCTAssertThrowsError(try BackupCodec.encode(bad))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: BackupCodec.encode(backup)) as? [String: Any])
        object.removeValue(forKey: "collectionMemberships")
        XCTAssertThrowsError(try BackupCodec.decode(JSONSerialization.data(withJSONObject: object)))
    }

    @MainActor func testCollectionRestoreFailureRollsBackAllNewRows() throws {
        let source = try populated()
        var fail = false
        let target = LibraryStore(container: try PersistenceController.makeContainer(inMemory: true), save: { context in
            if fail { throw LibraryStoreError.saveFailed }; try context.save()
        })
        let local = try target.saveCollection(name: "Local")
        try target.setFavorite(true, media: .movie(Movie(id: "fixture:local", title: "Local title")))
        let before = try target.capturePersonalBackup(at: now).canonical()
        let plan = try BackupFixtures.plan(source.capturePersonalBackup(at: now), into: target)
        fail = true
        XCTAssertThrowsError(try target.restorePersonalBackup(plan))
        XCTAssertEqual(try target.capturePersonalBackup(at: now).canonical(), before)
        XCTAssertEqual(target.collections.map(\.id), [local])
        XCTAssertTrue(target.collectionMemberships.isEmpty)
    }

    @MainActor func testCollectionChangeInvalidatesPreparedRestoreWithoutPartialWrites() throws {
        let source = try populated(), target = try BackupFixtures.store()
        let plan = try BackupFixtures.plan(source.capturePersonalBackup(at: now), into: target)
        let local = try target.saveCollection(name: "Local new list")
        XCTAssertThrowsError(try target.restorePersonalBackup(plan))
        XCTAssertEqual(target.collections.map(\.id), [local])
        XCTAssertTrue(target.collectionMemberships.isEmpty)
    }

    @MainActor func testMembershipUUIDCollisionSkipsIncomingCollectionAsOneUnit() throws {
        let source = try populated(), target = try BackupFixtures.store()
        let backup = try source.capturePersonalBackup(at: now)
        let membership = try XCTUnwrap(backup.collectionMemberships.first)
        let local = try target.saveCollection(name: "Existing")
        // Build a valid existing portable snapshot with a conflicting membership UUID, not a second import path.
        var localBackup = try target.capturePersonalBackup(at: now)
        localBackup.collectionMemberships = [.init(id: membership.id, collectionID: local,
            mediaID: membership.mediaID, position: 0, addedAt: now)]
        let plan = try BackupMergePlanner.prepare(backup, local: localBackup, revision: 0)
        XCTAssertFalse(plan.additions.collections.contains { $0.id == membership.collectionID })
        XCTAssertFalse(plan.additions.collectionMemberships.contains { $0.collectionID == membership.collectionID })
        XCTAssertFalse(plan.conflicts.isEmpty)
    }

    @MainActor func testRecoveryArchiveIncludesCollectionsAndKeepsProviderBodiesOut() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try PersistenceController.makeContainer(inMemory: true), store = LibraryStore(container: source)
        let id = try store.saveCollection(name: "Recovery")
        try store.setCollectionMembership(true, collection: id, media: .movie(Movie(id: "fixture:1", title: "PROVIDER_TITLE")))
        let archive = try PersonalDataArchive.capture(source.mainContext), url = directory.appendingPathComponent("PersonalData.json")
        try archive.writeVerified(to: url)
        XCTAssertFalse(try String(contentsOf: url, encoding: .utf8).contains("PROVIDER_TITLE"))
        let target = try PersistenceController.makeContainer(inMemory: true)
        try PersonalDataArchive.read(url).restore(into: target.mainContext); try target.mainContext.save()
        let restored = LibraryStore(container: target)
        XCTAssertEqual(restored.collections.first?.id, id)
        XCTAssertEqual(restored.members(of: id).map(\.id), store.members(of: id).map(\.id))
    }

    @MainActor func testLegacyInternalArchiveWithoutCollectionKeysStillRestores() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try PersistenceController.makeContainer(inMemory: true)
        let store = LibraryStore(container: source)
        try store.setFavorite(true, media: .movie(Movie(id: "fixture:legacy", title: "Private record reference")))
        var archive = try PersonalDataArchive.capture(source.mainContext)
        archive.format = 1; archive.collections = nil; archive.collectionMemberships = nil
        let url = dir.appendingPathComponent("Legacy.json")
        try archive.writeVerified(to: url)
        let target = try PersistenceController.makeContainer(inMemory: true)
        try PersonalDataArchive.read(url).restore(into: target.mainContext); try target.mainContext.save()
        let restored = LibraryStore(container: target)
        XCTAssertEqual(restored.entries.count, 1); XCTAssertTrue(restored.entries.first?.isFavorite == true)
        XCTAssertTrue(restored.collections.isEmpty)
    }

    @MainActor func testV3SafetyBackupConversionPreservesCollectionRecords() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("CollectionSource.store")
        let store = LibraryStore(container: try PersistenceController.makeContainer(at: source))
        let id = try store.saveCollection(name: "Recoverable private list")
        try store.setCollectionMembership(true, collection: id, media: .movie(Movie(id: "fixture:backup", title: "PROVIDER_TITLE")))
        let backup = try StoreSafetyBackup.create(for: source)
        XCTAssertEqual(MetadataArchiveMaintenance.convertBackups(beside: source), 0)
        let archive = try PersonalDataArchive.read(backup.appendingPathComponent("PersonalData.json"))
        XCTAssertEqual(archive.collections?.first?.id, id)
        XCTAssertEqual(archive.collectionMemberships?.first?.id, store.members(of: id).first?.id)
        XCTAssertEqual(store.collections.first?.id, id)
    }

    @MainActor func testDiskV2ToV3PreservesEveryPersonalEntityAndRepeatedOpen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Version2.store")
        let movie = MediaSearchResult.movie(Movie(id: "fixture:movie", title: "Movie"))
        let movieID = SearchItem(movie).id, libraryID = UUID(), eventID = UUID(), reviewID = UUID(), flagID = UUID()
        let show = TVShow(id: "fixture:show", title: "Show")
        let episode = TVEpisode(id: EpisodeID(seriesID: show.id, providerValue: "fixture:episode"), seasonNumber: 1, number: 1, title: "Episode", airDate: now, overview: "", runtimeMinutes: nil)
        try autoreleasepool {
            let schema = Schema(versionedSchema: LibrarySchemaV2.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = container.mainContext
            context.insert(StoredLibraryEntry(entry: UserLibraryEntry(id: libraryID, mediaID: movieID, status: .watched, isFavorite: true, rating: try PersonalRating(halfStarUnits: 9))))
            context.insert(try StoredViewingEvent(id: eventID, media: movie, watchedDate: nil, recordedAt: now))
            context.insert(try StoredPersonalReview(id: reviewID, media: movie, text: "Preserved review", createdAt: now, viewingEventID: eventID))
            let season = try StoredTVSeason(show: show, summary: TVSeasonSummary(number: 1, providerID: nil, name: "One", episodeCount: 1))
            context.insert(season)
            let flag = try StoredEpisodeProgress(episode: episode, watched: true, now: now)
            flag.id = flagID; context.insert(flag)
            context.insert(StoredMetadataState(id: movieID, scope: "title"))
            try context.save()
        }
        var collectionID: UUID?
        for run in 0..<2 {
            try autoreleasepool {
                let store = LibraryStore(container: try PersistenceController.makeContainer(at: url))
                XCTAssertNil(store.loadError)
                XCTAssertEqual(store.entry(for: movieID)?.id, libraryID)
                XCTAssertEqual(store.entry(for: movieID)?.ratingHalfStarUnits, 9)
                XCTAssertTrue(store.entry(for: movieID)?.isFavorite == true)
                XCTAssertEqual(store.entry(for: movieID)?.status, "watched")
                XCTAssertEqual(store.viewingEvents.first?.id, eventID)
                XCTAssertEqual(store.personalReviews.first?.id, reviewID)
                XCTAssertEqual(store.personalReviews.first?.text, "Preserved review")
                XCTAssertEqual(store.episodeProgress.first?.id, flagID)
                XCTAssertTrue(store.isWatched(episode.id)); XCTAssertEqual(store.metadataStates.count, 1)
                if run == 0 {
                    XCTAssertTrue(store.collections.isEmpty)
                    collectionID = try store.saveCollection(name: "After migration")
                    try store.setCollectionMembership(true, collection: collectionID!, media: movie)
                } else { XCTAssertEqual(store.collections.first?.id, collectionID); XCTAssertEqual(store.collectionMemberships.count, 1) }
            }
        }
    }
}
