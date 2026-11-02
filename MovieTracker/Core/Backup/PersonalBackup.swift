import Foundation

/// Public portable format, independent of SwiftData and the internal migration recovery archive.
struct PersonalBackup: Codable, Equatable, Sendable {
    struct Library: Codable, Equatable, Sendable {
        let id: UUID
        let mediaID: MediaID
        let status: LibraryStatus?
        let favorite: Bool
        let ratingHalfStarUnits: Int?
        let ratingUpdatedAt: Date?
        let legacyReview: String?
        let addedAt: Date
        let updatedAt: Date
    }
    struct Review: Codable, Equatable, Sendable {
        let id: UUID
        let mediaID: MediaID
        let text: String
        let createdAt: Date
        let editedAt: Date
        let viewingEventID: UUID?
        let isLegacyImport: Bool
    }
    struct Viewing: Codable, Equatable, Sendable {
        let id: UUID
        let mediaID: MediaID
        let watchedDate: Date?
        let recordedAt: Date
        let updatedAt: Date
    }
    struct Progress: Codable, Equatable, Sendable {
        let id: UUID
        let episodeID: EpisodeID
        let seasonNumber: Int
        let isWatched: Bool
        let watchedAt: Date?
    }
    struct SeasonAnchor: Codable, Equatable, Sendable {
        let id: UUID
        let seriesID: MediaID
        let number: Int
        var key: SeasonKey { SeasonKey(series: seriesID, number: number) }
    }
    struct SeasonKey: Hashable, Sendable { let series: MediaID; let number: Int }
    var format = "MovieTracker.personal-backup"
    var version = 1
    var dateEncoding = "secondsSince2001-01-01T00:00:00Z"
    let exportedAt: Date
    let applicationVersion: String?
    var library: [Library] = []
    var reviews: [Review] = []
    var viewings: [Viewing] = []
    var episodeProgress: [Progress] = []
    var seasonAnchors: [SeasonAnchor] = []

    func validate() throws {
        try Task.checkCancellation()
        guard format == "MovieTracker.personal-backup", dateEncoding == "secondsSince2001-01-01T00:00:00Z" else { throw BackupError.invalidFormat }
        guard version == 1 else { throw BackupError.unsupportedVersion(version) }
        guard library.count + reviews.count + viewings.count + episodeProgress.count + seasonAnchors.count <= 100_000 else { throw BackupError.tooLarge }
        func date(_ value: Date?) -> Bool { value?.timeIntervalSinceReferenceDate.isFinite ?? true }
        func identity(_ value: MediaID) -> Bool { !value.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.value.utf8.count <= 1_024 }
        func unique<T: Hashable>(_ values: [T]) -> Bool { Set(values).count == values.count }
        guard date(exportedAt), unique(library.map(\.id)), unique(library.map(\.mediaID)),
              unique(reviews.map(\.id)), unique(viewings.map(\.id)), unique(episodeProgress.map(\.id)),
              unique(episodeProgress.map(\.episodeID)), unique(seasonAnchors.map(\.id)), unique(seasonAnchors.map(\.key)) else { throw BackupError.invalidRecords }
        for row in library {
            try Task.checkCancellation()
            guard identity(row.mediaID), date(row.addedAt), date(row.updatedAt), date(row.ratingUpdatedAt),
                  row.status != .watching || row.mediaID.kind == .tvShow else { throw BackupError.invalidRecords }
            if let units = row.ratingHalfStarUnits { _ = try PersonalRating(halfStarUnits: units) }
        }
        let events = Dictionary(uniqueKeysWithValues: viewings.map { ($0.id, $0) })
        var links = Set<UUID>()
        for row in reviews {
            try Task.checkCancellation()
            guard identity(row.mediaID), !row.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  row.text.utf8.count <= 1_048_576, date(row.createdAt), date(row.editedAt) else { throw BackupError.invalidRecords }
            if let event = row.viewingEventID {
                guard events[event]?.mediaID == row.mediaID, links.insert(event).inserted else { throw BackupError.invalidRelationships }
            }
        }
        for row in viewings {
            try Task.checkCancellation()
            guard identity(row.mediaID), date(row.watchedDate), date(row.recordedAt), date(row.updatedAt) else { throw BackupError.invalidRecords }
        }
        let anchors = Set(seasonAnchors.map(\.key))
        for row in seasonAnchors {
            guard identity(row.seriesID), row.seriesID.kind == .tvShow, row.number >= 0 else { throw BackupError.invalidRecords }
        }
        for row in episodeProgress {
            try Task.checkCancellation()
            guard identity(row.episodeID.seriesID), row.episodeID.seriesID.kind == .tvShow,
                  !row.episodeID.providerValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  row.episodeID.providerValue.utf8.count <= 1_024, row.seasonNumber >= 0, date(row.watchedAt),
                  row.isWatched || row.watchedAt == nil,
                  anchors.contains(SeasonKey(series: row.episodeID.seriesID, number: row.seasonNumber)) else { throw BackupError.invalidRelationships }
        }
    }
    func canonical() -> Self {
        var copy = self
        copy.library.sort { $0.id.uuidString < $1.id.uuidString }
        copy.reviews.sort { $0.id.uuidString < $1.id.uuidString }
        copy.viewings.sort { $0.id.uuidString < $1.id.uuidString }
        copy.episodeProgress.sort { $0.id.uuidString < $1.id.uuidString }
        copy.seasonAnchors.sort { $0.id.uuidString < $1.id.uuidString }
        return copy
    }
}

enum BackupError: Error, LocalizedError, Equatable {
    case invalidFormat, unsupportedVersion(Int), invalidRecords, invalidRelationships, tooLarge, readFailed, exportFailed
    case libraryUnavailable, libraryChanged, saveFailed
    var errorDescription: String? {
        switch self {
        case .invalidFormat: "This is not a supported MovieTracker personal backup. No data was changed."
        case .unsupportedVersion(let version): "Backup version \(version) is unsupported. This app supports version 1. No data was changed."
        case .invalidRecords: "The backup contains missing, invalid or duplicate personal records. No data was changed."
        case .invalidRelationships: "The backup contains invalid viewing-review or episode-season associations. No data was changed."
        case .tooLarge: "The backup exceeds the supported file, record or text limits. No data was changed."
        case .readFailed: "The selected backup could not be read. Check file access and try again."
        case .exportFailed: "A complete personal backup could not be exported. Check that saved records have valid identities and ratings, and try again."
        case .libraryUnavailable: "Saved records need attention before backup or restore. Retry loading the Library and resolve integrity errors first."
        case .libraryChanged: "Your Library changed after this preview. Select the backup again to review an updated merge before confirming."
        case .saveFailed: "The restore could not be saved. The previous saved data was restored. Try again."
        }
    }
}
