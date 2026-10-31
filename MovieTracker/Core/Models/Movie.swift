import Foundation

struct Movie: Identifiable, Equatable, Sendable {
    let id: MediaID
    var title: String
    var overview: String
    var releaseDate: Date?
    /// An opaque reference to future local or remote artwork, not a downloaded image.
    var posterReference: String?
    var genres: [MediaGenre]
    var genreIDs: [String]
    var runtimeMinutes: Int?
    var backdropReference: String?

    init(
        id: String,
        title: String,
        overview: String = "",
        releaseDate: Date? = nil,
        posterReference: String? = nil,
        genreIDs: [String] = [],
        runtimeMinutes: Int? = nil,
        backdropReference: String? = nil,
        genres: [MediaGenre] = []
    ) {
        self.id = MediaID(kind: .movie, value: id)
        self.title = title
        self.overview = overview
        self.releaseDate = releaseDate
        self.posterReference = posterReference
        self.genres = genres
        self.genreIDs = genreIDs
        self.runtimeMinutes = runtimeMinutes
        self.backdropReference = backdropReference
    }
}
