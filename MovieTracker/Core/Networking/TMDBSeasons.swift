import Foundation

struct TMDBSeasonSummary: Decodable, Sendable {
    let id: Int?
    let name: String?
    let seasonNumber: Int
    let episodeCount: Int?
    enum CodingKeys: String, CodingKey { case id, name; case seasonNumber = "season_number", episodeCount = "episode_count" }
    func domain() throws -> TVSeasonSummary {
        guard seasonNumber >= 0 else { throw MetadataError.invalidPayload }
        let title = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return TVSeasonSummary(number: seasonNumber, providerID: id.flatMap { $0 > 0 ? "tmdb:\($0)" : nil },
            name: title?.isEmpty == false ? title ?? "" : (seasonNumber == 0 ? "Specials" : "Season \(seasonNumber)"),
            episodeCount: episodeCount.flatMap { $0 >= 0 ? $0 : nil })
    }
}

struct TMDBSeasonResponse: Decodable, Sendable {
    let seasonNumber: Int
    let name: String?
    let episodes: [Episode]
    enum CodingKeys: String, CodingKey { case name, episodes; case seasonNumber = "season_number" }
    struct Episode: Decodable, Sendable {
        let id: Int
        let number: Int
        let season: Int?
        let name: String?
        let airDate: String?
        let overview: String?
        let runtime: Int?
        enum CodingKeys: String, CodingKey {
            case id, name, overview, runtime
            case number = "episode_number", season = "season_number", airDate = "air_date"
        }
    }
    func domain(seriesID: MediaID, requested: Int) throws -> TVSeasonDetails {
        guard seasonNumber == requested else { throw MetadataError.invalidPayload }
        var seen = Set<Int>()
        let values = try episodes.map { episode -> TVEpisode in
            guard episode.id > 0, episode.number >= 0, episode.season == nil || episode.season == requested,
                  seen.insert(episode.id).inserted else { throw MetadataError.invalidPayload }
            let title = episode.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            return TVEpisode(id: EpisodeID(seriesID: seriesID, providerValue: "tmdb:\(episode.id)"),
                seasonNumber: requested, number: episode.number,
                title: title?.isEmpty == false ? title ?? "" : "Episode \(episode.number)",
                airDate: TMDBTitle.date(episode.airDate), overview: episode.overview ?? "",
                runtimeMinutes: episode.runtime.flatMap { $0 > 0 ? $0 : nil })
        }
        let seasonName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return TVSeasonDetails(seriesID: seriesID, number: requested,
            name: seasonName?.isEmpty == false ? seasonName ?? "" : (requested == 0 ? "Specials" : "Season \(requested)"), episodes: values)
    }
}
