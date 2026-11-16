import Foundation
import SwiftData

/// Additive personal collections. V1/V2 entity declarations and their deletion rules remain frozen.
enum LibrarySchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(3, 0, 0) }
    static var models: [any PersistentModel.Type] { LibrarySchemaV2.models + [StoredCollection.self, StoredCollectionMembership.self] }

    @Model final class StoredCollection {
        @Attribute(.unique) var id: UUID
        var name: String
        var createdAt: Date
        var updatedAt: Date
        init(id: UUID = UUID(), name: String, createdAt: Date, updatedAt: Date) {
            self.id = id; self.name = name; self.createdAt = createdAt; self.updatedAt = updatedAt
        }
    }
    @Model final class StoredCollectionMembership {
        @Attribute(.unique) var id: UUID
        var collectionID: UUID
        var mediaKind: String
        var mediaValue: String
        var position: Int
        var addedAt: Date
        init(id: UUID = UUID(), collectionID: UUID, mediaID: MediaID, position: Int, addedAt: Date) {
            self.id = id; self.collectionID = collectionID; mediaKind = mediaID.kind.rawValue
            mediaValue = mediaID.value; self.position = position; self.addedAt = addedAt
        }
        var mediaID: MediaID? { DiaryMedia.identity(kind: mediaKind, value: mediaValue) }
    }
}
typealias StoredCollection = LibrarySchemaV3.StoredCollection
typealias StoredCollectionMembership = LibrarySchemaV3.StoredCollectionMembership
