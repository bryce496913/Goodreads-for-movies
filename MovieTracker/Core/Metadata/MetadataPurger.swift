import Foundation
import SwiftData

@MainActor
enum MetadataPurger {
    static func purge(_ context: ModelContext, at now: Date, all: Bool = false) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        func expired(_ date: Date?) -> Bool { all || !MetadataPolicy.isUsable(date, at: now) }
        func media(_ data: Data?) -> MediaSearchResult? { data.flatMap { try? JSONDecoder().decode(MediaSearchResult.self, from: $0) } }
        for row in try context.fetch(FetchDescriptor<StoredLibraryEntry>()) {
            guard let id = row.mediaID, MetadataPolicy.isTMDB(id), expired(media(row.snapshotData)?.metadataRetrievedAt) else { continue }
            if row.savedTitle != nil || row.savedYear != nil || row.savedPosterReference != nil || row.savedPosterURL != nil || row.snapshotData != nil {
                row.savedTitle = nil; row.savedYear = nil; row.savedPosterReference = nil; row.savedPosterURL = nil; row.snapshotData = nil
            }
        }
        for row in try context.fetch(FetchDescriptor<StoredPersonalReview>()) {
            guard let id = row.mediaID, MetadataPolicy.isTMDB(id), expired(media(row.snapshotData)?.metadataRetrievedAt) else { continue }
            if row.savedTitle != MetadataPolicy.placeholder(id) || row.snapshotData != nil {
                row.savedTitle = MetadataPolicy.placeholder(id); row.snapshotData = nil
            }
        }
        for row in try context.fetch(FetchDescriptor<StoredViewingEvent>()) {
            guard let id = row.mediaID, MetadataPolicy.isTMDB(id), expired(media(row.snapshotData)?.metadataRetrievedAt) else { continue }
            if row.savedTitle != MetadataPolicy.placeholder(id) || row.snapshotData != nil {
                row.savedTitle = MetadataPolicy.placeholder(id); row.snapshotData = nil
            }
        }
        for row in try context.fetch(FetchDescriptor<StoredTVSeason>()) where MetadataPolicy.isTMDB(row.seriesID) {
            if expired(row.savedShow?.metadataRetrievedAt) {
                let placeholder = MetadataPolicy.placeholder(row.seriesID)
                if row.seriesTitle != placeholder || row.seriesData != nil || row.expectedRegularSeasonCount != nil || row.isListed {
                    row.seriesTitle = placeholder; row.seriesData = nil; row.expectedRegularSeasonCount = nil; row.isListed = false
                }
            }
            let episodes = row.episodes
            let kept = episodes.filter { !expired($0.metadataRetrievedAt) }
            if kept.count != episodes.count || (row.episodesData.map { (try? JSONDecoder().decode([TVEpisode].self, from: $0)) == nil } == true) {
                row.episodesData = kept.isEmpty ? nil : try encoder.encode(kept)
                row.listedIDsData = kept.isEmpty ? nil : try encoder.encode(kept.map(\.id))
                row.listingLoaded = false
            }
            // A season header is leased by its successful episode listing, not a personal edit.
            if expired(row.refreshedAt) || (kept.isEmpty && row.seriesData == nil) {
                if row.name != "Season metadata unavailable" || row.expectedEpisodeCount != nil || row.listingLoaded || row.listedIDsData != nil {
                    row.name = "Season metadata unavailable"; row.expectedEpisodeCount = nil; row.listingLoaded = false; row.listedIDsData = nil
                }
            }
        }
        for row in try context.fetch(FetchDescriptor<StoredEpisodeProgress>()) where MetadataPolicy.isTMDB(row.episodeID.seriesID) {
            guard expired(row.savedEpisode?.metadataRetrievedAt) else { continue }
            let placeholder = TVEpisode(id: row.episodeID, seasonNumber: row.seasonNumber, number: 0,
                title: "Episode metadata unavailable", airDate: nil, overview: "", runtimeMinutes: nil)
            let data = try encoder.encode(placeholder)
            if row.episodeData != data { row.episodeData = data }
        }
    }
}
