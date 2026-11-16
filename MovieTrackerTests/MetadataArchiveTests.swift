import SwiftData
import XCTest
@testable import MovieTracker

final class MetadataArchiveTests: XCTestCase {
    @MainActor func testCorruptArchiveOnlyFolderRemainsBlockedAndPreserved() throws { try verifyArchiveOnly("corrupt") }
    @MainActor func testUnsupportedArchiveOnlyFolderRemainsBlockedAndPreserved() throws { try verifyArchiveOnly("future") }
    @MainActor func testSupportedArchiveOnlyFolderIsRevalidatedWithoutRewriting() throws { try verifyArchiveOnly("valid") }

    @MainActor private func verifyArchiveOnly(_ mode: String) throws {
        let files = FileManager.default, directory = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let backup = directory.appendingPathComponent("StoreSafetyBackups").appendingPathComponent(UUID().uuidString)
        try files.createDirectory(at: backup, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: directory) }
        let archive = backup.appendingPathComponent("PersonalData.json")
        let container = try PersistenceController.makeContainer(inMemory: true)
        try PersonalDataArchive.capture(container.mainContext).writeVerified(to: archive)
        if mode == "corrupt" { try Data("unreadable recovery data".utf8).write(to: archive) }
        if mode == "future" {
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: archive)) as? [String: Any])
            json["format"] = 999
            try JSONSerialization.data(withJSONObject: json).write(to: archive)
        }
        let before = try Data(contentsOf: archive)
        for _ in 0..<2 {
            XCTAssertEqual(MetadataArchiveMaintenance.convertBackups(beside: directory.appendingPathComponent("Library.store")), mode == "valid" ? 0 : 1)
            XCTAssertEqual(try Data(contentsOf: archive), before)
        }
        XCTAssertFalse(files.fileExists(atPath: directory.appendingPathComponent("Library.store").path))
    }

    @MainActor func testArchiveConversionRejectsLinkedRootWithoutTouchingTarget() throws { try verifyLinkedBackup("root") }
    @MainActor func testArchiveConversionRejectsLinkedDirectoryWithoutTouchingTarget() throws { try verifyLinkedBackup("directory") }
    @MainActor func testArchiveConversionRejectsLinkedStoreWithoutTouchingTarget() throws { try verifyLinkedBackup("store") }
    @MainActor func testArchiveConversionRejectsLinkedOutputWithoutTouchingTarget() throws { try verifyLinkedBackup("output") }

    @MainActor private func verifyLinkedBackup(_ kind: String) throws {
        let files = FileManager.default
        let directory = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: directory) }
        let source = directory.appendingPathComponent("Library.store")
        let store = try BackupFixtures.store(at: source)
        let media = MediaSearchResult.movie(Movie(id: "fixture:private", title: "Provider title"))
        try store.saveReview(id: UUID(), media: media, text: "Private content must be preserved")
        let backup = try StoreSafetyBackup.create(for: source)
        let root = backup.deletingLastPathComponent()
        let external = directory.appendingPathComponent("OutsideManagedBackups", isDirectory: kind != "store" && kind != "output")
        var raw = backup.appendingPathComponent(source.lastPathComponent)
        switch kind {
        case "root":
            try files.moveItem(at: root, to: external)
            try files.createSymbolicLink(at: root, withDestinationURL: external)
            raw = external.appendingPathComponent(backup.lastPathComponent).appendingPathComponent(source.lastPathComponent)
        case "directory":
            try files.moveItem(at: backup, to: external)
            try files.createSymbolicLink(at: backup, withDestinationURL: external)
            raw = external.appendingPathComponent(source.lastPathComponent)
        case "store":
            try files.moveItem(at: raw, to: external)
            try files.createSymbolicLink(at: raw, withDestinationURL: external)
            raw = external
        default:
            try Data("Do not overwrite".utf8).write(to: external)
            try files.createSymbolicLink(at: backup.appendingPathComponent("PersonalData.json"), withDestinationURL: external)
        }
        let before = try Data(contentsOf: raw)
        if kind == "root" {
            let original = try files.contentsOfDirectory(atPath: external.path).sorted()
            XCTAssertThrowsError(try StoreSafetyBackup.create(for: source))
            XCTAssertEqual(try files.contentsOfDirectory(atPath: external.path).sorted(), original)
        }
        XCTAssertEqual(MetadataArchiveMaintenance.convertBackups(beside: source), 1)
        XCTAssertEqual(try Data(contentsOf: raw), before)
        if kind != "output" { XCTAssertFalse(files.fileExists(atPath: raw.deletingLastPathComponent().appendingPathComponent("PersonalData.json").path)) }
        if kind == "output" { XCTAssertEqual(try Data(contentsOf: external), Data("Do not overwrite".utf8)) }
        XCTAssertEqual(store.personalReviews.first?.text, "Private content must be preserved")
    }

    @MainActor func testPersonalArchiveExcludesMetadataAndRestoresExactUserRecords() throws {
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let container = try PersistenceController.makeContainer(at: directory.appendingPathComponent("Source.store"))
        let store = LibraryStore(container: container)
        let media = MediaSearchResult.movie(Movie(id: "tmdb:1", title: "Provider-only title", overview: "Provider-only synopsis", posterReference: "/provider.jpg", metadataRetrievedAt: .now))
        try store.setStatus(.watched, media: media)
        try store.setPersonalRating(PersonalRating(halfStarUnits: 7), media: media)
        try store.setFavorite(true, media: media)
        let event = UUID(), review = UUID()
        try store.saveViewingEvent(id: event, media: media, watchedDate: nil)
        try store.saveReview(id: review, media: media, text: "Private text to preserve", eventID: event)
        let show = TVShow(id: "tmdb:2", title: "Provider-only series")
        let episode = TVEpisode(id: EpisodeID(seriesID: show.id, providerValue: "tmdb:episode:2"), seasonNumber: 1, number: 2,
            title: "Provider-only episode", airDate: Date(timeIntervalSince1970: 1_577_836_800), overview: "Provider-only synopsis", runtimeMinutes: 40)
        try store.setEpisodeWatched(true, episode: episode, show: show)
        let flagID = store.episodeProgress.first?.id, marked = store.episodeProgress.first?.watchedAt
        let archived = try PersonalDataArchive.capture(container.mainContext)
        let url = directory.appendingPathComponent("PersonalData.json")
        try archived.writeVerified(to: url)
        let bytes = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(bytes.contains("Provider-only")); XCTAssertFalse(bytes.contains("/provider.jpg"))
        let restored = try PersistenceController.makeContainer(at: directory.appendingPathComponent("Restored.store"))
        let decoded = try PersonalDataArchive.read(url)
        try decoded.restore(into: restored.mainContext); try restored.mainContext.save()
        let copy = LibraryStore(container: restored)
        XCTAssertEqual(copy.entry(for: SearchItem(media).id)?.id, store.entry(for: SearchItem(media).id)?.id)
        XCTAssertEqual(copy.entry(for: SearchItem(media).id)?.ratingHalfStarUnits, 7); XCTAssertTrue(copy.entry(for: SearchItem(media).id)?.isFavorite == true)
        XCTAssertEqual(copy.entry(for: SearchItem(media).id)?.status, "watched"); XCTAssertNil(copy.entry(for: SearchItem(media).id)?.snapshotData)
        XCTAssertEqual(copy.personalReviews.first?.id, review); XCTAssertEqual(copy.personalReviews.first?.text, "Private text to preserve")
        XCTAssertEqual(copy.personalReviews.first?.viewingEventID, event); XCTAssertEqual(copy.viewingEvents.first?.id, event)
        XCTAssertEqual(copy.episodeProgress.first?.id, flagID); XCTAssertEqual(copy.episodeProgress.first?.watchedAt, marked)
        XCTAssertTrue(copy.isWatched(episode.id)); XCTAssertEqual(copy.tvSeasons.count, 1)
        XCTAssertNil(copy.tvSeasons.first?.seriesData); XCTAssertNil(copy.tvSeasons.first?.episodesData)
        XCTAssertThrowsError(try decoded.restore(into: restored.mainContext))
    }
    @MainActor func testManagedRawBackupConvertsOnlyAfterVerifiedPersonalArchive() throws {
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("Source.store")
        let container = try PersistenceController.makeContainer(at: source), store = LibraryStore(container: container)
        try store.saveReview(id: UUID(), media: .movie(Movie(id: "tmdb:1", title: "Provider title")), text: "Keep backup user text")
        let backup = try StoreSafetyBackup.create(for: source)
        XCTAssertEqual(MetadataArchiveMaintenance.convertBackups(beside: source), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.appendingPathComponent(source.lastPathComponent).path))
        let archive = try PersonalDataArchive.read(backup.appendingPathComponent("PersonalData.json"))
        XCTAssertEqual(archive.reviews.first?.text, "Keep backup user text")
        XCTAssertEqual(MetadataArchiveMaintenance.convertBackups(beside: source), 0)
        XCTAssertEqual(store.personalReviews.first?.text, "Keep backup user text")
    }
    @MainActor func testUnreadableArchiveIsPreservedForRecoveryAndReported() throws {
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("Source.store")
        let backup = directory.appendingPathComponent("StoreSafetyBackups/Unknown", isDirectory: true)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        let file = backup.appendingPathComponent("Source.store"), bytes = Data("Do not delete unknown user records".utf8)
        try bytes.write(to: file)
        XCTAssertEqual(MetadataArchiveMaintenance.convertBackups(beside: source), 1)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.appendingPathComponent("PersonalData.json").path))
    }
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); return directory
    }
}
