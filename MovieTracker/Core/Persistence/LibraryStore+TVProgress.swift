import Foundation
import SwiftData

extension LibraryStore {
    func seasons(for series: MediaID) -> [StoredTVSeason] {
        guard series.kind == .tvShow else { return [] }
        _ = revision; return seasonsBySeries[series] ?? []
    }

    func savedTVShow(for id: MediaID) -> TVShow? {
        guard id.kind == .tvShow, let first = seasons(for: id).first else { return nil }
        return first.savedShow ?? TVShow(id: id.value, title: first.seriesTitle)
    }

    func episodes(for season: StoredTVSeason) -> [TVEpisode] {
        _ = revision
        if let cached = seasonEpisodeCache[season.id] { return cached }
        var seen = Set<EpisodeID>()
        var values = season.episodes.filter { seen.insert($0.id).inserted }
        for record in progressBySeason[season.seriesID]?[season.number] ?? [] {
            if let episode = record.savedEpisode, seen.insert(episode.id).inserted { values.append(episode) }
        }
        let result = values.filter { $0.id.seriesID == season.seriesID && $0.seasonNumber == season.number }.sorted {
            if $0.number != $1.number { return $0.number < $1.number }
            return $0.id.providerValue < $1.id.providerValue
        }
        seasonEpisodeCache[season.id] = result
        return result
    }

    func isWatched(_ id: EpisodeID) -> Bool { _ = revision; return progressByEpisode[id]?.first?.isWatched == true }

    func seasonProgress(_ season: StoredTVSeason, now: Date = .now) -> EpisodeProgressSummary {
        _ = revision
        let day = progressDay(now)
        if let cached = seasonSummaryCache[season.id], cached.0 == day { return cached.1 }
        let values = episodes(for: season)
        let watched = watchedEpisodeIDs
        let result = EpisodeProgressSummary.calculate(episodes: values, watchedIDs: watched,
                          coverageKnown: season.coverageKnown && values.count == season.episodes.count, now: now)
        seasonSummaryCache[season.id] = (day, result); return result
    }

    func seriesProgress(_ series: MediaID, now: Date = .now) -> EpisodeProgressSummary {
        _ = revision
        let day = progressDay(now)
        if let cached = seriesSummaryCache[series], cached.0 == day { return cached.1 }
        let regular = seasons(for: series).filter { $0.number > 0 }
        let expected = regular.compactMap(\.expectedRegularSeasonCount).max()
        let values = regular.map { episodes(for: $0) }
        let coverage = !regular.isEmpty && expected == regular.count && zip(regular, values).allSatisfy { season, episodes in
            season.coverageKnown && episodes.count == season.episodes.count
        }
        let result = EpisodeProgressSummary.calculate(episodes: values.flatMap { $0 },
                          watchedIDs: watchedEpisodeIDs, coverageKnown: coverage, now: now)
        seriesSummaryCache[series] = (day, result); return result
    }

    private func progressDay(_ now: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt
        return calendar.startOfDay(for: now)
    }

    func cacheSeasonCatalog(show: TVShow) throws {
        guard show.id.kind == .tvShow, !show.id.value.isEmpty, let summaries = show.seasons,
              summaries.allSatisfy({ $0.number >= 0 }), Set(summaries.map(\.number)).count == summaries.count else {
            throw TVProgressError.invalidEpisode
        }
        try writeTransaction { context in
            let rows = try seasonRows(show.id, context: context)
            if MetadataPolicy.isTMDB(show.id), rows.contains(where: {
                ($0.savedShow?.metadataRetrievedAt ?? .distantPast) > (show.metadataRetrievedAt ?? .distantPast)
            }) { return }
            for row in rows {
                row.isListed = summaries.contains { $0.number == row.number }
                row.expectedRegularSeasonCount = summaries.filter { $0.number > 0 }.count
                row.seriesData = try JSONEncoder().encode(show)
            }
            for summary in summaries {
                let row = try seasonRecord(show, number: summary.number, context: context)
                row.name = summary.name; row.expectedEpisodeCount = summary.episodeCount
                row.expectedRegularSeasonCount = summaries.filter { $0.number > 0 }.count
                row.seriesTitle = show.title; row.seriesData = try JSONEncoder().encode(show); row.isListed = true
            }
        }
    }

    func cacheSeason(_ details: TVSeasonDetails, show: TVShow, now: Date = .now) throws {
        guard details.seriesID == show.id, show.id.kind == .tvShow, details.number >= 0,
              details.episodes.allSatisfy({ $0.id.seriesID == show.id && $0.seasonNumber == details.number && $0.number >= 0 && !$0.id.providerValue.isEmpty }),
              Set(details.episodes.map(\.id)).count == details.episodes.count else { throw TVProgressError.invalidEpisode }
        try writeTransaction { context in
            let row = try seasonRecord(show, number: details.number, context: context)
            if MetadataPolicy.isTMDB(show.id), let incoming = details.metadataRetrievedAt,
               let current = row.refreshedAt, current > incoming { return }
            var merged: [EpisodeID: TVEpisode] = [:]
            for episode in row.episodes { merged[episode.id] = episode }
            for episode in details.episodes { merged[episode.id] = episode }
            row.name = details.name
            row.expectedEpisodeCount = max(row.expectedEpisodeCount ?? details.episodes.count, details.episodes.count)
            row.episodesData = try JSONEncoder().encode(Array(merged.values).sorted { $0.id.providerValue < $1.id.providerValue })
            row.listedIDsData = try JSONEncoder().encode(details.episodes.map(\.id))
            row.listingLoaded = true; row.refreshedAt = details.metadataRetrievedAt ?? now
            row.seriesData = try JSONEncoder().encode(show)
            // A stable provider ID may move seasons. Move cached metadata, never the watched flag.
            let newIDs = Set(details.episodes.map(\.id))
            for other in try seasonRows(show.id, context: context) where other.number != details.number {
                let remaining = other.episodes.filter { !newIDs.contains($0.id) }
                if remaining.count != other.episodes.count {
                    other.episodesData = try JSONEncoder().encode(remaining)
                    other.listedIDsData = try JSONEncoder().encode(Array(other.listedIDs.subtracting(newIDs)))
                }
            }
            for progress in try progressRows(show.id, context: context) {
                if let episode = details.episodes.first(where: { $0.id == progress.episodeID }) {
                    progress.episodeData = try JSONEncoder().encode(episode)
                    progress.seasonNumber = episode.seasonNumber
                }
            }
        }
    }

    func setEpisodeWatched(_ watched: Bool, episode: TVEpisode, show: TVShow, now: Date = .now) throws {
        guard episode.id.seriesID == show.id, show.id.kind == .tvShow, episode.seasonNumber >= 0, episode.number >= 0,
              !show.id.value.isEmpty, !episode.id.providerValue.isEmpty else { throw TVProgressError.invalidEpisode }
        if watched && isFuture(episode, now: now) { throw TVProgressError.futureEpisode }
        try writeTransaction { context in
            if watched { try prepareWatching(show) }
            try updateProgress(watched, episode: episode, context: context, now: now)
            let season = try seasonRecord(show, number: episode.seasonNumber, context: context)
            if !season.episodes.contains(where: { $0.id == episode.id }) {
                season.episodesData = try JSONEncoder().encode(season.episodes + [episode])
            }
        }
    }

    func setSeasonWatched(_ watched: Bool, season: StoredTVSeason, show: TVShow, now: Date = .now) throws {
        guard season.seriesID == show.id, show.id.kind == .tvShow else { throw TVProgressError.invalidEpisode }
        try writeTransaction { context in
            guard let owned = try seasonRows(show.id, context: context).first(where: { $0.id == season.id && $0.number == season.number }) else {
                throw TVProgressError.invalidEpisode
            }
            let eligible = episodes(for: owned).filter { $0.airDate != nil && !isFuture($0, now: now) }
            if watched {
                if !eligible.isEmpty { try prepareWatching(show) }
                let grouped = Dictionary(grouping: try progressRows(show.id, context: context), by: \.episodeValue)
                for episode in eligible {
                    try updateProgress(true, episode: episode, context: context, now: now, existingMatches: grouped[episode.id.providerValue] ?? [])
                }
            } else {
                for progress in try progressRows(show.id, context: context) where progress.seasonNumber == season.number {
                    progress.isWatched = false; progress.watchedAt = nil
                }
            }
        }
    }

    private func prepareWatching(_ show: TVShow) throws {
        let entry = try ensureLibraryEntry(media: .tvShow(show))
        if entry.status == "none" || entry.status == "watchlist" { entry.status = "watching"; entry.updatedAt = .now }
    }

    private func updateProgress(_ watched: Bool, episode: TVEpisode, context: ModelContext, now: Date, existingMatches: [StoredEpisodeProgress]? = nil) throws {
        let matches: [StoredEpisodeProgress]
        if let existingMatches { matches = existingMatches }
        else {
            let series = episode.id.seriesID.value, value = episode.id.providerValue
            var descriptor = FetchDescriptor<StoredEpisodeProgress>(predicate: #Predicate { $0.seriesValue == series && $0.episodeValue == value })
            descriptor.fetchLimit = 2
            matches = try context.fetch(descriptor)
        }
        guard matches.count < 2 else { throw LibraryStoreError.duplicateRecords }
        if let record = matches.first {
            if record.isWatched != watched { record.isWatched = watched; record.watchedAt = watched ? now : nil }
            record.episodeData = try JSONEncoder().encode(episode); record.seasonNumber = episode.seasonNumber
        } else if watched { context.insert(try StoredEpisodeProgress(episode: episode, watched: true, now: now)) }
    }

    private func seasonRecord(_ show: TVShow, number: Int, context: ModelContext) throws -> StoredTVSeason {
        let matches = try seasonRows(show.id, context: context).filter { $0.number == number }
        guard matches.count < 2 else { throw LibraryStoreError.duplicateRecords }
        if let first = matches.first { return first }
        let summary = show.seasons?.first { $0.number == number }
            ?? TVSeasonSummary(number: number, providerID: nil, name: number == 0 ? "Specials" : "Season \(number)", episodeCount: nil)
        let row = try StoredTVSeason(show: show, summary: summary)
        context.insert(row)
        return row
    }

    private func seasonRows(_ id: MediaID, context: ModelContext) throws -> [StoredTVSeason] {
        let value = id.value
        let rows = try context.fetch(FetchDescriptor<StoredTVSeason>(predicate: #Predicate { $0.seriesValue == value }))
        guard !Dictionary(grouping: rows, by: \.number).values.contains(where: { $0.count > 1 }) else { throw LibraryStoreError.duplicateRecords }
        return rows
    }
    private func progressRows(_ id: MediaID, context: ModelContext) throws -> [StoredEpisodeProgress] {
        let value = id.value
        let rows = try context.fetch(FetchDescriptor<StoredEpisodeProgress>(predicate: #Predicate { $0.seriesValue == value }))
        guard !Dictionary(grouping: rows, by: \.episodeValue).values.contains(where: { $0.count > 1 }) else { throw LibraryStoreError.duplicateRecords }
        return rows
    }
    func isFuture(_ episode: TVEpisode, now: Date = .now) -> Bool {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt
        return episode.airDate.map { $0 > calendar.startOfDay(for: now) } == true
    }
}

enum TVProgressError: Error, LocalizedError {
    case invalidEpisode, futureEpisode
    var errorDescription: String? {
        switch self {
        case .invalidEpisode: "This season or episode has inconsistent identifiers. No progress was changed."
        case .futureEpisode: "This episode has a future air date. It cannot be marked watched yet."
        }
    }
}
