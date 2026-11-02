import SwiftData

/// PR011–012's five-entity shape, now explicitly frozen as the current baseline.
/// Global Stored* aliases preserve call sites and persisted entity basenames.
enum LibrarySchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(1, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [StoredLibraryEntry.self, StoredPersonalReview.self, StoredViewingEvent.self,
         StoredTVSeason.self, StoredEpisodeProgress.self]
    }
}

enum LibraryMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [LibrarySchemaFoundation.self, LibrarySchemaSnapshots.self, LibrarySchemaRatings.self,
         LibrarySchemaDiary.self, LibrarySchemaTVProgress.self, LibrarySchemaV1.self, LibrarySchemaV2.self]
    }
    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: LibrarySchemaFoundation.self, toVersion: LibrarySchemaSnapshots.self),
            .lightweight(fromVersion: LibrarySchemaSnapshots.self, toVersion: LibrarySchemaRatings.self),
            .lightweight(fromVersion: LibrarySchemaRatings.self, toVersion: LibrarySchemaDiary.self),
            .lightweight(fromVersion: LibrarySchemaDiary.self, toVersion: LibrarySchemaTVProgress.self),
            .lightweight(fromVersion: LibrarySchemaTVProgress.self, toVersion: LibrarySchemaV1.self),
            .lightweight(fromVersion: LibrarySchemaV1.self, toVersion: LibrarySchemaV2.self)
        ]
    }
}
