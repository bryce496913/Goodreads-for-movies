import Foundation
import SwiftData

extension LibraryStore {
    /// Main-actor scalar capture only; encoding, validation and planning run on immutable copies.
    func capturePersonalBackup(at now: Date = .now, applicationVersion: String? = nil, includeAllAnchors: Bool = false) throws -> PersonalBackup {
        guard loadError == nil else { throw BackupError.libraryUnavailable }
        var result = PersonalBackup(exportedAt: now, applicationVersion: applicationVersion)
        result.library = try entries.map { row in
            guard let id = row.mediaID, row.status == "none" || LibraryStatus(rawValue: row.status) != nil else { throw BackupError.libraryUnavailable }
            let rating: PersonalRating?
            do { rating = try row.validatedRating() } catch { throw BackupError.libraryUnavailable }
            return PersonalBackup.Library(id: row.id, mediaID: id, status: LibraryStatus(rawValue: row.status), favorite: row.isFavorite,
                ratingHalfStarUnits: rating?.halfStarUnits, ratingUpdatedAt: row.ratingUpdatedAt,
                legacyReview: row.review, addedAt: row.addedAt, updatedAt: row.updatedAt)
        }
        result.reviews = try personalReviews.map { row in
            guard let id = row.mediaID else { throw BackupError.libraryUnavailable }
            return PersonalBackup.Review(id: row.id, mediaID: id, text: row.text, createdAt: row.createdAt,
                editedAt: row.editedAt, viewingEventID: row.viewingEventID, isLegacyImport: row.isLegacyImport)
        }
        result.viewings = try viewingEvents.map { row in
            guard let id = row.mediaID else { throw BackupError.libraryUnavailable }
            return PersonalBackup.Viewing(id: row.id, mediaID: id, watchedDate: row.watchedDate, recordedAt: row.recordedAt, updatedAt: row.updatedAt)
        }
        result.episodeProgress = episodeProgress.map {
            PersonalBackup.Progress(id: $0.id, episodeID: $0.episodeID, seasonNumber: $0.seasonNumber, isWatched: $0.isWatched, watchedAt: $0.watchedAt)
        }
        let keys = Set(result.episodeProgress.map { PersonalBackup.SeasonKey(series: $0.episodeID.seriesID, number: $0.seasonNumber) })
        result.seasonAnchors = tvSeasons.filter { includeAllAnchors || keys.contains(.init(series: $0.seriesID, number: $0.number)) }.map {
            PersonalBackup.SeasonAnchor(id: $0.id, seriesID: $0.seriesID, number: $0.number)
        }
        let known = Set(result.seasonAnchors.map(\.key))
        // Old stores may contain progress without a cached season. Use the first stable progress UUID as its deterministic anchor.
        var missing: [PersonalBackup.SeasonKey: PersonalBackup.Progress] = [:]
        for row in result.episodeProgress {
            let key = PersonalBackup.SeasonKey(series: row.episodeID.seriesID, number: row.seasonNumber)
            if !known.contains(key), missing[key] == nil || row.id.uuidString < missing[key]!.id.uuidString { missing[key] = row }
        }
        for (key, row) in missing { result.seasonAnchors.append(.init(id: row.id, seriesID: key.series, number: key.number)) }
        return result
    }

    /// UI must obtain a plan/summary and explicit confirmation before calling this one-save merge.
    func restorePersonalBackup(_ plan: BackupMergePlan) throws {
        guard loadError == nil else { throw BackupError.libraryUnavailable }
        guard revision == plan.revision else { throw BackupError.libraryChanged }
        let source = plan.additions
        do {
            try writeTransaction { context in
                for row in source.library {
                    let rating = try row.ratingHalfStarUnits.map { try PersonalRating(halfStarUnits: $0) }
                    let value = StoredLibraryEntry(entry: UserLibraryEntry(id: row.id, mediaID: row.mediaID, status: row.status,
                        isFavorite: row.favorite, rating: rating, review: row.legacyReview, addedAt: row.addedAt, updatedAt: row.updatedAt))
                    value.ratingUpdatedAt = row.ratingUpdatedAt; context.insert(value)
                }
                for row in source.viewings {
                    let value = try StoredViewingEvent(id: row.id, media: MetadataPolicy.placeholderMedia(row.mediaID), watchedDate: row.watchedDate, recordedAt: row.recordedAt)
                    value.updatedAt = row.updatedAt; value.snapshotData = nil; context.insert(value)
                }
                for row in source.reviews {
                    let value = try StoredPersonalReview(id: row.id, media: MetadataPolicy.placeholderMedia(row.mediaID), text: row.text,
                        createdAt: row.createdAt, viewingEventID: row.viewingEventID, isLegacyImport: row.isLegacyImport)
                    value.editedAt = row.editedAt; value.snapshotData = nil; context.insert(value)
                }
                for row in source.seasonAnchors {
                    let value = try StoredTVSeason(show: TVShow(id: row.seriesID.value, title: MetadataPolicy.placeholder(row.seriesID)),
                        summary: TVSeasonSummary(number: row.number, providerID: nil, name: "Season metadata unavailable", episodeCount: nil))
                    value.id = row.id; value.seriesData = nil; value.isListed = false; context.insert(value)
                }
                for row in source.episodeProgress {
                    let episode = TVEpisode(id: row.episodeID, seasonNumber: row.seasonNumber, number: 0, title: "Episode metadata unavailable",
                        airDate: nil, overview: "", runtimeMinutes: nil)
                    let value = try StoredEpisodeProgress(episode: episode, watched: row.isWatched, now: row.watchedAt ?? Date(timeIntervalSinceReferenceDate: 0))
                    value.id = row.id; value.watchedAt = row.watchedAt; context.insert(value)
                }
            }
        } catch { throw BackupError.saveFailed } // LibraryStore has already rolled back and reloaded; no private diagnostics.
    }
}
