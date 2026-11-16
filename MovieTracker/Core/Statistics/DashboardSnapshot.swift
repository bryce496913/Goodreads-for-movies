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

/// A local candidate does not imply globally reliable ordering or complete coverage.
enum NextEpisodeSelection: Equatable, Sendable {
    case reliable(TVEpisode)
    case knownUnwatched(TVEpisode)
    case unavailable

    var reliableEpisode: TVEpisode? {
        if case .reliable(let episode) = self { return episode }
        return nil
    }
}

enum NextEpisodeSelector {
    static func select(series: MediaID, episodes: [TVEpisode], watched: Set<EpisodeID>,
                       seasons: [Int], coverageKnown: Bool, now: Date) -> NextEpisodeSelection {
        guard series.kind == .tvShow, !series.value.isEmpty, now.timeIntervalSinceReferenceDate.isFinite else { return .unavailable }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt
        let today = calendar.startOfDay(for: now)
        let regular = episodes.filter { $0.seasonNumber > 0 }
        let valid = regular.filter {
            $0.id.seriesID == series && !$0.id.providerValue.isEmpty && $0.number > 0
                && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && (!MetadataPolicy.isTMDB(series) || MetadataPolicy.isUsable($0.metadataRetrievedAt, at: now))
        }
        let candidates = valid.filter {
            !watched.contains($0.id) && $0.airDate.map { $0.timeIntervalSinceReferenceDate.isFinite && $0 <= today } == true
        }.sorted {
            if $0.seasonNumber != $1.seasonNumber { return $0.seasonNumber < $1.seasonNumber }
            if $0.number != $1.number { return $0.number < $1.number }
            return $0.id.providerValue < $1.id.providerValue
        }
        guard let candidate = candidates.first else { return .unavailable }
        let seasonNumbers = Array(Set(seasons.filter { $0 > 0 })).sorted()
        let contiguousSeasons = !seasonNumbers.isEmpty && seasonNumbers == Array(1...seasonNumbers.count)
        let unambiguousPositions = Dictionary(grouping: valid, by: \.seasonNumber).values.allSatisfy { values in
            values.map(\.number).sorted() == Array(1...values.count)
        }
        let unknownRemaining = valid.contains {
            !watched.contains($0.id) && ($0.airDate == nil || $0.airDate?.timeIntervalSinceReferenceDate.isFinite == false)
        }
        guard coverageKnown, contiguousSeasons, valid.allSatisfy({ seasonNumbers.contains($0.seasonNumber) }),
              unambiguousPositions, valid.count == regular.count,
              Set(valid.map(\.id)).count == valid.count, !unknownRemaining else { return .knownUnwatched(candidate) }
        return .reliable(candidate)
    }
}
