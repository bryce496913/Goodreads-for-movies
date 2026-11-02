import Foundation
import SwiftData

extension LibraryStore {
    func maintainMetadata(at date: Date? = nil) throws {
        let now = date ?? metadataClock()
        metadataPolicyEnabled = true
        metadataReferenceDate = now
        try writeTransaction { try MetadataPurger.purge($0, at: now) }
    }

    func clearProviderMetadata() throws {
        try writeTransaction { try MetadataPurger.purge($0, at: metadataClock(), all: true) }
        metadataInvalidation += 1
        ProviderArtworkCache.shared.clear()
        URLCache.shared.removeAllCachedResponses()
    }
    func clearMetadataBackoff() throws {
        try writeTransaction { context in
            for state in try context.fetch(FetchDescriptor<StoredMetadataState>()) { state.lastFailure = nil; state.retryAfter = nil }
        }
    }

    func metadataState(for id: MediaID, scope: String = "title") -> StoredMetadataState? {
        metadataStates.first { $0.mediaID == id && $0.scope == scope }
    }
    func mayRefreshMetadata(_ id: MediaID, scope: String = "title", at date: Date? = nil, force: Bool = false) -> Bool {
        guard MetadataPolicy.isTMDB(id) else { return true }
        let now = date ?? metadataClock()
        let state = metadataState(for: id, scope: scope)
        if force && state?.lastFailure != "rateLimited" { return true }
        return state?.retryAfter.map { now >= $0 } ?? true
    }
    func metadataRefreshFailed(_ id: MediaID, scope: String = "title", error: MetadataError, at date: Date? = nil) throws {
        guard MetadataPolicy.isTMDB(id) else { return }
        let now = date ?? metadataClock()
        try writeTransaction { context in
            let state = try uniqueMetadataState(id, scope: scope, in: context)
            state.lastAttempt = now
            // Persist only sanitized enum categories, never provider bodies, credentials or arbitrary messages.
            state.lastFailure = Self.failureCategory(error)
            let advisory: TimeInterval
            if case .rateLimited(let raw) = error { advisory = MetadataPolicy.retryDelay(raw, at: now) }
            else { advisory = MetadataPolicy.retryInterval }
            state.retryAfter = now.addingTimeInterval(advisory)
        }
    }
    func metadataRefreshSucceeded(_ media: MediaSearchResult, posterURL: URL? = nil) throws {
        let id = SearchItem(media).id
        guard MetadataPolicy.isTMDB(id), let fetched = media.metadataRetrievedAt,
              MetadataPolicy.isUsable(fetched, at: metadataClock()) else { return }
        if let successful = metadataState(for: id)?.lastSuccessfulFetch, successful > fetched { return }
        if let retained = cachedMedia(for: id)?.metadataRetrievedAt, retained > fetched { return }
        let item = SearchItem(media), data = try JSONEncoder().encode(media)
        let kind = id.kind.rawValue, value = id.value
        try writeTransaction { context in
            let state = try uniqueMetadataState(id, scope: "title", in: context)
            state.lastSuccessfulFetch = max(state.lastSuccessfulFetch ?? fetched, fetched); state.lastAttempt = metadataClock(); state.lastFailure = nil; state.retryAfter = nil
            for row in try context.fetch(FetchDescriptor<StoredLibraryEntry>(predicate: #Predicate { $0.mediaKind == kind && $0.mediaValue == value })) {
                let previousURL = row.savedPosterReference == item.posterReference ? row.savedPosterURL : nil
                row.savedTitle = item.title; row.savedYear = item.year; row.savedPosterReference = item.posterReference
                row.savedPosterURL = posterURL?.absoluteString ?? previousURL; row.snapshotData = data
            }
            for row in try context.fetch(FetchDescriptor<StoredPersonalReview>(predicate: #Predicate { $0.mediaKind == kind && $0.mediaValue == value })) {
                row.savedTitle = item.title; row.snapshotData = data
            }
            for row in try context.fetch(FetchDescriptor<StoredViewingEvent>(predicate: #Predicate { $0.mediaKind == kind && $0.mediaValue == value })) {
                row.savedTitle = item.title; row.snapshotData = data
            }
        }
    }
    func seasonRefreshSucceeded(_ details: TVSeasonDetails) throws {
        guard MetadataPolicy.isTMDB(details.seriesID), let fetched = details.metadataRetrievedAt,
              MetadataPolicy.isUsable(fetched, at: metadataClock()) else { return }
        if let current = metadataState(for: details.seriesID, scope: "season:\(details.number)")?.lastSuccessfulFetch, current > fetched { return }
        try writeTransaction { context in
            let state = try uniqueMetadataState(details.seriesID, scope: "season:\(details.number)", in: context)
            state.lastSuccessfulFetch = max(state.lastSuccessfulFetch ?? fetched, fetched); state.lastAttempt = metadataClock(); state.lastFailure = nil; state.retryAfter = nil
        }
    }
    private func uniqueMetadataState(_ id: MediaID, scope: String, in context: ModelContext) throws -> StoredMetadataState {
        let kind = id.kind.rawValue, value = id.value
        var descriptor = FetchDescriptor<StoredMetadataState>(predicate: #Predicate {
            $0.mediaKind == kind && $0.mediaValue == value && $0.scope == scope
        })
        descriptor.fetchLimit = 2
        let matches = try context.fetch(descriptor)
        guard matches.count < 2 else { throw LibraryStoreError.duplicateRecords }
        if let row = matches.first { return row }
        let row = StoredMetadataState(id: id, scope: scope); context.insert(row); return row
    }
    private static func failureCategory(_ error: MetadataError) -> String {
        switch error {
        case .offline, .connectionLost, .connectionFailed, .dnsFailure: "offline"
        case .unauthorized: "unauthorized"
        case .forbidden: "forbidden"
        case .notFound: "notFound"
        case .rateLimited: "rateLimited"
        case .missingCredential, .invalidCredentialFormat, .credentialUnavailable: "configuration"
        case .timedOut: "timedOut"
        default: "providerFailure"
        }
    }
}
