import Foundation
import SwiftData

@Model
final class StoredViewingEvent {
    @Attribute(.unique) var id: UUID
    var mediaKind: String
    var mediaValue: String
    /// A UTC-normalized civil date, not the timestamp when the record was created.
    var watchedDate: Date?
    var recordedAt: Date
    var updatedAt: Date
    var savedTitle: String
    var snapshotData: Data?

    init(id: UUID, media: MediaSearchResult, watchedDate: Date?, recordedAt: Date) throws {
        let item = SearchItem(media)
        self.id = id; mediaKind = item.id.kind.rawValue; mediaValue = item.id.value
        self.watchedDate = watchedDate; self.recordedAt = recordedAt; updatedAt = recordedAt
        savedTitle = item.title; snapshotData = try JSONEncoder().encode(media)
    }

    var mediaID: MediaID? { DiaryMedia.identity(kind: mediaKind, value: mediaValue) }
    var savedMedia: MediaSearchResult? { DiaryMedia.restore(data: snapshotData, kind: mediaKind, value: mediaValue, title: savedTitle) }
    var sortDate: Date { watchedDate ?? recordedAt }
    var dateLabel: String {
        if let watchedDate { return "Watched " + DetailFormatting.date(watchedDate) }
        return "Date recorded " + recordedAt.formatted(date: .abbreviated, time: .shortened)
    }
}

enum DiaryMedia {
    static func identity(kind: String, value: String) -> MediaID? {
        guard let kind = MediaID.Kind(rawValue: kind) else { return nil }
        return MediaID(kind: kind, value: value)
    }
    static func restore(data: Data?, kind: String, value: String, title: String) -> MediaSearchResult? {
        guard let id = identity(kind: kind, value: value) else { return nil }
        if let data, let media = try? JSONDecoder().decode(MediaSearchResult.self, from: data), SearchItem(media).id == id { return media }
        // Private text remains accessible even if its metadata snapshot is missing or from a newer version.
        switch id.kind {
        case .movie: return .movie(Movie(id: id.value, title: title))
        case .tvShow: return .tvShow(TVShow(id: id.value, title: title))
        }
    }
}
