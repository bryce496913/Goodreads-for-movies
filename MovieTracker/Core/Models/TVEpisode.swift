import Foundation

struct EpisodeID: Codable, Hashable, Sendable {
    let seriesID: MediaID
    /// Opaque provider-qualified stable ID; numbers/titles are mutable metadata, not identity.
    let providerValue: String
}

struct TVEpisode: Codable, Identifiable, Equatable, Sendable {
    let id: EpisodeID
    var seasonNumber: Int
    var number: Int
    var title: String
    var airDate: Date?
    var overview: String
    var runtimeMinutes: Int?
    var metadataRetrievedAt: Date? = nil
}

struct TVSeasonSummary: Codable, Identifiable, Hashable, Sendable {
    let number: Int
    let providerID: String?
    let name: String
    let episodeCount: Int?
    var id: Int { number } // Only used within its owning series.
}

struct TVSeasonDetails: Sendable {
    let seriesID: MediaID
    let number: Int
    let name: String
    let episodes: [TVEpisode]
    var metadataRetrievedAt: Date? = nil
}

struct EpisodeProgressSummary: Equatable, Sendable {
    let watched: Int
    let totalWatched: Int
    let eligible: Int
    let future: Int
    let unknownAirDate: Int
    let coverageKnown: Bool
    var percentage: Int? { coverageKnown && eligible > 0 ? Int((Double(watched) / Double(eligible) * 100).rounded()) : nil }
    var isUpToDate: Bool { coverageKnown && eligible > 0 && watched == eligible }

    static func calculate(episodes: [TVEpisode], watchedIDs: Set<EpisodeID>, coverageKnown: Bool, now: Date = .now) -> Self {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt
        let today = calendar.startOfDay(for: now)
        var seen = Set<EpisodeID>()
        var watched = 0, totalWatched = 0, eligible = 0, future = 0, unknown = 0
        for episode in episodes where seen.insert(episode.id).inserted {
            let marked = watchedIDs.contains(episode.id)
            if marked { totalWatched += 1 }
            if let date = episode.airDate {
                if date <= today { eligible += 1; if marked { watched += 1 } }
                else { future += 1 }
            } else { unknown += 1 }
        }
        return Self(watched: watched, totalWatched: totalWatched, eligible: eligible,
                    future: future, unknownAirDate: unknown, coverageKnown: coverageKnown)
    }
}
