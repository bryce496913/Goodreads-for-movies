import Foundation
import SwiftData

@MainActor
enum MetadataPurger {
    static func purge(_ context: ModelContext, at now: Date, all: Bool = false) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let savedStates = try context.fetch(FetchDescriptor<StoredMetadataState>())
        struct Key: Hashable { let id: MediaID; let scope: String }
        var states: [Key: StoredMetadataState] = [:]
        for state in savedStates {
            if let id = state.mediaID { states[Key(id: id, scope: state.scope)] = state }
        }
        // Preserve only the original receipt fact when content expires, not a new lease or an attempt.
        func remember(_ id: MediaID, fetched: Date?, scope: String = "title") {
            guard !all, let fetched, fetched <= now, fetched.timeIntervalSinceReferenceDate.isFinite else { return }
            let key = Key(id: id, scope: scope)
            let state = states[key] ?? StoredMetadataState(id: id, scope: scope)
            if states[key] == nil { context.insert(state); states[key] = state }
            if state.lastSuccessfulFetch == nil || state.lastSuccessfulFetch! < fetched { state.lastSuccessfulFetch = fetched }
        }
        func expired(_ date: Date?) -> Bool { all || !MetadataPolicy.isUsable(date, at: now) }
        func media(_ data: Data?) -> MediaSearchResult? { data.flatMap { try? JSONDecoder().decode(MediaSearchResult.self, from: $0) } }
        for row in try context.fetch(FetchDescriptor<StoredLibraryEntry>()) {
            guard let id = row.mediaID, MetadataPolicy.isTMDB(id) else { continue }
            let fetched = media(row.snapshotData)?.metadataRetrievedAt
            guard expired(fetched) else { continue }
            remember(id, fetched: fetched)
            if row.savedTitle != nil || row.savedYear != nil || row.savedPosterReference != nil || row.savedPosterURL != nil || row.snapshotData != nil {
                row.savedTitle = nil; row.savedYear = nil; row.savedPosterReference = nil; row.savedPosterURL = nil; row.snapshotData = nil
            }
        }
        for row in try context.fetch(FetchDescriptor<StoredPersonalReview>()) {
            guard let id = row.mediaID, MetadataPolicy.isTMDB(id) else { continue }
            let fetched = media(row.snapshotData)?.metadataRetrievedAt
            guard expired(fetched) else { continue }
            remember(id, fetched: fetched)
            if row.savedTitle != MetadataPolicy.placeholder(id) || row.snapshotData != nil {
                row.savedTitle = MetadataPolicy.placeholder(id); row.snapshotData = nil
            }
        }
        for row in try context.fetch(FetchDescriptor<StoredViewingEvent>()) {
            guard let id = row.mediaID, MetadataPolicy.isTMDB(id) else { continue }
            let fetched = media(row.snapshotData)?.metadataRetrievedAt
            guard expired(fetched) else { continue }
            remember(id, fetched: fetched)
            if row.savedTitle != MetadataPolicy.placeholder(id) || row.snapshotData != nil {
                row.savedTitle = MetadataPolicy.placeholder(id); row.snapshotData = nil
            }
        }
        for row in try context.fetch(FetchDescriptor<StoredTVSeason>()) where MetadataPolicy.isTMDB(row.seriesID) {
            let showReceipt = row.savedShow?.metadataRetrievedAt
            if expired(showReceipt) {
                remember(row.seriesID, fetched: showReceipt)
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
                remember(row.seriesID, fetched: row.refreshedAt, scope: "season:\(row.number)")
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
