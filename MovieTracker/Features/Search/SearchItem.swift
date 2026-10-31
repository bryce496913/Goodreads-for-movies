import Foundation

struct SearchItem: Identifiable, Equatable, Sendable {
    let id: MediaID
    let title: String
    let year: Int?
    let posterReference: String?

    var mediaType: String { id.kind == .movie ? "Movie" : "TV Show" }
    var destination: MediaDestination { MediaDestination(id: id, title: title, year: year) }

    init(_ result: MediaSearchResult) {
        let date: Date?
        switch result {
        case .movie(let movie):
            id = movie.id; title = movie.title; date = movie.releaseDate; posterReference = movie.posterReference
        case .tvShow(let show):
            id = show.id; title = show.title; date = show.firstAirDate; posterReference = show.posterReference
        }
        // Provider date-only values are UTC, so January 1 must not become the previous year locally.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        year = date.map { calendar.component(.year, from: $0) }
    }
}

enum SearchFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case movies = "Movies"
    case tvShows = "TV Shows"
    var id: Self { self }
}
