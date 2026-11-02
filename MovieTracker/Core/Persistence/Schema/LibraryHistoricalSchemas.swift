import Foundation
import SwiftData

// Frozen published field definitions. Do not edit these when adding a future version.

// Source: 5060993; PR001.
enum LibrarySchemaFoundation: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(0, 1, 0) }
    static var models: [any PersistentModel.Type] { [StoredLibraryEntry.self] }

    @Model
    final class StoredLibraryEntry {
        @Attribute(.unique) var id: UUID
        var mediaKind: String
        var mediaValue: String
        var status: String
        var isFavorite: Bool
        var rating: Double?
        var review: String?
        var addedAt: Date
        var updatedAt: Date

        init(entry: UserLibraryEntry) {
            id = entry.id; mediaKind = entry.mediaID.kind.rawValue; mediaValue = entry.mediaID.value
            status = entry.status?.rawValue ?? "none"; isFavorite = entry.isFavorite
            rating = entry.rating?.stars; review = entry.review
            addedAt = entry.addedAt; updatedAt = entry.updatedAt
        }
    }
}

// Source: 7e8f696; PR006.
enum LibrarySchemaSnapshots: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(0, 6, 0) }
    static var models: [any PersistentModel.Type] { [StoredLibraryEntry.self] }

    @Model
    final class StoredLibraryEntry {
        @Attribute(.unique) var id: UUID
        var mediaKind: String
        var mediaValue: String
        var status: String
        var isFavorite: Bool
        var rating: Double?
        var review: String?
        var addedAt: Date
        var updatedAt: Date

        // Additive optional fields: old rows remain valid during lightweight migration.
        var savedTitle: String? = nil
        var savedYear: Int? = nil
        var savedPosterReference: String? = nil
        var savedPosterURL: String? = nil
        var snapshotData: Data? = nil

        init(entry: UserLibraryEntry) {
            id = entry.id; mediaKind = entry.mediaID.kind.rawValue; mediaValue = entry.mediaID.value
            status = entry.status?.rawValue ?? "none"; isFavorite = entry.isFavorite
            rating = entry.rating?.stars; review = entry.review
            addedAt = entry.addedAt; updatedAt = entry.updatedAt
        }
    }
}

// Source: 6418725; PR007.
enum LibrarySchemaRatings: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(0, 7, 0) }
    static var models: [any PersistentModel.Type] { [StoredLibraryEntry.self] }

    @Model
    final class StoredLibraryEntry {
        @Attribute(.unique) var id: UUID
        var mediaKind: String
        var mediaValue: String
        var status: String
        var isFavorite: Bool
        var rating: Double? // Legacy compatible mirror; retained for safe schema evolution.
        var ratingHalfStarUnits: Int? = nil
        var review: String?
        var addedAt: Date
        var updatedAt: Date

        // Additive optional fields: old rows remain valid during lightweight migration.
        var savedTitle: String? = nil
        var savedYear: Int? = nil
        var savedPosterReference: String? = nil
        var savedPosterURL: String? = nil
        var snapshotData: Data? = nil

        init(entry: UserLibraryEntry) {
            id = entry.id; mediaKind = entry.mediaID.kind.rawValue; mediaValue = entry.mediaID.value
            status = entry.status?.rawValue ?? "none"; isFavorite = entry.isFavorite
            rating = entry.rating?.stars; review = entry.review
            addedAt = entry.addedAt; updatedAt = entry.updatedAt
            ratingHalfStarUnits = entry.rating?.halfStarUnits
        }
    }
}

// PR008 added reviews and events; unchanged classes are shared with the frozen V1 definition.
enum LibrarySchemaDiary: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(0, 8, 0) }
    typealias StoredLibraryEntry = LibrarySchemaRatings.StoredLibraryEntry
    static var models: [any PersistentModel.Type] {
        [StoredLibraryEntry.self, LibrarySchemaV1.StoredPersonalReview.self, LibrarySchemaV1.StoredViewingEvent.self]
    }
}

// PR009–010 added seasons/progress. The library shape is identical to PR007.
enum LibrarySchemaTVProgress: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(0, 9, 0) }
    typealias StoredLibraryEntry = LibrarySchemaRatings.StoredLibraryEntry
    static var models: [any PersistentModel.Type] {
        [StoredLibraryEntry.self, LibrarySchemaV1.StoredPersonalReview.self, LibrarySchemaV1.StoredViewingEvent.self,
         LibrarySchemaV1.StoredTVSeason.self, LibrarySchemaV1.StoredEpisodeProgress.self]
    }
}
