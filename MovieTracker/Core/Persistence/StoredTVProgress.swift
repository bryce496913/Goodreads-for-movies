import Foundation
import SwiftData

@Model
final class StoredTVSeason {
    @Attribute(.unique) var id: UUID
    var seriesValue: String
    var seriesTitle: String
    var seriesData: Data?
    var number: Int
    var name: String
    var expectedEpisodeCount: Int?
    var expectedRegularSeasonCount: Int?
    var isListed: Bool
    var listingLoaded: Bool
    var episodesData: Data?
    var listedIDsData: Data?
    var refreshedAt: Date?

    init(show: TVShow, summary: TVSeasonSummary) throws {
        id = UUID(); seriesValue = show.id.value; seriesTitle = show.title
        seriesData = try JSONEncoder().encode(show)
        number = summary.number; name = summary.name; expectedEpisodeCount = summary.episodeCount
        expectedRegularSeasonCount = show.seasons?.filter { $0.number > 0 }.count
        isListed = true; listingLoaded = false
    }
    var seriesID: MediaID { MediaID(kind: .tvShow, value: seriesValue) }
    var episodes: [TVEpisode] { (try? episodesData.map { try JSONDecoder().decode([TVEpisode].self, from: $0) }) ?? [] }
    var listedIDs: Set<EpisodeID> { Set((try? listedIDsData.map { try JSONDecoder().decode([EpisodeID].self, from: $0) }) ?? []) }
    var coverageKnown: Bool {
        listingLoaded && isListed && expectedEpisodeCount != nil
            && episodes.count == expectedEpisodeCount && listedIDs.count == episodes.count
    }
    var savedShow: TVShow? { try? seriesData.map { try JSONDecoder().decode(TVShow.self, from: $0) } }
}

@Model
final class StoredEpisodeProgress {
    @Attribute(.unique) var id: UUID
    var seriesValue: String
    var episodeValue: String
    var seasonNumber: Int
    var isWatched: Bool
    var watchedAt: Date?
    var episodeData: Data

    init(episode: TVEpisode, watched: Bool, now: Date) throws {
        id = UUID(); seriesValue = episode.id.seriesID.value; episodeValue = episode.id.providerValue
        seasonNumber = episode.seasonNumber; isWatched = watched; watchedAt = watched ? now : nil
        episodeData = try JSONEncoder().encode(episode)
    }
    var episodeID: EpisodeID { EpisodeID(seriesID: MediaID(kind: .tvShow, value: seriesValue), providerValue: episodeValue) }
    var savedEpisode: TVEpisode? { try? JSONDecoder().decode(TVEpisode.self, from: episodeData) }
}
