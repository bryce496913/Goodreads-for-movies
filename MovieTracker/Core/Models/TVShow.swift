import Foundation

struct TVShow: Identifiable, Equatable, Sendable {
    let id: MediaID
    var title: String
    var overview: String
    var firstAirDate: Date?
    var posterReference: String?
    var genres: [MediaGenre]
    var genreIDs: [String]
    var episodeRuntimeMinutes: Int?
    var backdropReference: String?
    var episodeCount: Int?
    var seriesStatus: String?
    var seasonCount: Int?

    init(
        id: String,
        title: String,
        overview: String = "",
        firstAirDate: Date? = nil,
        posterReference: String? = nil,
        genreIDs: [String] = [],
        seasonCount: Int? = nil,
        episodeRuntimeMinutes: Int? = nil,
        backdropReference: String? = nil,
        genres: [MediaGenre] = [],
        episodeCount: Int? = nil,
        seriesStatus: String? = nil
    ) {
        self.id = MediaID(kind: .tvShow, value: id)
        self.title = title
        self.overview = overview
        self.firstAirDate = firstAirDate
        self.posterReference = posterReference
        self.genres = genres
        self.genreIDs = genreIDs
        self.episodeRuntimeMinutes = episodeRuntimeMinutes
        self.backdropReference = backdropReference
        self.seasonCount = seasonCount
        self.episodeCount = episodeCount
        self.seriesStatus = seriesStatus
    }
}
