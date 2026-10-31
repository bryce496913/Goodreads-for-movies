import Foundation

struct Movie: Identifiable, Equatable, Sendable {
    let id: MediaID
    var title: String
    var overview: String
    var releaseDate: Date?
    /// An opaque reference to future local or remote artwork, not a downloaded image.
    var posterReference: String?
    var genreIDs: [String]

    init(
        id: String,
        title: String,
        overview: String = "",
        releaseDate: Date? = nil,
        posterReference: String? = nil,
        genreIDs: [String] = []
    ) {
        self.id = MediaID(kind: .movie, value: id)
        self.title = title
        self.overview = overview
        self.releaseDate = releaseDate
        self.posterReference = posterReference
        self.genreIDs = genreIDs
    }
}
