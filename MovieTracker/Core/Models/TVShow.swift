import Foundation

struct TVShow: Identifiable, Equatable, Sendable {
    let id: MediaID
    var title: String
    var overview: String
    var firstAirDate: Date?
    var posterReference: String?
    var genreIDs: [String]
    var seasonCount: Int?

    init(
        id: String,
        title: String,
        overview: String = "",
        firstAirDate: Date? = nil,
        posterReference: String? = nil,
        genreIDs: [String] = [],
        seasonCount: Int? = nil
    ) {
        self.id = MediaID(kind: .tvShow, value: id)
        self.title = title
        self.overview = overview
        self.firstAirDate = firstAirDate
        self.posterReference = posterReference
        self.genreIDs = genreIDs
        self.seasonCount = seasonCount
    }
}
