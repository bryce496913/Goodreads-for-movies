import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class LibraryStore {
    private(set) var entries: [StoredLibraryEntry] = []
    private(set) var personalReviews: [StoredPersonalReview] = []
    private(set) var viewingEvents: [StoredViewingEvent] = []
    private(set) var tvSeasons: [StoredTVSeason] = []
    private(set) var episodeProgress: [StoredEpisodeProgress] = []
    private(set) var loadError: LibraryStoreError?
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let saveContext: (ModelContext) throws -> Void

    init(container: ModelContainer, save: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        context = ModelContext(container)
        context.autosaveEnabled = false
        saveContext = save
        reload()
    }

    func reload() {
        do {
            let savedEntries = try context.fetch(FetchDescriptor<StoredLibraryEntry>()).sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                if $0.mediaKind != $1.mediaKind { return $0.mediaKind < $1.mediaKind }
                if $0.mediaValue != $1.mediaValue { return $0.mediaValue < $1.mediaValue }
                return $0.id.uuidString < $1.id.uuidString
            }
            let savedReviews = try context.fetch(FetchDescriptor<StoredPersonalReview>()).sorted {
                if $0.editedAt != $1.editedAt { return $0.editedAt > $1.editedAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            let savedEvents = try context.fetch(FetchDescriptor<StoredViewingEvent>()).sorted {
                if $0.sortDate != $1.sortDate { return $0.sortDate > $1.sortDate }
                if $0.recordedAt != $1.recordedAt { return $0.recordedAt > $1.recordedAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            let seasons = try context.fetch(FetchDescriptor<StoredTVSeason>()).sorted {
                if $0.seriesValue != $1.seriesValue { return $0.seriesValue < $1.seriesValue }
                return $0.number < $1.number
            }
            let progress = try context.fetch(FetchDescriptor<StoredEpisodeProgress>())
            tvSeasons = seasons; episodeProgress = progress
            entries = savedEntries; personalReviews = savedReviews; viewingEvents = savedEvents
            loadError = nil
        } catch { loadError = .readFailed }
    }

    func entry(for id: MediaID) -> StoredLibraryEntry? {
        entries.first { $0.mediaKind == id.kind.rawValue && $0.mediaValue == id.value }
    }

    func setStatus(_ status: LibraryStatus?, media: MediaSearchResult, posterURL: URL? = nil) throws {
        let id = SearchItem(media).id
        guard status != .watching || id.kind == .tvShow else { throw LibraryStoreError.invalidStatus }
        try mutate(media: media, status: status, changesStatus: true, favorite: nil, posterURL: posterURL)
    }

    func setFavorite(_ favorite: Bool, media: MediaSearchResult, posterURL: URL? = nil) throws {
        try mutate(media: media, status: nil, changesStatus: false, favorite: favorite, posterURL: posterURL)
    }

    func setPersonalRating(_ rating: PersonalRating?, media: MediaSearchResult, posterURL: URL? = nil) throws {
        try mutate(media: media, status: nil, changesStatus: false, favorite: nil, posterURL: posterURL,
                   rating: rating, changesRating: true)
    }

    func remove(_ id: MediaID) throws {
        do {
            guard let record = try uniqueRecord(for: id) else { return }
            if let legacy = record.review, !legacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                guard let media = record.offlineMedia else { throw LibraryStoreError.invalidIdentity }
                context.insert(try StoredPersonalReview(id: UUID(), media: media, text: legacy, createdAt: .now,
                                                       viewingEventID: nil, isLegacyImport: true))
            }
            context.delete(record)
            try saveContext(context)
            reload()
        } catch {
            context.rollback() // Dedicated context: never roll back another feature's pending work.
            reload()
            throw (error as? LibraryStoreError) ?? .saveFailed
        }
    }

    private func mutate(media: MediaSearchResult, status: LibraryStatus?, changesStatus: Bool,
                        favorite: Bool?, posterURL: URL?, rating: PersonalRating? = nil, changesRating: Bool = false) throws {
        let item = SearchItem(media)
        guard !item.id.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LibraryStoreError.invalidIdentity }
        do {
            let existing = try uniqueRecord(for: item.id)
            // Clearing an unsaved status/favorite is a no-op, not a new empty library row.
            if existing == nil && status == nil && favorite != true && (!changesRating || rating == nil) { return }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(media)
            let record = existing ?? StoredLibraryEntry(entry: UserLibraryEntry(mediaID: item.id, status: nil))
            let newStatus = changesStatus ? (status?.rawValue ?? "none") : record.status
            let newFavorite = favorite ?? record.isFavorite
            let newUnits = changesRating ? rating?.halfStarUnits : record.ratingHalfStarUnits
            let newLegacyStars = changesRating ? rating?.stars : record.rating
            let newURL = posterURL?.absoluteString ?? record.savedPosterURL
            guard existing == nil || record.status != newStatus || record.isFavorite != newFavorite
                    || record.snapshotData != data || record.savedTitle != item.title || record.savedYear != item.year
                    || record.savedPosterReference != item.posterReference || record.savedPosterURL != newURL
                    || (changesRating && (record.ratingHalfStarUnits != newUnits || record.rating != newLegacyStars)) else { return }
            if existing == nil { context.insert(record) }
            record.status = newStatus
            record.isFavorite = newFavorite
            record.ratingHalfStarUnits = newUnits
            record.rating = newLegacyStars
            record.savedTitle = item.title
            record.savedYear = item.year
            record.savedPosterReference = item.posterReference
            record.savedPosterURL = newURL
            record.snapshotData = data
            record.updatedAt = .now
            try saveContext(context)
            reload()
        } catch {
            context.rollback()
            reload()
            throw (error as? LibraryStoreError) ?? .saveFailed
        }
    }

    func writeTransaction(_ operation: (ModelContext) throws -> Void) throws {
        do {
            try operation(context)
            try saveContext(context)
            reload()
        } catch {
            context.rollback()
            reload()
            if let error = error as? DiaryError { throw error }
            if let error = error as? TVProgressError { throw error }
            throw (error as? LibraryStoreError) ?? .saveFailed
        }
    }

    func diaryLibraryEntry(for id: MediaID) throws -> StoredLibraryEntry? { try uniqueRecord(for: id) }

    func ensureLibraryEntry(media: MediaSearchResult) throws -> StoredLibraryEntry {
        let item = SearchItem(media)
        guard !item.id.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LibraryStoreError.invalidIdentity }
        if let existing = try uniqueRecord(for: item.id) { return existing }
        let record = StoredLibraryEntry(entry: UserLibraryEntry(mediaID: item.id, status: nil))
        record.savedTitle = item.title; record.savedYear = item.year; record.savedPosterReference = item.posterReference
        record.snapshotData = try JSONEncoder().encode(media)
        context.insert(record)
        return record
    }

    private func uniqueRecord(for id: MediaID) throws -> StoredLibraryEntry? {
        let kind = id.kind.rawValue
        let value = id.value
        var descriptor = FetchDescriptor<StoredLibraryEntry>(predicate: #Predicate {
            $0.mediaKind == kind && $0.mediaValue == value
        })
        descriptor.fetchLimit = 2
        let matches: [StoredLibraryEntry]
        do { matches = try context.fetch(descriptor) } catch { throw LibraryStoreError.readFailed }
        guard matches.count < 2 else { throw LibraryStoreError.duplicateRecords }
        return matches.first
    }
}

enum LibraryStoreError: Error, LocalizedError {
    case readFailed, saveFailed, duplicateRecords, invalidIdentity, invalidStatus
    var errorDescription: String? {
        switch self {
        case .readFailed: "Your library could not be read. Try loading it again."
        case .saveFailed: "Your library changes could not be saved. Your previous saved state has been restored. Try again."
        case .duplicateRecords: "Multiple saved records exist for this title. No changes were made; the existing records need review."
        case .invalidIdentity: "This title does not have a usable identifier."
        case .invalidStatus: "Watching is available for television series. Choose Watchlist or Watched for a movie."
        }
    }
}
