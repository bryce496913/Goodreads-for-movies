import Foundation

struct DashboardTitle: Identifiable, Sendable {
    let id: MediaID
    let title: String
    let year: Int?
    let posterURL: URL?
    let rating: PersonalRating?
    var destination: MediaDestination { MediaDestination(id: id, title: title, year: year) }
}
struct DashboardDiaryItem: Identifiable, Sendable {
    let id: UUID
    let title: DashboardTitle
    let watchedDate: Date?
    let recordedAt: Date
    var sortDate: Date { watchedDate ?? recordedAt }
}
struct DashboardActivity: Identifiable, Sendable {
    let id: String
    let title: DashboardTitle
    let label: String
    let date: Date
    let watchedDate: Date?
}
struct ContinueWatchingItem: Identifiable, Sendable {
    let title: DashboardTitle
    let show: TVShow
    let progress: EpisodeProgressSummary
    let next: TVEpisode?
    let lastMarked: TVEpisode?
    let lastMarkedAt: Date?
    var id: MediaID { title.id }
}
struct ViewingStatistics: Equatable, Sendable {
    let watchedMovies: Int
    let seriesWithProgress: Int
    let watchedEpisodes: Int
    let watchlist: Int
    let favorites: Int
    let ratings: Int
    let averageRating: Double?
    let reviews: Int
    let viewingEvents: Int
}
struct DashboardSnapshot: Sendable {
    let statistics: ViewingStatistics
    let continueWatching: [ContinueWatchingItem]
    let recentlyWatched: [DashboardDiaryItem]
    let recentDiary: [DashboardDiaryItem]
    let watchlist: [DashboardTitle]
    let activity: [DashboardActivity]
    let duplicateTitles: Int
    let invalidRatings: Int
    let unclassifiedTitles: Int
    let hasPersonalData: Bool
}
