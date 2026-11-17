import SwiftData
import XCTest
@testable import MovieTracker

final class CollectionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_767_225_600)
    private func media(_ n: Int, tv: Bool = false) -> MediaSearchResult {
        tv ? .tvShow(TVShow(id: "fixture:\(n)", title: "Show \(n)")) : .movie(Movie(id: "fixture:\(n)", title: "Movie \(n)"))
    }
    @MainActor private func makeStore() throws -> LibraryStore { LibraryStore(container: try PersistenceController.makeContainer(inMemory: true)) }

    @MainActor func testSharedCollectionReferencesSurviveMainRemovalAndPersonalOnlyDiskRestore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appendingPathComponent("Source.store"), targetURL = directory.appendingPathComponent("Target.store")
        let movie = media(1), identity = SearchItem(movie).id, other = media(2)
        var exported: Data?
        var first = UUID(), second = UUID(), order: [UUID] = []
        let instant = now
        try autoreleasepool {
            let store = LibraryStore(container: try PersistenceController.makeContainer(at: sourceURL))
            first = try store.saveCollection(name: "A"); second = try store.saveCollection(name: "B")
            try store.setCollectionMembership(true, collection: first, media: movie)
            try store.setCollectionMembership(true, collection: second, media: movie)
            XCTAssertEqual(store.entry(for: identity)?.status, "none")
            try store.setCollectionMembership(true, collection: first, media: other)
            let original = store.members(of: first).map(\.id)
            try store.reorderCollection(first, memberships: Array(original.reversed()), original: original)
            order = store.members(of: first).map(\.id)
            try store.setPersonalRating(PersonalRating(halfStarUnits: 8), media: movie)
            try store.setStatus(.watched, media: movie)
            try store.setFavorite(true, media: movie)
            try store.saveReview(id: LargeLibraryFixtures.uuid(800), media: movie, text: "Preserved private review", now: instant)
            try store.saveViewingEvent(id: LargeLibraryFixtures.uuid(801), media: movie, watchedDate: nil, now: instant)
            try store.remove(identity)
            XCTAssertNil(store.entry(for: identity)) // Models the documented confirmed entry/rating/status/favorite removal scope.
            XCTAssertEqual(store.members(of: first).map(\.id), order)
            XCTAssertTrue(store.isInCollection(second, mediaID: identity))
            let saved = try XCTUnwrap(store.offlineMedia(for: identity))
            XCTAssertEqual(SearchItem(saved).id, identity) // Same typed route still opens through a collection.
            XCTAssertEqual(store.reviews(for: identity).first?.text, "Preserved private review")
            XCTAssertEqual(store.events(for: identity).count, 1)
            exported = try BackupCodec.encode(store.capturePersonalBackup(at: instant))
        }
        let decoded = try BackupCodec.decode(XCTUnwrap(exported))
        XCTAssertFalse(decoded.library.contains { $0.mediaID == identity })
        try autoreleasepool {
            let target = LibraryStore(container: try PersistenceController.makeContainer(at: targetURL))
            try target.restorePersonalBackup(BackupFixtures.plan(decoded, into: target))
            XCTAssertNil(target.entry(for: identity)) // Restore must not silently recreate a removed personal row.
            XCTAssertEqual(target.members(of: first).map(\.id), order)
            XCTAssertTrue(target.isInCollection(second, mediaID: identity))
            XCTAssertEqual(SearchItem(try XCTUnwrap(target.offlineMedia(for: identity))).id, identity)
            XCTAssertEqual(target.reviews(for: identity).first?.text, "Preserved private review")
            let repeatPlan = try BackupFixtures.plan(decoded, into: target)
            XCTAssertEqual(repeatPlan.counts.total, 0); try target.restorePersonalBackup(repeatPlan)
            let before = try target.capturePersonalBackup(at: instant)
            try target.deleteCollection(first)
            let after = try target.capturePersonalBackup(at: instant)
            XCTAssertEqual(after.library, before.library); XCTAssertEqual(after.reviews, before.reviews)
            XCTAssertEqual(after.viewings, before.viewings); XCTAssertEqual(after.episodeProgress, before.episodeProgress)
            XCTAssertTrue(target.isInCollection(second, mediaID: identity))
        }
        try autoreleasepool {
            let reopened = LibraryStore(container: try PersistenceController.makeContainer(at: targetURL))
            XCTAssertNil(reopened.loadError); XCTAssertNil(reopened.entry(for: identity))
            XCTAssertTrue(reopened.isInCollection(second, mediaID: identity))
            XCTAssertEqual(reopened.reviews(for: identity).count, 1); XCTAssertEqual(reopened.events(for: identity).count, 1)
        }
    }

    @MainActor func testCreateRenameUnicodeAndCaseInsensitiveDuplicateNames() throws {
        let store = try makeStore()
        let id = try store.saveCollection(name: "  Café 🎬  ", now: now)
        XCTAssertEqual(store.collections.first?.name, "Café 🎬")
        XCTAssertThrowsError(try store.saveCollection(name: "CAFÉ 🎬", now: now))
        try store.saveCollection(id: id, name: "日本の映画", now: now.addingTimeInterval(1))
        XCTAssertEqual(store.collections.first?.id, id)
        XCTAssertEqual(store.collections.first?.createdAt, now)
        XCTAssertEqual(store.collections.first?.name, "日本の映画")
        for invalid in ["", " \n ", String(repeating: "a", count: 101), "bad\nname"] {
            XCTAssertThrowsError(try store.saveCollection(name: invalid, now: now))
        }
        XCTAssertEqual(store.collections.count, 1)
        XCTAssertNoThrow(try store.saveCollection(name: "Family 👨‍👩‍👧‍👦"))
    }

    @MainActor func testDuplicateMembershipIsIdempotentAndMovieTVRemainDistinct() throws {
        let store = try makeStore(), id = try store.saveCollection(name: "Mixed")
        try store.setCollectionMembership(true, collection: id, media: media(1), now: now)
        let membership = store.members(of: id).first?.id
        try store.setCollectionMembership(true, collection: id, media: media(1), now: now.addingTimeInterval(1))
        try store.setCollectionMembership(true, collection: id, media: media(1, tv: true), now: now)
        XCTAssertEqual(store.members(of: id).count, 2)
        XCTAssertEqual(store.members(of: id).first?.id, membership)
        XCTAssertEqual(Set(store.members(of: id).compactMap(\.mediaID)).count, 2)
        XCTAssertTrue(store.entries.allSatisfy { $0.status == "none" })
        XCTAssertEqual(store.entries.count, 2)
    }

    @MainActor func testReorderAppendRemoveAndIndependentLists() throws {
        let store = try makeStore(), first = try store.saveCollection(name: "First"), second = try store.saveCollection(name: "Second")
        for n in 1...3 {
            try store.setCollectionMembership(true, collection: first, media: media(n), now: now)
            try store.setCollectionMembership(true, collection: second, media: media(n), now: now)
        }
        let original = store.members(of: first).map(\.id), other = store.members(of: second).map(\.id)
        let reversed = Array(original.reversed()), libraryOrder = store.entries.map(\.id), revision = store.libraryRevision
        try store.reorderCollection(first, memberships: reversed)
        XCTAssertEqual(store.entries.map(\.id), libraryOrder)
        XCTAssertEqual(store.libraryRevision, revision)
        XCTAssertEqual(store.members(of: first).map(\.id), reversed)
        XCTAssertEqual(store.members(of: second).map(\.id), other)
        try store.setCollectionMembership(true, collection: first, media: media(4))
        XCTAssertEqual(store.members(of: first).map(\.position), [0, 1, 2, 3])
        XCTAssertEqual(store.members(of: first).last?.mediaID, SearchItem(media(4)).id)
        try store.setCollectionMembership(false, collection: first, media: media(2))
        XCTAssertEqual(store.members(of: first).map(\.position), [0, 1, 2])
        XCTAssertEqual(store.members(of: first).compactMap(\.mediaID), [SearchItem(media(3)).id, SearchItem(media(1)).id, SearchItem(media(4)).id])
        XCTAssertThrowsError(try store.reorderCollection(first, memberships: original))
    }

    @MainActor func testDeleteCollectionKeepsPersonalDataAndOtherMemberships() throws {
        let store = try makeStore(), a = try store.saveCollection(name: "A"), b = try store.saveCollection(name: "B")
        let value = media(1), id = SearchItem(value).id
        try store.setStatus(.watched, media: value)
        try store.setFavorite(true, media: value)
        try store.setPersonalRating(PersonalRating(halfStarUnits: 9), media: value)
        let event = UUID(), review = UUID()
        try store.saveViewingEvent(id: event, media: value, watchedDate: nil)
        try store.saveReview(id: review, media: value, text: "Private", eventID: event)
        let show = TVShow(id: "fixture:show", title: "Show")
        let ep = TVEpisode(id: EpisodeID(seriesID: show.id, providerValue: "fixture:ep"), seasonNumber: 1, number: 1, title: "Episode", airDate: now, overview: "", runtimeMinutes: nil)
        try store.setEpisodeWatched(true, episode: ep, show: show, now: now)
        try store.setCollectionMembership(true, collection: a, media: value)
        try store.setCollectionMembership(true, collection: b, media: value)
        let before = try store.capturePersonalBackup(at: now)
        try store.deleteCollection(a)
        let after = try store.capturePersonalBackup(at: now)
        XCTAssertEqual(before.library, after.library)
        XCTAssertEqual(before.reviews, after.reviews); XCTAssertEqual(before.viewings, after.viewings)
        XCTAssertEqual(before.episodeProgress, after.episodeProgress)
        XCTAssertEqual(store.members(of: b).count, 1); XCTAssertTrue(store.members(of: a).isEmpty)
        XCTAssertEqual(store.entry(for: id)?.status, "watched")
    }

    @MainActor func testRemovalOfLibraryEntryKeepsCollectionReferenceAndPlaceholder() async throws {
        let store = try makeStore(), id = try store.saveCollection(name: "References")
        let value = media(1), identity = SearchItem(value).id
        try store.setCollectionMembership(true, collection: id, media: value)
        try store.remove(identity)
        XCTAssertEqual(store.members(of: id).first?.mediaID, identity)
        let saved = try XCTUnwrap(store.offlineMedia(for: identity))
        XCTAssertEqual(SearchItem(saved).id, identity)
        let model = SearchModel(service: nil).detailModel(for: MediaDestination(id: identity, title: SearchItem(saved).title, year: nil), savedMedia: saved)
        await model.load(store: store)
        XCTAssertEqual(model.snapshot.map { SearchItem($0.media).id }, identity)
        XCTAssertNil(store.entry(for: identity)) // Routing must not recreate status/rating/favorite data.
    }

    @MainActor func testFailedMainRemovalPreservesCollectionsAndLegacyTextThenRetryImportsOnce() throws {
        var fail = false
        let store = LibraryStore(container: try PersistenceController.makeContainer(inMemory: true), save: { context in
            if fail { throw LibraryStoreError.saveFailed }; try context.save()
        })
        let value = media(1), identity = SearchItem(value).id
        let list = try store.saveCollection(name: "Keep reference")
        try store.setCollectionMembership(true, collection: list, media: value)
        try store.setPersonalRating(PersonalRating(halfStarUnits: 9), media: value)
        try store.writeTransaction { _ in store.entry(for: identity)?.review = "Legacy private note" }
        let before = try store.capturePersonalBackup(at: now), membership = store.members(of: list).map(\.id)
        fail = true
        XCTAssertThrowsError(try store.remove(identity))
        XCTAssertEqual(try store.capturePersonalBackup(at: now).canonical(), before.canonical())
        XCTAssertEqual(store.members(of: list).map(\.id), membership)
        fail = false
        try store.remove(identity); try store.remove(identity)
        XCTAssertNil(store.entry(for: identity))
        XCTAssertEqual(store.reviews(for: identity).map(\.text), ["Legacy private note"])
        XCTAssertEqual(store.members(of: list).map(\.id), membership)
        XCTAssertNotNil(store.offlineMedia(for: identity))
    }

    @MainActor func testCollectionSaveFailureRollsBackNameMembershipAndOrder() throws {
        var fail = false
        let store = LibraryStore(container: try PersistenceController.makeContainer(inMemory: true), save: { context in
            if fail { throw LibraryStoreError.saveFailed }; try context.save()
        })
        let id = try store.saveCollection(name: "Original")
        try store.setCollectionMembership(true, collection: id, media: media(1))
        try store.setCollectionMembership(true, collection: id, media: media(2))
        let order = store.members(of: id).map(\.id)
        fail = true
        XCTAssertThrowsError(try store.saveCollection(id: id, name: "Changed"))
        XCTAssertEqual(store.collections.first?.name, "Original")
        XCTAssertThrowsError(try store.reorderCollection(id, memberships: Array(order.reversed())))
        XCTAssertEqual(store.members(of: id).map(\.id), order)
        XCTAssertThrowsError(try store.setCollectionMembership(true, collection: id, media: media(3)))
        XCTAssertEqual(store.entries.count, 2); XCTAssertEqual(store.members(of: id).count, 2)
        XCTAssertThrowsError(try store.deleteCollection(id))
        XCTAssertEqual(store.collections.count, 1)
    }

    @MainActor func testOfflineCollectionsAndOrderSurviveDiskReopen() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Collections.store")
        var collection = UUID(), order: [UUID] = []
        try autoreleasepool {
            let store = LibraryStore(container: try PersistenceController.makeContainer(at: url))
            collection = try store.saveCollection(name: "Offline")
            for n in 1...3 { try store.setCollectionMembership(true, collection: collection, media: media(n)) }
            order = Array(store.members(of: collection).map(\.id).reversed())
            try store.reorderCollection(collection, memberships: order)
        }
        let store = LibraryStore(container: try PersistenceController.makeContainer(at: url))
        XCTAssertEqual(store.collections.first?.id, collection)
        XCTAssertEqual(store.members(of: collection).map(\.id), order)
        XCTAssertEqual(store.members(of: collection).map(\.position), [0, 1, 2])
        XCTAssertNil(store.loadError)
    }

    @MainActor func testExpiredMetadataNeverDeletesMembershipOrRenewsItsReceipt() throws {
        let store = try makeStore(), owner = try store.saveCollection(name: "Personal references", now: now)
        let movie = Movie(id: "tmdb:42", title: "Temporary provider title", metadataRetrievedAt: now)
        try store.setCollectionMembership(true, collection: owner, media: .movie(movie), now: now)
        let membership = store.members(of: owner).first?.id
        try store.maintainMetadata(at: now.addingTimeInterval(MetadataPolicy.retention))
        XCTAssertEqual(store.members(of: owner).first?.id, membership)
        XCTAssertEqual(store.members(of: owner).first?.addedAt, now)
        XCTAssertEqual(store.collections.first?.name, "Personal references")
        XCTAssertEqual(SearchItem(store.offlineMedia(for: movie.id) ?? MetadataPolicy.placeholderMedia(movie.id)).title, MetadataPolicy.placeholder(movie.id))
    }

    @MainActor func testTiedPositionsAreDeterministicAndReportedNotSilentlyRepaired() throws {
        let container = try PersistenceController.makeContainer(inMemory: true), collection = UUID()
        let context = container.mainContext
        context.insert(StoredCollection(id: collection, name: "Ties", createdAt: now, updatedAt: now))
        let ids = [MigrationFixtures.uuid(1), MigrationFixtures.uuid(2)]
        for n in [1, 0] { context.insert(StoredCollectionMembership(id: ids[n], collectionID: collection, mediaID: SearchItem(media(n)).id, position: 0, addedAt: now)) }
        try context.save()
        let store = LibraryStore(container: container)
        XCTAssertEqual(store.members(of: collection).map(\.id), ids)
        XCTAssertNotNil(store.loadError)
    }
}
