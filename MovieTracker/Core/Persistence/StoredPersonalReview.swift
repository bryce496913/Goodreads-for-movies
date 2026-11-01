import Foundation
import SwiftData

@Model
final class StoredPersonalReview {
    @Attribute(.unique) var id: UUID
    var mediaKind: String
    var mediaValue: String
    var text: String
    var createdAt: Date
    var editedAt: Date
    var viewingEventID: UUID?
    var savedTitle: String
    var snapshotData: Data?
    var isLegacyImport: Bool = false

    init(id: UUID, media: MediaSearchResult, text: String, createdAt: Date, viewingEventID: UUID?, isLegacyImport: Bool = false) throws {
        let item = SearchItem(media)
        self.id = id
        mediaKind = item.id.kind.rawValue; mediaValue = item.id.value
        self.text = text; self.createdAt = createdAt; editedAt = createdAt
        self.viewingEventID = viewingEventID
        self.isLegacyImport = isLegacyImport
        savedTitle = item.title
        snapshotData = try JSONEncoder().encode(media)
    }

    var dateLabel: String {
        if editedAt != createdAt { return "Edited " + editedAt.formatted(date: .abbreviated, time: .shortened) }
        let prefix = isLegacyImport ? "Imported (original date unavailable) " : "Created "
        return prefix + createdAt.formatted(date: .abbreviated, time: .shortened)
    }
    var mediaID: MediaID? { DiaryMedia.identity(kind: mediaKind, value: mediaValue) }
    var savedMedia: MediaSearchResult? { DiaryMedia.restore(data: snapshotData, kind: mediaKind, value: mediaValue, title: savedTitle) }
}
