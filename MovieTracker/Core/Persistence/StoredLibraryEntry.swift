import Foundation
import SwiftData

/// SwiftData storage stays separate from provider-independent domain values.
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
        id = entry.id
        mediaKind = entry.mediaID.kind.rawValue
        mediaValue = entry.mediaID.value
        status = entry.status.rawValue
        isFavorite = entry.isFavorite
        rating = entry.rating
        review = entry.review
        addedAt = entry.addedAt
        updatedAt = entry.updatedAt
    }

    func domainEntry() throws -> UserLibraryEntry {
        guard let kind = MediaID.Kind(rawValue: mediaKind) else {
            throw ConversionError.unknownMediaKind
        }
        guard let libraryStatus = LibraryStatus(rawValue: status) else {
            throw ConversionError.unknownLibraryStatus
        }
        return UserLibraryEntry(
            id: id,
            mediaID: MediaID(kind: kind, value: mediaValue),
            status: libraryStatus,
            isFavorite: isFavorite,
            rating: rating,
            review: review,
            addedAt: addedAt,
            updatedAt: updatedAt
        )
    }

    enum ConversionError: Error, Equatable {
        case unknownMediaKind
        case unknownLibraryStatus
    }
}
