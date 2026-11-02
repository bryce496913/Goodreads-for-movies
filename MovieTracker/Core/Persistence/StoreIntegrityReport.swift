import Foundation
import SwiftData

struct StoreIntegrityIssue: Hashable {
    enum Entity: String { case library, review, viewing, season, episode }
    enum Kind: String { case duplicateUUID, duplicateIdentity, invalidIdentity, danglingAssociation, crossMediaAssociation, duplicateAssociation, inconsistentSnapshot }
    let entity: Entity
    let kind: Kind
    let records: [UUID]
}

/// Read-only diagnostics: no merging, deletion, parent recreation or guessed identity repair.
@MainActor
enum StoreIntegrityReport {
    static func read(_ context: ModelContext) throws -> Set<StoreIntegrityIssue> {
        audit(entries: try context.fetch(FetchDescriptor<StoredLibraryEntry>()),
              reviews: try context.fetch(FetchDescriptor<StoredPersonalReview>()),
              events: try context.fetch(FetchDescriptor<StoredViewingEvent>()),
              seasons: try context.fetch(FetchDescriptor<StoredTVSeason>()),
              progress: try context.fetch(FetchDescriptor<StoredEpisodeProgress>()))
    }

    static func audit(entries: [StoredLibraryEntry], reviews: [StoredPersonalReview], events: [StoredViewingEvent],
                      seasons: [StoredTVSeason], progress: [StoredEpisodeProgress]) -> Set<StoreIntegrityIssue> {
        var issues = Set<StoreIntegrityIssue>()
        func add(_ entity: StoreIntegrityIssue.Entity, _ kind: StoreIntegrityIssue.Kind, _ records: [UUID]) {
            issues.insert(.init(entity: entity, kind: kind, records: records.sorted { $0.uuidString < $1.uuidString }))
        }
        func duplicates<T, Key: Hashable>(_ rows: [T], entity: StoreIntegrityIssue.Entity, kind: StoreIntegrityIssue.Kind,
                                          key: (T) -> Key, id: (T) -> UUID) {
            for group in Dictionary(grouping: rows, by: key).values where group.count > 1 { add(entity, kind, group.map(id)) }
        }
        duplicates(entries, entity: .library, kind: .duplicateUUID, key: { $0.id }, id: { $0.id })
        duplicates(reviews, entity: .review, kind: .duplicateUUID, key: { $0.id }, id: { $0.id })
        duplicates(events, entity: .viewing, kind: .duplicateUUID, key: { $0.id }, id: { $0.id })
        duplicates(seasons, entity: .season, kind: .duplicateUUID, key: { $0.id }, id: { $0.id })
        duplicates(progress, entity: .episode, kind: .duplicateUUID, key: { $0.id }, id: { $0.id })
        duplicates(entries.filter { $0.mediaID != nil }, entity: .library, kind: .duplicateIdentity,
                   key: { $0.mediaID }, id: { $0.id })
        duplicates(progress, entity: .episode, kind: .duplicateIdentity, key: { $0.episodeID }, id: { $0.id })
        struct SeasonKey: Hashable { let series: MediaID; let number: Int }
        duplicates(seasons, entity: .season, kind: .duplicateIdentity,
                   key: { SeasonKey(series: $0.seriesID, number: $0.number) }, id: { $0.id })
        func valid(_ id: MediaID?) -> Bool { id?.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
        for row in entries where !valid(row.mediaID) { add(.library, .invalidIdentity, [row.id]) }
        for row in events where !valid(row.mediaID) { add(.viewing, .invalidIdentity, [row.id]) }
        let eventsByID = Dictionary(grouping: events, by: \.id)
        for row in reviews {
            if !valid(row.mediaID) { add(.review, .invalidIdentity, [row.id]) }
            if let eventID = row.viewingEventID {
                guard let matches = eventsByID[eventID], matches.count == 1, let event = matches.first else {
                    add(.review, .danglingAssociation, [row.id]); continue
                }
                if row.mediaID == nil || row.mediaID != event.mediaID { add(.review, .crossMediaAssociation, [row.id]) }
            }
        }
        duplicates(reviews.filter { $0.viewingEventID != nil }, entity: .review, kind: .duplicateAssociation,
                   key: { $0.viewingEventID }, id: { $0.id })
        for row in seasons {
            if !valid(row.seriesID) || row.number < 0 { add(.season, .invalidIdentity, [row.id]) }
            if let data = row.seriesData, let show = try? JSONDecoder().decode(TVShow.self, from: data), show.id != row.seriesID {
                add(.season, .inconsistentSnapshot, [row.id])
            }
        }
        for row in progress {
            if !valid(row.episodeID.seriesID) || row.episodeValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || row.seasonNumber < 0 {
                add(.episode, .invalidIdentity, [row.id])
            }
            guard let episode = row.savedEpisode, episode.id == row.episodeID, episode.seasonNumber == row.seasonNumber else {
                add(.episode, .inconsistentSnapshot, [row.id]); continue
            }
        }
        return issues
    }
}
