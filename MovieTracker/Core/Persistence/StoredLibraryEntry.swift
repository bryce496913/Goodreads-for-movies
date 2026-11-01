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
    var rating: Double? // Legacy compatible mirror; retained for safe schema evolution.
    var ratingHalfStarUnits: Int? = nil
    var ratingUpdatedAt: Date? = nil
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
        id = entry.id
        mediaKind = entry.mediaID.kind.rawValue
        mediaValue = entry.mediaID.value
        status = entry.status?.rawValue ?? "none"
        isFavorite = entry.isFavorite
        rating = entry.rating?.stars
        ratingHalfStarUnits = entry.rating?.halfStarUnits
        review = entry.review
        addedAt = entry.addedAt
        updatedAt = entry.updatedAt
    }

    func domainEntry() throws -> UserLibraryEntry {
        guard let kind = MediaID.Kind(rawValue: mediaKind) else {
            throw ConversionError.unknownMediaKind
        }
        let libraryStatus: LibraryStatus?
        if status == "none" {
            libraryStatus = nil
        } else {
            guard let value = LibraryStatus(rawValue: status) else { throw ConversionError.unknownLibraryStatus }
            libraryStatus = value
        }
        return UserLibraryEntry(
            id: id,
            mediaID: MediaID(kind: kind, value: mediaValue),
            status: libraryStatus,
            isFavorite: isFavorite,
            rating: try validatedRating(),
            review: review,
            addedAt: addedAt,
            updatedAt: updatedAt
        )
    }

    func validatedRating() throws -> PersonalRating? {
        if let ratingHalfStarUnits { return try PersonalRating(halfStarUnits: ratingHalfStarUnits) }
        if let rating { return try PersonalRating.fromLegacyStars(rating) }
        return nil
    }

    enum ConversionError: Error, Equatable {
        case unknownMediaKind
        case unknownLibraryStatus
    }
}
