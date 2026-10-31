import Foundation

enum LibraryStatus: String, Codable, CaseIterable, Sendable {
    case watchlist
    case watching
    case watched
}

struct UserLibraryEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let mediaID: MediaID
    var status: LibraryStatus
    /// Favorites are independent of viewing status, so a watched item can also be a favorite.
    var isFavorite: Bool
    /// Optional future rating; the rating scale will be decided with the editing feature.
    var rating: Double?
    var review: String?
    let addedAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        mediaID: MediaID,
        status: LibraryStatus = .watchlist,
        isFavorite: Bool = false,
        rating: Double? = nil,
        review: String? = nil,
        addedAt: Date = .now,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.mediaID = mediaID
        self.status = status
        self.isFavorite = isFavorite
        self.rating = rating
        self.review = review
        self.addedAt = addedAt
        self.updatedAt = updatedAt ?? addedAt
    }
}
