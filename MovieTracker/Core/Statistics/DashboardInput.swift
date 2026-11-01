import Foundation

struct DashboardInput: Codable, Sendable {
    struct Title: Codable, Sendable {
        let recordID: UUID
        let mediaID: MediaID?
        let title: String?
        let year: Int?
        let posterURL: URL?
        let status: String
        let favorite: Bool
        let addedAt: Date
        let updatedAt: Date
        let ratingUnits: Int?
        let legacyRating: Double?
        let ratingUpdatedAt: Date?
        let legacyReview: String?
        let mediaData: Data?
    }
    struct Viewing: Codable, Sendable {
        let id: UUID
        let mediaID: MediaID?
        let title: String
        let watchedDate: Date?
        let recordedAt: Date
        let mediaData: Data?
    }
    struct Review: Codable, Sendable {
        let id: UUID
        let mediaID: MediaID?
        let title: String
        let text: String
        let createdAt: Date
        let editedAt: Date
        let imported: Bool
    }
    struct Progress: Codable, Sendable {
        let id: UUID
        let episodeID: EpisodeID
        let season: Int
        let watched: Bool
        let watchedAt: Date?
        let episodeData: Data
    }
    struct Season: Codable, Sendable {
        let id: UUID
        let seriesID: MediaID
        let title: String
        let number: Int
        let expectedEpisodes: Int?
        let expectedRegularSeasons: Int?
        let listed: Bool
        let loaded: Bool
        let episodesData: Data?
        let listedIDsData: Data?
        let seriesData: Data?
        let refreshedAt: Date?
    }
    var titles: [Title] = []
    var viewings: [Viewing] = []
    var reviews: [Review] = []
    var progress: [Progress] = []
    var seasons: [Season] = []

    /// Scalar/COW copies only. JSON decoding, grouping, sorting and arithmetic happen off actor.
    @MainActor
    static func capture(_ store: LibraryStore) -> Self {
        Self(titles: store.entries.map {
            Title(recordID: $0.id, mediaID: $0.mediaID, title: $0.savedTitle, year: $0.savedYear,
                  posterURL: $0.thumbnailURL, status: $0.status, favorite: $0.isFavorite, addedAt: $0.addedAt,
                  updatedAt: $0.updatedAt, ratingUnits: $0.ratingHalfStarUnits, legacyRating: $0.rating,
                  ratingUpdatedAt: $0.ratingUpdatedAt, legacyReview: $0.review, mediaData: $0.snapshotData)
        }, viewings: store.viewingEvents.map {
            Viewing(id: $0.id, mediaID: $0.mediaID, title: $0.savedTitle, watchedDate: $0.watchedDate,
                    recordedAt: $0.recordedAt, mediaData: $0.snapshotData)
        }, reviews: store.personalReviews.map {
            Review(id: $0.id, mediaID: $0.mediaID, title: $0.savedTitle, text: $0.text,
                   createdAt: $0.createdAt, editedAt: $0.editedAt, imported: $0.isLegacyImport)
        }, progress: store.episodeProgress.map {
            Progress(id: $0.id, episodeID: $0.episodeID, season: $0.seasonNumber,
                     watched: $0.isWatched, watchedAt: $0.watchedAt, episodeData: $0.episodeData)
        }, seasons: store.tvSeasons.map {
            Season(id: $0.id, seriesID: $0.seriesID, title: $0.seriesTitle, number: $0.number,
                   expectedEpisodes: $0.expectedEpisodeCount, expectedRegularSeasons: $0.expectedRegularSeasonCount,
                   listed: $0.isListed, loaded: $0.listingLoaded, episodesData: $0.episodesData,
                   listedIDsData: $0.listedIDsData, seriesData: $0.seriesData, refreshedAt: $0.refreshedAt)
        })
    }
}
