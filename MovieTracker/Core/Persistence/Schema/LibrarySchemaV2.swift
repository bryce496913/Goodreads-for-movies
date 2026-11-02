import Foundation
import SwiftData

/// Additive lifecycle state. The five V1 personal/cache model definitions remain frozen.
enum LibrarySchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(2, 0, 0) }
    static var models: [any PersistentModel.Type] { LibrarySchemaV1.models + [StoredMetadataState.self] }

    @Model
    final class StoredMetadataState {
        @Attribute(.unique) var id: UUID
        var mediaKind: String
        var mediaValue: String
        var scope: String
        var lastSuccessfulFetch: Date?
        var lastAttempt: Date?
        var lastFailure: String?
        var retryAfter: Date?
        init(id: MediaID, scope: String) {
            self.id = UUID(); mediaKind = id.kind.rawValue; mediaValue = id.value; self.scope = scope
        }
        var mediaID: MediaID? { DiaryMedia.identity(kind: mediaKind, value: mediaValue) }
    }
}
typealias StoredMetadataState = LibrarySchemaV2.StoredMetadataState
