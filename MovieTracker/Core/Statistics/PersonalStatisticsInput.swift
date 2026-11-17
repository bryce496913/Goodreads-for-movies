import Foundation

/// Only the scalar fields needed for statistics cross to the worker; no live SwiftData objects,
/// private review text, artwork, episode payloads or network services.
struct PersonalStatisticsInput: Sendable {
    struct Title: Sendable {
        let recordID: UUID
        let mediaID: MediaID?
        let updatedAt: Date
        let ratingUnits: Int?
        let legacyRating: Double?
        let mediaData: Data?
    }
    struct Viewing: Sendable {
        let id: UUID
        let mediaID: MediaID?
        let watchedDate: Date?
        let mediaData: Data?
    }
    struct Episode: Sendable {
        let id: EpisodeID
        let watched: Bool
        let markedAt: Date?
    }
    var titles: [Title] = []
    var viewings: [Viewing] = []
    var episodes: [Episode] = []

    @MainActor static func capture(_ store: LibraryStore) -> Self {
        Self(titles: store.entries.map {
            Title(recordID: $0.id, mediaID: $0.mediaID, updatedAt: $0.updatedAt,
                  ratingUnits: $0.ratingHalfStarUnits, legacyRating: $0.rating, mediaData: $0.snapshotData)
        }, viewings: store.viewingEvents.map {
            Viewing(id: $0.id, mediaID: $0.mediaID, watchedDate: $0.watchedDate, mediaData: $0.snapshotData)
        }, episodes: store.episodeProgress.map {
            Episode(id: $0.episodeID, watched: $0.isWatched, markedAt: $0.watchedAt)
        })
    }
}

enum PersonalStatisticsError: Error { case invalidReferenceDate, invalidYear }

struct PersonalStatisticsSnapshot: Sendable {
    struct Month: Identifiable, Equatable, Sendable {
        let number: Int
        var movieEvents = 0
        var seriesEvents = 0
        var episodeMarks = 0
        var id: Int { number }
    }
    struct RatingBucket: Identifiable, Equatable, Sendable {
        let units: Int
        var count = 0
        var id: Int { units }
        var stars: Double { Double(units) / 2 }
    }
    struct Genre: Identifiable, Equatable, Sendable {
        let id: String
        let name: String
        let titles: Int
    }
    let year: Int
    let years: [Int]
    let months: [Month]
    let uniqueMovies: Int
    let uniqueSeries: Int
    let ratingBuckets: [RatingBucket]
    let unratedTitles: Int
    let invalidRatings: Int
    let genres: [Genre]
    let genreEligibleTitles: Int
    let missingGenreTitles: Int
    let nextMetadataExpiry: Date?
    let undatedEvents: Int
    let excludedEvents: Int
    let unknownEpisodeDates: Int
    let excludedEpisodeDates: Int
    let overallWatchedEpisodes: Int
    let conflictingEpisodes: Int
    var movieEvents: Int { months.reduce(0) { $0 + $1.movieEvents } }
    var seriesEvents: Int { months.reduce(0) { $0 + $1.seriesEvents } }
    var episodeMarks: Int { months.reduce(0) { $0 + $1.episodeMarks } }
    var activeMovieMonths: Int { months.filter { $0.movieEvents > 0 }.count }
    var busiestMovieMonth: Month? {
        months.filter { $0.movieEvents > 0 }.max {
            $0.movieEvents != $1.movieEvents ? $0.movieEvents < $1.movieEvents : $0.number > $1.number
        }
    }
}
