import Foundation

extension LibraryStore {
    /// One local path for every navigation entry point; no request and no personal-record creation.
    func cachedMedia(for id: MediaID) -> MediaSearchResult? {
        var candidates: [MediaSearchResult] = []
        if let media = entry(for: id)?.savedMedia { candidates.append(media) }
        candidates += events(for: id).compactMap(\.savedMedia)
        candidates += reviews(for: id).compactMap(\.savedMedia)
        candidates += seasons(for: id).compactMap { row -> MediaSearchResult? in
            row.savedShow.map { .tvShow($0) }
        }
        var best: MediaSearchResult?
        for candidate in candidates where SearchItem(candidate).id == id && MetadataPolicy.mayDisplay(candidate, at: metadataClock()) {
            if best == nil || (candidate.metadataRetrievedAt ?? .distantPast) > (best?.metadataRetrievedAt ?? .distantPast) { best = candidate }
        }
        return best
    }

    /// A late response or an edit from an older screen cannot downgrade a newer successful snapshot.
    func preferredMetadata(_ incoming: MediaSearchResult) -> MediaSearchResult {
        let id = SearchItem(incoming).id
        guard MetadataPolicy.isTMDB(id), let local = cachedMedia(for: id),
              (local.metadataRetrievedAt ?? .distantPast) > (incoming.metadataRetrievedAt ?? .distantPast) else { return incoming }
        return local
    }

    func refreshDeferral(for id: MediaID, scope: String = "title") -> MetadataError {
        metadataState(for: id, scope: scope)?.lastFailure == "rateLimited" ? .rateLimited(retryAfter: nil) : .refreshDeferred
    }
}
