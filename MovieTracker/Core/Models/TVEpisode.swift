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
        let unique = episodes.filter { seen.insert($0.id).inserted }
        let eligible = unique.filter { $0.airDate.map { $0 <= today } == true }
        return Self(watched: eligible.filter { watchedIDs.contains($0.id) }.count,
                    totalWatched: unique.filter { watchedIDs.contains($0.id) }.count, eligible: eligible.count,
                    future: unique.filter { $0.airDate.map { $0 > today } == true }.count,
                    unknownAirDate: unique.filter { $0.airDate == nil }.count, coverageKnown: coverageKnown)
    }
}
