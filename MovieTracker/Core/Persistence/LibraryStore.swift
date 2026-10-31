import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class LibraryStore {
    private(set) var entries: [StoredLibraryEntry] = []
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
            entries = try context.fetch(FetchDescriptor<StoredLibraryEntry>()).sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                if $0.mediaKind != $1.mediaKind { return $0.mediaKind < $1.mediaKind }
                if $0.mediaValue != $1.mediaValue { return $0.mediaValue < $1.mediaValue }
                return $0.id.uuidString < $1.id.uuidString
            }
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

    func remove(_ id: MediaID) throws {
        do {
            guard let record = try uniqueRecord(for: id) else { return }
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
                        favorite: Bool?, posterURL: URL?) throws {
        let item = SearchItem(media)
        guard !item.id.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LibraryStoreError.invalidIdentity }
        do {
            let existing = try uniqueRecord(for: item.id)
            // Clearing an unsaved status/favorite is a no-op, not a new empty library row.
            if existing == nil && status == nil && favorite != true { return }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(media)
            let record = existing ?? StoredLibraryEntry(entry: UserLibraryEntry(mediaID: item.id, status: nil))
            let newStatus = changesStatus ? (status?.rawValue ?? "none") : record.status
            let newFavorite = favorite ?? record.isFavorite
            let newURL = posterURL?.absoluteString ?? record.savedPosterURL
            guard existing == nil || record.status != newStatus || record.isFavorite != newFavorite
                    || record.snapshotData != data || record.savedTitle != item.title || record.savedYear != item.year
                    || record.savedPosterReference != item.posterReference || record.savedPosterURL != newURL else { return }
            if existing == nil { context.insert(record) }
            record.status = newStatus
            record.isFavorite = newFavorite
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
