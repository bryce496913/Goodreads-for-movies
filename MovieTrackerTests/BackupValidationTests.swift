import XCTest
@testable import MovieTracker

final class BackupValidationTests: XCTestCase {
    func testMalformedJSONAndForeignFormatAreRejected() {
        for bytes in [Data("{".utf8), Data("null".utf8), Data(#"{"format":"foreign","version":1}"#.utf8)] {
            XCTAssertThrowsError(try BackupCodec.decode(bytes))
        }
    }
    func testUnsupportedVersionIsReportedBeforeReadingVersionSpecificRecords() {
        let bytes = Data(#"{"format":"MovieTracker.personal-backup","version":99}"#.utf8)
        XCTAssertThrowsError(try BackupCodec.decode(bytes)) { XCTAssertEqual($0 as? BackupError, .unsupportedVersion(99)) }
    }
    @MainActor func testMissingRequiredArraysAndIdentifiersAreRejected() throws {
        let backup = try BackupFixtures.populated().capturePersonalBackup(at: BackupFixtures.now)
        let bytes = try BackupCodec.encode(backup)
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        root.removeValue(forKey: "library")
        XCTAssertThrowsError(try BackupCodec.decode(JSONSerialization.data(withJSONObject: root)))
        root = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var rows = try XCTUnwrap(root["library"] as? [[String: Any]])
        rows[0].removeValue(forKey: "mediaID"); root["library"] = rows
        XCTAssertThrowsError(try BackupCodec.decode(JSONSerialization.data(withJSONObject: root)))
    }
    @MainActor func testDuplicateUUIDAndLogicalTitleAreRejectedBeforeMutation() throws {
        var backup = try BackupFixtures.populated().capturePersonalBackup(at: BackupFixtures.now)
        backup.library.append(backup.library[0])
        XCTAssertThrowsError(try backup.validate())
        backup.library.removeLast()
        backup.library.append(BackupFixtures.library(backup.library[0], id: UUID()))
        XCTAssertThrowsError(try backup.validate())
    }
    @MainActor func testDuplicateEpisodeIdentityWithDifferentUUIDIsRejected() throws {
        var backup = try BackupFixtures.populated().capturePersonalBackup(at: BackupFixtures.now)
        let row = backup.episodeProgress[0]
        backup.episodeProgress.append(.init(id: UUID(), episodeID: row.episodeID, seasonNumber: row.seasonNumber, isWatched: false, watchedAt: nil))
        XCTAssertThrowsError(try backup.validate())
    }
    @MainActor func testInvalidRatingsStatusesAndEmptyIdentifiersAreRejected() throws {
        let original = try BackupFixtures.populated().capturePersonalBackup(at: BackupFixtures.now)
        for units in [0, 11, -1] {
            var invalid = original
            invalid.library = [BackupFixtures.library(original.library[0], units: units)]
            XCTAssertThrowsError(try BackupCodec.encode(invalid))
        }
        let movie = try XCTUnwrap(original.library.first { $0.mediaID.kind == .movie })
        var invalid = original
        invalid.library = [BackupFixtures.library(movie, status: .watching)]
        XCTAssertThrowsError(try invalid.validate())
        invalid.library = [BackupFixtures.library(movie, mediaID: MediaID(kind: .movie, value: "   "))]
        XCTAssertThrowsError(try invalid.validate())
    }
    @MainActor func testDanglingCrossMediaAndDuplicateReviewLinksAreRejected() throws {
        let original = try BackupFixtures.populated().capturePersonalBackup(at: BackupFixtures.now), row = try XCTUnwrap(original.reviews.first)
        for media in [row.mediaID, BackupFixtures.showID] {
            var invalid = original
            invalid.reviews = [.init(id: row.id, mediaID: media, text: row.text, createdAt: row.createdAt, editedAt: row.editedAt,
                viewingEventID: media == row.mediaID ? UUID() : row.viewingEventID, isLegacyImport: false)]
            XCTAssertThrowsError(try invalid.validate())
        }
        var invalid = original
        invalid.reviews.append(.init(id: UUID(), mediaID: row.mediaID, text: "Another", createdAt: row.createdAt,
            editedAt: row.editedAt, viewingEventID: row.viewingEventID, isLegacyImport: false))
        XCTAssertThrowsError(try invalid.validate())
    }
    @MainActor func testBlankReviewMissingSeasonAndInvalidTimestampAreRejected() throws {
        let original = try BackupFixtures.populated().capturePersonalBackup(at: BackupFixtures.now), row = try XCTUnwrap(original.reviews.first)
        var invalid = original
        invalid.reviews = [.init(id: row.id, mediaID: row.mediaID, text: " \n", createdAt: row.createdAt, editedAt: row.editedAt, viewingEventID: nil, isLegacyImport: false)]
        XCTAssertThrowsError(try invalid.validate())
        invalid = original; invalid.seasonAnchors = []
        XCTAssertThrowsError(try invalid.validate())
        let infinite = PersonalBackup(exportedAt: Date(timeIntervalSinceReferenceDate: .infinity), applicationVersion: nil)
        XCTAssertThrowsError(try infinite.validate())
    }
    func testSizeLimitAndMissingFileUseSanitizedErrors() {
        XCTAssertThrowsError(try BackupCodec.decode(Data(repeating: 0, count: BackupCodec.maximumBytes + 1))) {
            XCTAssertEqual($0 as? BackupError, .tooLarge)
        }
        XCTAssertThrowsError(try BackupCodec.read(FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))) {
            XCTAssertEqual($0 as? BackupError, .readFailed)
        }
    }
    @MainActor func testCanceledEncodingDoesNotProduceACompleteExport() async {
        let backup = PersonalBackup(exportedAt: BackupFixtures.now, applicationVersion: nil)
        let work = Task { try BackupCodec.encode(backup) }
        work.cancel()
        do { _ = try await work.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
    }
    @MainActor func testUnknownFieldsCannotImportProviderMetadataOrCredentials() throws {
        let backup = try BackupFixtures.populated().capturePersonalBackup(at: BackupFixtures.now)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: BackupCodec.encode(backup)) as? [String: Any])
        object["metadataCache"] = ["title": "DO_NOT_IMPORT", "credential": "NONSECRET_TEST_MARKER"]
        let decoded = try BackupCodec.decode(JSONSerialization.data(withJSONObject: object)), target = try BackupFixtures.store()
        try target.restorePersonalBackup(BackupFixtures.plan(decoded, into: target))
        XCTAssertNil(target.entries.first?.savedTitle); XCTAssertNil(target.entries.first?.snapshotData)
        XCTAssertFalse(String(decoding: try BackupCodec.encode(decoded), as: UTF8.self).contains("NONSECRET_TEST_MARKER"))
    }
    @MainActor func testInvalidImportModelNeverStagesOrMutatesData() async throws {
        let bytes = Data("malformed private input must not be logged".utf8), url = try BackupFixtures.tempFile(bytes)
        defer { try? FileManager.default.removeItem(at: url) }
        let target = try BackupFixtures.store(), model = DataBackupModel()
        await model.prepareImport(url, into: target)
        XCTAssertNil(model.preview); XCTAssertTrue(target.entries.isEmpty)
        XCTAssertFalse(model.message?.contains("private input") == true); XCTAssertFalse(model.isBusy)
    }
    @MainActor func testInvalidLegacyRatingBlocksExportInsteadOfDroppingPersonalData() async throws {
        let source = try BackupFixtures.populated()
        try source.writeTransaction { _ in source.entries.first?.ratingHalfStarUnits = 0 }
        let model = DataBackupModel()
        await model.prepareExport(from: source)
        XCTAssertNil(model.exportBytes); XCTAssertNotNil(model.message)
        XCTAssertEqual(source.entries.first?.ratingHalfStarUnits, 0)
    }
    @MainActor func testDocumentPickerCancellationHasNoFailureMessage() {
        let model = DataBackupModel(), canceled = NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.userCancelled.rawValue)
        model.fileSelectionFailed(canceled); XCTAssertNil(model.message)
        model.finishExport(.failure(canceled)); XCTAssertNil(model.message)
    }
}
