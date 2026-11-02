import Foundation

/// A complete, immutable plan. Only this planner can construct one; applying it requires its source revision.
struct BackupMergePlan: Sendable {
    struct Counts: Equatable, Sendable {
        var library = 0, reviews = 0, viewings = 0, progress = 0, anchors = 0
        var total: Int { library + reviews + viewings + progress + anchors }
    }
    let revision: Int
    let additions: PersonalBackup
    let kept: Int
    let conflicts: [String] // Static reason + identifier only, never review text or provider content.
    let counts: Counts
    fileprivate init(revision: Int, additions: PersonalBackup, kept: Int, conflicts: [String], counts: Counts) {
        self.revision = revision; self.additions = additions; self.kept = kept; self.conflicts = conflicts; self.counts = counts
    }
}

enum BackupMergePlanner {
    static func prepare(_ source: PersonalBackup, local: PersonalBackup, revision: Int) throws -> BackupMergePlan {
        try source.validate()
        do { try local.validate() } catch is CancellationError { throw CancellationError() }
        catch { throw BackupError.libraryUnavailable }
        let incoming = source.canonical()
        var added = PersonalBackup(exportedAt: source.exportedAt, applicationVersion: source.applicationVersion)
        var conflicts: [String] = [], kept = 0
        let libraryByID = Dictionary(uniqueKeysWithValues: local.library.map { ($0.mediaID, $0) })
        let libraryUUIDs = Dictionary(uniqueKeysWithValues: local.library.map { ($0.id, $0) })
        for row in incoming.library {
            try Task.checkCancellation()
            if let existing = libraryByID[row.mediaID] {
                kept += 1
                // Matching MediaID may have a different local UUID: preserve the local row in its entirety.
                if existing.status != row.status || existing.favorite != row.favorite || existing.ratingHalfStarUnits != row.ratingHalfStarUnits
                    || existing.legacyReview != row.legacyReview || existing.addedAt != row.addedAt || existing.updatedAt != row.updatedAt
                    || existing.ratingUpdatedAt != row.ratingUpdatedAt {
                    conflicts.append("Library \(row.mediaID.kind.rawValue) \(row.mediaID.value): existing personal fields kept.")
                }
            } else if libraryUUIDs[row.id] != nil {
                kept += 1; conflicts.append("Library UUID \(row.id): another local identity uses this UUID; incoming row skipped.")
            } else { added.library.append(row) }
        }
        var events = Dictionary(uniqueKeysWithValues: local.viewings.map { ($0.id, $0) })
        for row in incoming.viewings {
            try Task.checkCancellation()
            if let old = events[row.id] {
                kept += 1
                if old != row { conflicts.append("Viewing \(row.id): existing identity and dates kept.") }
            } else { added.viewings.append(row); events[row.id] = row }
        }
        let reviews = Dictionary(uniqueKeysWithValues: local.reviews.map { ($0.id, $0) })
        var linked = Set(local.reviews.compactMap(\.viewingEventID))
        for row in incoming.reviews {
            try Task.checkCancellation()
            if let old = reviews[row.id] {
                kept += 1
                if old != row { conflicts.append("Review \(row.id): existing text and association kept.") }
            } else if let event = row.viewingEventID, events[event]?.mediaID != row.mediaID || linked.contains(event) {
                kept += 1; conflicts.append("Review \(row.id): its event association conflicts with local data; incoming review skipped.")
            } else {
                added.reviews.append(row)
                if let event = row.viewingEventID { linked.insert(event) }
            }
        }
        let episodes = Dictionary(uniqueKeysWithValues: local.episodeProgress.map { ($0.episodeID, $0) })
        let episodeUUIDs = Dictionary(uniqueKeysWithValues: local.episodeProgress.map { ($0.id, $0) })
        var anchors = Dictionary(uniqueKeysWithValues: local.seasonAnchors.map { ($0.key, $0) })
        let anchorUUIDs = Dictionary(uniqueKeysWithValues: local.seasonAnchors.map { ($0.id, $0) })
        let sourceAnchors = Dictionary(uniqueKeysWithValues: source.seasonAnchors.map { ($0.key, $0) })
        for row in incoming.episodeProgress {
            try Task.checkCancellation()
            if let old = episodes[row.episodeID] {
                kept += 1
                if old.isWatched != row.isWatched || old.watchedAt != row.watchedAt || old.seasonNumber != row.seasonNumber {
                    conflicts.append("Episode \(row.episodeID.seriesID.value) / \(row.episodeID.providerValue): existing watched state and season kept.")
                }
                continue
            }
            guard episodeUUIDs[row.id] == nil else {
                kept += 1; conflicts.append("Episode UUID \(row.id): another local episode uses this UUID; incoming progress skipped."); continue
            }
            let key = PersonalBackup.SeasonKey(series: row.episodeID.seriesID, number: row.seasonNumber)
            if anchors[key] == nil, let anchor = sourceAnchors[key] {
                guard anchorUUIDs[anchor.id] == nil else {
                    kept += 1; conflicts.append("Episode \(row.id): its season UUID conflicts with local data; incoming progress skipped."); continue
                }
                anchors[key] = anchor; added.seasonAnchors.append(anchor)
            }
            added.episodeProgress.append(row)
        }
        let counts = BackupMergePlan.Counts(library: added.library.count, reviews: added.reviews.count,
            viewings: added.viewings.count, progress: added.episodeProgress.count, anchors: added.seasonAnchors.count)
        return BackupMergePlan(revision: revision, additions: added, kept: kept, conflicts: conflicts, counts: counts)
    }
}
