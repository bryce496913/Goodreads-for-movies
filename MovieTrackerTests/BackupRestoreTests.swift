import SwiftData
import XCTest
@testable import MovieTracker

final class BackupRestoreTests: XCTestCase {
    @MainActor func testEmptyExportAndRoundTrip() throws {
        let source = try BackupFixtures.store(), target = try BackupFixtures.store()
        let backup = try source.capturePersonalBackup(at: BackupFixtures.now)
        let bytes = try BackupCodec.encode(backup)
        XCTAssertEqual(try BackupCodec.decode(bytes), backup)
        let plan = try BackupFixtures.plan(backup, into: target)
        XCTAssertEqual(plan.counts.total, 0)
        try target.restorePersonalBackup(plan)
        XCTAssertTrue(target.entries.isEmpty)
    }
    @MainActor func testPopulatedRoundTripPreservesPersonalFieldsAndIdentities() throws {
        let source = try BackupFixtures.populated(), target = try BackupFixtures.store()
        let backup = try source.capturePersonalBackup(at: BackupFixtures.now, applicationVersion: "0.5.0")
        let decoded = try BackupCodec.decode(BackupCodec.encode(backup))
        try target.restorePersonalBackup(BackupFixtures.plan(decoded, into: target))
        XCTAssertEqual(try target.capturePersonalBackup(at: backup.exportedAt, applicationVersion: backup.applicationVersion).canonical(), backup.canonical())
        XCTAssertEqual(target.entries.count, 2); XCTAssertEqual(target.viewingEvents.count, 2)
        XCTAssertEqual(target.reviews(for: BackupFixtures.movieID).first?.viewingEventID, BackupFixtures.eventID)
        XCTAssertTrue(target.isWatched(BackupFixtures.episode.id))
        XCTAssertEqual(target.entry(for: BackupFixtures.movieID)?.ratingHalfStarUnits, 7)
    }
    @MainActor func testExportExcludesProviderBodiesCredentialsAndDeviceFields() throws {
        let source = try BackupFixtures.populated()
        let bytes = try BackupCodec.encode(source.capturePersonalBackup(at: BackupFixtures.now))
        let text = String(decoding: bytes, as: UTF8.self)
        for forbidden in ["PROVIDER_TITLE", "PROVIDER_SYNOPSIS", "PROVIDER_POSTER", "PROVIDER_TV", "PROVIDER_EPISODE", "PROVIDER_SEASON", "snapshotData", "Authorization", "readAccessToken", "deviceIdentifier"] {
            XCTAssertFalse(text.contains(forbidden))
        }
        XCTAssertTrue(text.contains("Retained legacy note")); XCTAssertTrue(text.contains("Second line."))
    }
    @MainActor func testEncodingIsDeterministicAcrossArrayOrderAndPreservesFractionalDates() throws {
        var first = try BackupFixtures.populated().capturePersonalBackup(at: BackupFixtures.now)
        let bytes = try BackupCodec.encode(first)
        first.library.reverse(); first.viewings.reverse(); first.reviews.reverse(); first.episodeProgress.reverse(); first.seasonAnchors.reverse()
        XCTAssertEqual(try BackupCodec.encode(first), bytes)
        XCTAssertEqual(try BackupCodec.decode(bytes).exportedAt, BackupFixtures.now)
        XCTAssertEqual(try BackupCodec.decode(bytes).reviews.first?.createdAt, BackupFixtures.now)
    }
    @MainActor func testRepeatedImportIsIdempotent() throws {
        let backup = try BackupFixtures.populated().capturePersonalBackup(at: BackupFixtures.now), target = try BackupFixtures.store()
        try target.restorePersonalBackup(BackupFixtures.plan(backup, into: target))
        let first = try target.capturePersonalBackup(at: BackupFixtures.now)
        let again = try BackupFixtures.plan(backup, into: target)
        XCTAssertEqual(again.counts.total, 0); XCTAssertTrue(again.conflicts.isEmpty)
        try target.restorePersonalBackup(again)
        XCTAssertEqual(try target.capturePersonalBackup(at: BackupFixtures.now).canonical(), first.canonical())
    }
    @MainActor func testMergeAddsMissingRecordsAndKeepsExistingTitles() throws {
        let source = try BackupFixtures.populated(), target = try BackupFixtures.store()
        try target.setStatus(.watchlist, media: .movie(Movie(id: BackupFixtures.movieID.value, title: "Local")))
        let localUUID = target.entry(for: BackupFixtures.movieID)?.id
        let backup = try source.capturePersonalBackup(at: BackupFixtures.now), plan = try BackupFixtures.plan(backup, into: target)
        XCTAssertEqual(plan.counts.library, 1); XCTAssertEqual(plan.counts.reviews, 1); XCTAssertEqual(plan.counts.viewings, 2)
        XCTAssertFalse(plan.conflicts.isEmpty)
        try target.restorePersonalBackup(plan)
        XCTAssertEqual(target.entries.count, 2); XCTAssertEqual(target.entry(for: BackupFixtures.movieID)?.id, localUUID)
        XCTAssertEqual(target.entry(for: BackupFixtures.movieID)?.status, "watchlist")
        XCTAssertNil(target.entry(for: BackupFixtures.movieID)?.ratingHalfStarUnits)
        XCTAssertEqual(target.reviews(for: BackupFixtures.movieID).first?.text, BackupFixtures.text)
    }
    @MainActor func testConflictingRatingsStatusesAndFavoritesAreKeptLocally() throws {
        let target = try BackupFixtures.populated(), original = try target.capturePersonalBackup(at: BackupFixtures.now)
        var incoming = original
        incoming.library = incoming.library.map { BackupFixtures.library($0) }
        let plan = try BackupFixtures.plan(incoming, into: target)
        XCTAssertEqual(plan.conflicts.count, 2)
        try target.restorePersonalBackup(plan)
        XCTAssertEqual(try target.capturePersonalBackup(at: BackupFixtures.now).canonical(), original.canonical())
    }
    @MainActor func testConflictingEpisodeWatchedStatesAndSeasonRemainLocal() throws {
        let target = try BackupFixtures.populated(), original = try target.capturePersonalBackup(at: BackupFixtures.now)
        var incoming = original
        incoming.episodeProgress = original.episodeProgress.map { .init(id: $0.id, episodeID: $0.episodeID, seasonNumber: $0.seasonNumber, isWatched: false, watchedAt: nil) }
        let plan = try BackupFixtures.plan(incoming, into: target)
        XCTAssertEqual(plan.conflicts.count, 1)
        try target.restorePersonalBackup(plan)
        XCTAssertTrue(target.isWatched(BackupFixtures.episode.id))
        XCTAssertEqual(target.episodeProgress.first?.watchedAt, BackupFixtures.now)
    }
    @MainActor func testExistingReviewTextAndEventDatesAreNeverOverwritten() throws {
        let target = try BackupFixtures.populated(), original = try target.capturePersonalBackup(at: BackupFixtures.now)
        var incoming = original
        incoming.reviews = original.reviews.map { .init(id: $0.id, mediaID: $0.mediaID, text: "Different incoming private text", createdAt: $0.createdAt, editedAt: $0.editedAt, viewingEventID: $0.viewingEventID, isLegacyImport: $0.isLegacyImport) }
        incoming.viewings = original.viewings.map { .init(id: $0.id, mediaID: $0.mediaID, watchedDate: nil, recordedAt: $0.recordedAt, updatedAt: $0.updatedAt) }
        let plan = try BackupFixtures.plan(incoming, into: target)
        XCTAssertFalse(plan.conflicts.joined().contains("Different incoming private text"))
        try target.restorePersonalBackup(plan)
        XCTAssertEqual(try target.capturePersonalBackup(at: BackupFixtures.now).canonical(), original.canonical())
    }
    @MainActor func testConflictingReviewEventLinkSkipsWholeIncomingReview() throws {
        let target = try BackupFixtures.populated()
        var incoming = try target.capturePersonalBackup(at: BackupFixtures.now)
        let old = incoming.reviews[0]
        incoming.reviews = [.init(id: UUID(), mediaID: old.mediaID, text: "Incoming linked review", createdAt: old.createdAt, editedAt: old.editedAt, viewingEventID: old.viewingEventID, isLegacyImport: false)]
        let plan = try BackupFixtures.plan(incoming, into: target)
        XCTAssertEqual(plan.counts.reviews, 0); XCTAssertEqual(plan.conflicts.count, 1)
        try target.restorePersonalBackup(plan)
        XCTAssertEqual(target.personalReviews.count, 1)
    }
    @MainActor func testSameNumericMovieAndTVIDsRemainSeparate() throws {
        let source = try BackupFixtures.populated(), target = try BackupFixtures.store()
        try target.restorePersonalBackup(BackupFixtures.plan(source.capturePersonalBackup(at: BackupFixtures.now), into: target))
        XCTAssertNotNil(target.entry(for: BackupFixtures.movieID)); XCTAssertNotNil(target.entry(for: BackupFixtures.showID))
        XCTAssertEqual(target.entry(for: BackupFixtures.movieID)?.status, "watched")
        XCTAssertEqual(target.entry(for: BackupFixtures.showID)?.status, "watching")
    }
    @MainActor func testFailedSaveRollsBackEveryPlannedInsertAndKeepsDiskState() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Backup.store")
        try autoreleasepool {
            let original = try BackupFixtures.store(at: url)
            try original.setPersonalRating(PersonalRating(halfStarUnits: 9), media: .movie(Movie(id: "local:1", title: "Local")))
        }
        let target = try BackupFixtures.store(at: url, failSave: true), before = try target.capturePersonalBackup(at: BackupFixtures.now)
        let backup = try BackupFixtures.populated().capturePersonalBackup(at: BackupFixtures.now)
        XCTAssertThrowsError(try target.restorePersonalBackup(BackupFixtures.plan(backup, into: target)))
        XCTAssertEqual(try target.capturePersonalBackup(at: BackupFixtures.now).canonical(), before.canonical())
        let reopened = try BackupFixtures.store(at: url)
        XCTAssertEqual(try reopened.capturePersonalBackup(at: BackupFixtures.now).canonical(), before.canonical())
        XCTAssertTrue(reopened.personalReviews.isEmpty); XCTAssertTrue(reopened.viewingEvents.isEmpty); XCTAssertTrue(reopened.episodeProgress.isEmpty)
    }
    @MainActor func testSuccessfulRestorePersistsAcrossDiskReopenWithoutMetadata() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Restore.store"), backup = try BackupFixtures.populated().capturePersonalBackup(at: BackupFixtures.now)
        try autoreleasepool {
            let target = try BackupFixtures.store(at: url)
            try target.restorePersonalBackup(BackupFixtures.plan(backup, into: target))
        }
        let reopened = try BackupFixtures.store(at: url)
        XCTAssertEqual(try reopened.capturePersonalBackup(at: BackupFixtures.now).canonical(), backup.canonical())
        XCTAssertNil(reopened.entries.first?.snapshotData); XCTAssertNil(reopened.entries.first?.savedTitle)
        XCTAssertNil(reopened.personalReviews.first?.snapshotData); XCTAssertNil(reopened.tvSeasons.first?.seriesData)
        XCTAssertEqual(reopened.episodeProgress.first?.savedEpisode?.number, 0)
        XCTAssertEqual(reopened.episodeProgress.first?.savedEpisode?.title, "Episode metadata unavailable")
    }
    @MainActor func testLibraryUUIDCollisionSkipsIncomingRowWithoutUpsert() throws {
        let target = try BackupFixtures.populated(), original = try target.capturePersonalBackup(at: BackupFixtures.now)
        let existing = original.library[0]
        var incoming = PersonalBackup(exportedAt: BackupFixtures.now, applicationVersion: nil)
        incoming.library = [BackupFixtures.library(existing, status: nil, id: existing.id, mediaID: MediaID(kind: .movie, value: "other:999"))]
        let plan = try BackupFixtures.plan(incoming, into: target)
        XCTAssertEqual(plan.counts.library, 0); XCTAssertEqual(plan.conflicts.count, 1)
        try target.restorePersonalBackup(plan)
        XCTAssertEqual(try target.capturePersonalBackup(at: BackupFixtures.now).canonical(), original.canonical())
    }
    @MainActor func testEventUUIDCollisionCannotAttachIncomingReviewToWrongTitle() throws {
        let target = try BackupFixtures.store()
        let other = MediaSearchResult.movie(Movie(id: "other:999", title: "Local"))
        try target.saveViewingEvent(id: BackupFixtures.eventID, media: other, watchedDate: nil, now: BackupFixtures.now)
        let incoming = try BackupFixtures.populated().capturePersonalBackup(at: BackupFixtures.now)
        let plan = try BackupFixtures.plan(incoming, into: target)
        XCTAssertEqual(plan.counts.reviews, 0)
        XCTAssertTrue(plan.conflicts.contains { $0.contains("association") })
        try target.restorePersonalBackup(plan)
        XCTAssertTrue(target.personalReviews.isEmpty)
        XCTAssertEqual(target.viewingEvents.first { $0.id == BackupFixtures.eventID }?.mediaID?.value, "other:999")
    }
    @MainActor func testSeasonUUIDCollisionSkipsDependentProgress() throws {
        let target = try BackupFixtures.store(), incoming = try BackupFixtures.populated().capturePersonalBackup(at: BackupFixtures.now)
        let anchor = try XCTUnwrap(incoming.seasonAnchors.first)
        let show = TVShow(id: "other:series", title: "Local", seasons: [.init(number: 9, providerID: nil, name: "Nine", episodeCount: nil)])
        try target.cacheSeasonCatalog(show: show)
        try target.writeTransaction { _ in target.tvSeasons.first?.id = anchor.id }
        let plan = try BackupFixtures.plan(incoming, into: target)
        XCTAssertEqual(plan.counts.progress, 0)
        XCTAssertTrue(plan.conflicts.contains { $0.contains("season UUID") })
        try target.restorePersonalBackup(plan)
        XCTAssertTrue(target.episodeProgress.isEmpty)
        XCTAssertEqual(target.tvSeasons.first?.seriesID, show.id)
    }
    @MainActor func testChangedRevisionRejectsPreviewBeforeAnyMutation() throws {
        let target = try BackupFixtures.store(), backup = try BackupFixtures.populated().capturePersonalBackup(at: BackupFixtures.now)
        let plan = try BackupFixtures.plan(backup, into: target)
        try target.setStatus(.watchlist, media: .movie(Movie(id: "local:1", title: "Local")))
        XCTAssertThrowsError(try target.restorePersonalBackup(plan)) { XCTAssertEqual($0 as? BackupError, .libraryChanged) }
        XCTAssertEqual(target.entries.count, 1); XCTAssertTrue(target.personalReviews.isEmpty)
    }
    @MainActor func testPreviewCancelDoesNotWriteAndExplicitConfirmationSaves() async throws {
        let backup = try BackupFixtures.populated().capturePersonalBackup(at: BackupFixtures.now)
        let url = try BackupFixtures.tempFile(BackupCodec.encode(backup)); defer { try? FileManager.default.removeItem(at: url) }
        let target = try BackupFixtures.store(), model = DataBackupModel()
        await model.prepareImport(url, into: target)
        XCTAssertNotNil(model.preview); XCTAssertTrue(target.entries.isEmpty)
        model.cancelPreview(); XCTAssertNil(model.preview); XCTAssertTrue(target.entries.isEmpty)
        await model.prepareImport(url, into: target); await model.confirmRestore(into: target)
        XCTAssertNil(model.preview); XCTAssertFalse(model.isBusy); XCTAssertEqual(target.entries.count, 2)
        XCTAssertTrue(model.message?.contains("Restore saved") == true)
    }
    @MainActor func testImportedLegacyNamespaceRemainsAccessibleWithoutProviderMetadata() async throws {
        let source = try BackupFixtures.populated(), target = try BackupFixtures.store()
        let row = try XCTUnwrap(source.capturePersonalBackup(at: BackupFixtures.now).library.first { $0.mediaID.kind == .movie })
        let id = MediaID(kind: .movie, value: "legacy-provider:72")
        var backup = PersonalBackup(exportedAt: BackupFixtures.now, applicationVersion: nil)
        backup.library = [BackupFixtures.library(row, status: nil, units: 6, mediaID: id)]
        try target.restorePersonalBackup(BackupFixtures.plan(backup, into: target))
        let search = SearchModel(service: nil)
        let detail = search.detailModel(for: MediaDestination(id: id, title: "Identifier", year: nil), savedMedia: target.offlineMedia(for: id))
        await detail.load(store: target)
        XCTAssertNotNil(detail.snapshot); XCTAssertEqual(detail.snapshot.map { SearchItem($0.media).id }, id)
        XCTAssertEqual(detail.availability, .unavailable)
        XCTAssertEqual(target.entry(for: id)?.ratingHalfStarUnits, 6)
    }
    @MainActor func testOfflineExportPreparationProducesCompleteDecodableBuffer() async throws {
        let source = try BackupFixtures.populated(), model = DataBackupModel()
        await model.prepareExport(from: source)
        let data = try XCTUnwrap(model.exportBytes)
        XCTAssertEqual(try BackupCodec.decode(data).library.count, 2)
        XCTAssertNil(model.message); XCTAssertFalse(model.isBusy)
    }
}
