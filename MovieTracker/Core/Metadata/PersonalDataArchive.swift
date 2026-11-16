import Foundation
import SwiftData

/// Recovery data only: no provider titles, JSON snapshots, artwork, synopsis, cast or release dates.
struct PersonalDataArchive: Codable {
    struct Library: Codable {
        let id: UUID; let kind: String; let value: String; let status: String; let favorite: Bool
        let rating: Double?; let units: Int?; let ratedAt: Date?; let review: String?; let added: Date; let updated: Date
    }
    struct Review: Codable {
        let id: UUID; let kind: String; let value: String; let text: String
        let created: Date; let edited: Date; let event: UUID?; let imported: Bool
    }
    struct Viewing: Codable {
        let id: UUID; let kind: String; let value: String; let watched: Date?; let recorded: Date; let updated: Date
    }
    struct Progress: Codable {
        let id: UUID; let series: String; let episode: String; let seasonAnchor: Int; let watched: Bool; let marked: Date?
    }
    struct SeasonAnchor: Codable { let id: UUID; let series: String; let number: Int }
    private struct SeasonKey: Hashable { let series: String; let number: Int }
    var format = 2
    let library: [Library]; let reviews: [Review]; let viewings: [Viewing]; let progress: [Progress]
    var seasons: [SeasonAnchor] = []
    var collections: [PersonalBackup.Collection]? = nil
    var collectionMemberships: [PersonalBackup.Membership]? = nil

    @MainActor static func capture(_ context: ModelContext) throws -> Self {
        let flags = try context.fetch(FetchDescriptor<StoredEpisodeProgress>())
        let keys = Set(flags.map { SeasonKey(series: $0.seriesValue, number: $0.seasonNumber) })
        let anchors = try context.fetch(FetchDescriptor<StoredTVSeason>()).filter { keys.contains(SeasonKey(series: $0.seriesValue, number: $0.number)) }
            .map { SeasonAnchor(id: $0.id, series: $0.seriesValue, number: $0.number) }
        return Self(library: try context.fetch(FetchDescriptor<StoredLibraryEntry>()).map {
            Library(id: $0.id, kind: $0.mediaKind, value: $0.mediaValue, status: $0.status, favorite: $0.isFavorite,
                rating: $0.rating, units: $0.ratingHalfStarUnits, ratedAt: $0.ratingUpdatedAt, review: $0.review, added: $0.addedAt, updated: $0.updatedAt)
        }, reviews: try context.fetch(FetchDescriptor<StoredPersonalReview>()).map {
            Review(id: $0.id, kind: $0.mediaKind, value: $0.mediaValue, text: $0.text, created: $0.createdAt, edited: $0.editedAt, event: $0.viewingEventID, imported: $0.isLegacyImport)
        }, viewings: try context.fetch(FetchDescriptor<StoredViewingEvent>()).map {
            Viewing(id: $0.id, kind: $0.mediaKind, value: $0.mediaValue, watched: $0.watchedDate, recorded: $0.recordedAt, updated: $0.updatedAt)
        }, progress: flags.map {
            Progress(id: $0.id, series: $0.seriesValue, episode: $0.episodeValue, seasonAnchor: $0.seasonNumber, watched: $0.isWatched, marked: $0.watchedAt)
        }, seasons: anchors,
        collections: try context.fetch(FetchDescriptor<StoredCollection>()).map { PersonalBackup.Collection(id: $0.id, name: $0.name, createdAt: $0.createdAt, updatedAt: $0.updatedAt) },
        collectionMemberships: try context.fetch(FetchDescriptor<StoredCollectionMembership>()).map {
            guard let id = $0.mediaID else { throw ArchiveError.conflictingIdentity }
            return PersonalBackup.Membership(id: $0.id, collectionID: $0.collectionID, mediaID: id, position: $0.position, addedAt: $0.addedAt)
        })
    }
    func writeVerified(to url: URL) throws {
        try validateIdentities()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        let bytes = try encoder.encode(self)
        try bytes.write(to: url, options: .atomic)
        guard try Data(contentsOf: url) == bytes else { throw ArchiveError.verification }
        _ = try Self.read(url)
    }
    static func read(_ url: URL) throws -> Self {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        let result = try decoder.decode(Self.self, from: Data(contentsOf: url))
        guard result.format == 1 || result.format == 2 else { throw ArchiveError.verification }
        try result.validateIdentities(); return result
    }
    private func validateIdentities() throws {
        let groups = [library.map(\.id), reviews.map(\.id), viewings.map(\.id), progress.map(\.id), seasons.map(\.id)]
        if format == 2 && (collections == nil || collectionMemberships == nil) { throw ArchiveError.verification }
        var portable = PersonalBackup(exportedAt: Date(timeIntervalSinceReferenceDate: 0), applicationVersion: nil)
        portable.collections = collections ?? []; portable.collectionMemberships = collectionMemberships ?? []
        if format == 1 && (!portable.collections.isEmpty || !portable.collectionMemberships.isEmpty) { throw ArchiveError.verification }
        try portable.validate()
        guard groups.allSatisfy({ Set($0).count == $0.count }) else { throw ArchiveError.conflictingIdentity }
    }
    /// Explicit recovery primitive for an EMPTY destination only; never called automatically by the app.
    @MainActor func restore(into context: ModelContext) throws {
        try validateIdentities()
        guard try context.fetchCount(FetchDescriptor<StoredLibraryEntry>()) == 0,
              try context.fetchCount(FetchDescriptor<StoredPersonalReview>()) == 0,
              try context.fetchCount(FetchDescriptor<StoredViewingEvent>()) == 0,
              try context.fetchCount(FetchDescriptor<StoredEpisodeProgress>()) == 0,
              try context.fetchCount(FetchDescriptor<StoredTVSeason>()) == 0,
              try context.fetchCount(FetchDescriptor<StoredMetadataState>()) == 0,
              try context.fetchCount(FetchDescriptor<StoredCollection>()) == 0,
              try context.fetchCount(FetchDescriptor<StoredCollectionMembership>()) == 0 else { throw ArchiveError.destinationNotEmpty }
        func identity(_ kind: String, _ value: String) -> MediaID { MediaID(kind: MediaID.Kind(rawValue: kind) ?? .movie, value: value) }
        for row in collections ?? [] {
            context.insert(StoredCollection(id: row.id, name: row.name, createdAt: row.createdAt, updatedAt: row.updatedAt))
        }
        for row in collectionMemberships ?? [] {
            context.insert(StoredCollectionMembership(id: row.id, collectionID: row.collectionID, mediaID: row.mediaID, position: row.position, addedAt: row.addedAt))
        }
        for source in library {
            let row = StoredLibraryEntry(entry: UserLibraryEntry(id: source.id, mediaID: identity(source.kind, source.value), status: nil))
            row.mediaKind = source.kind; row.status = source.status; row.isFavorite = source.favorite
            row.rating = source.rating; row.ratingHalfStarUnits = source.units; row.ratingUpdatedAt = source.ratedAt
            row.review = source.review; row.addedAt = source.added; row.updatedAt = source.updated; context.insert(row)
        }
        for source in viewings {
            let row = try StoredViewingEvent(id: source.id, media: MetadataPolicy.placeholderMedia(identity(source.kind, source.value)), watchedDate: source.watched, recordedAt: source.recorded)
            row.mediaKind = source.kind; row.updatedAt = source.updated; row.snapshotData = nil; context.insert(row)
        }
        for source in reviews {
            let row = try StoredPersonalReview(id: source.id, media: MetadataPolicy.placeholderMedia(identity(source.kind, source.value)), text: source.text, createdAt: source.created, viewingEventID: source.event, isLegacyImport: source.imported)
            row.mediaKind = source.kind; row.editedAt = source.edited; row.snapshotData = nil; context.insert(row)
        }
        var anchors = seasons
        var keys = Set(anchors.map { SeasonKey(series: $0.series, number: $0.number) })
        for source in progress where keys.insert(SeasonKey(series: source.series, number: source.seasonAnchor)).inserted {
            anchors.append(SeasonAnchor(id: UUID(), series: source.series, number: source.seasonAnchor))
        }
        for anchor in anchors {
            let id = MediaID(kind: .tvShow, value: anchor.series)
            let row = try StoredTVSeason(show: TVShow(id: id.value, title: MetadataPolicy.placeholder(id)),
                summary: TVSeasonSummary(number: anchor.number, providerID: nil, name: "Season metadata unavailable", episodeCount: nil))
            row.id = anchor.id; row.seriesData = nil; row.isListed = false; context.insert(row)
        }
        for source in progress {
            let episode = TVEpisode(id: EpisodeID(seriesID: MediaID(kind: .tvShow, value: source.series), providerValue: source.episode), seasonNumber: source.seasonAnchor,
                number: 0, title: "Episode metadata unavailable", airDate: nil, overview: "", runtimeMinutes: nil)
            let row = try StoredEpisodeProgress(episode: episode, watched: source.watched, now: source.marked ?? Date(timeIntervalSince1970: 0))
            row.id = source.id; row.watchedAt = source.marked; context.insert(row)
        }
        // Caller controls explicit save/rollback and verifies IDs/content before any owner-authorized recovery.
    }
    enum ArchiveError: Error { case verification, destinationNotEmpty, conflictingIdentity }
}

@MainActor
enum MetadataArchiveMaintenance {
    /// Convert known raw snapshots only after a verified personal recovery archive exists.
    /// Unknown/corrupt files are retained; the returned failure count blocks provider activation.
    static func convertBackups(beside store: URL) -> Int {
        let files = FileManager.default
        let root = store.deletingLastPathComponent().appendingPathComponent("StoreSafetyBackups", isDirectory: true)
        // Never follow a substituted managed root into another directory while converting/deleting backups.
        guard files.fileExists(atPath: root.path) || (try? files.destinationOfSymbolicLink(atPath: root.path)) != nil else { return 0 }
        do { try requireDirectory(root) } catch { return 1 }
        guard let directories = try? files.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return 1 }
        var failed = 0
        for directory in directories {
            do {
                try requireDirectory(directory)
                let contents = try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                let raw = contents.filter { $0.lastPathComponent == store.lastPathComponent || $0.pathExtension == "store" }
                let archive = directory.appendingPathComponent("PersonalData.json")
                try requirePlainFileIfPresent(archive)
                try requirePlainFileIfPresent(directory.appendingPathComponent("COMPLETE"))
                if raw.isEmpty {
                    if contents.contains(where: { $0.lastPathComponent.hasSuffix("-wal") || $0.lastPathComponent.hasSuffix("-shm") }) { failed += 1; continue }
                    if files.fileExists(atPath: archive.path) {
                        // A marker or filename alone is not evidence of a supported recovery archive.
                        _ = try PersonalDataArchive.read(archive)
                    } else if !contents.isEmpty { failed += 1 }
                    continue
                }
                guard raw.count == 1, let source = raw.first else { failed += 1; continue }
                for path in [source, URL(fileURLWithPath: source.path + "-wal"), URL(fileURLWithPath: source.path + "-shm")] {
                    try requirePlainFileIfPresent(path)
                }
                // Always capture the still-present raw store; never overwrite it using a potentially stale JSON file.
                let snapshot = try autoreleasepool {
                    try StoreSchemaRecognition.validate(source, supported: LibraryMigrationPlan.schemas)
                    let schema = Schema(versionedSchema: LibrarySchemaV3.self)
                    let container = try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self,
                        configurations: [ModelConfiguration(schema: schema, url: source, cloudKitDatabase: .none)])
                    return try PersonalDataArchive.capture(container.mainContext)
                }
                try snapshot.writeVerified(to: archive)
                for path in [source, URL(fileURLWithPath: source.path + "-wal"), URL(fileURLWithPath: source.path + "-shm")] where files.fileExists(atPath: path.path) {
                    try files.removeItem(at: path)
                }
                try Data("Verified personal-data-only recovery archive, format 2.\n".utf8).write(to: directory.appendingPathComponent("COMPLETE"), options: .atomic)
            } catch { failed += 1 } // No raw-store/content/error-body logging. Keep source bytes on failure.
        }
        return failed
    }
    private enum PathError: Error { case unsafeManagedPath }
    private static func requireDirectory(_ url: URL) throws {
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) == nil else { throw PathError.unsafeManagedPath }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw PathError.unsafeManagedPath }
    }
    private static func requirePlainFileIfPresent(_ url: URL) throws {
        let files = FileManager.default
        // fileExists follows links and returns false for dangling links; reject those too.
        guard (try? files.destinationOfSymbolicLink(atPath: url.path)) == nil else { throw PathError.unsafeManagedPath }
        guard files.fileExists(atPath: url.path) else { return }
        let attributes = try files.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw PathError.unsafeManagedPath }
    }
}
