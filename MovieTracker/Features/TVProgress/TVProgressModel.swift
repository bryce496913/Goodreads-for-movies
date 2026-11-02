import Foundation
import Observation

@MainActor
@Observable
final class TVProgressModel {
    private(set) var show: TVShow
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    let usesTestData: Bool
    private let service: (any MediaMetadataService)?
    private var generation = UUID()

    init(show: TVShow, service: (any MediaMetadataService)?, usesTestData: Bool = false) {
        self.show = show; self.service = service; self.usesTestData = usesTestData
    }
    func expireMetadata(at now: Date) {
        if MetadataPolicy.isTMDB(show.id), !MetadataPolicy.isUsable(show.metadataRetrievedAt, at: now),
           case .tvShow(let placeholder) = MetadataPolicy.placeholderMedia(show.id) { show = placeholder }
    }
    func seasonModel(_ cached: StoredTVSeason) -> TVProgressModel {
        TVProgressModel(show: cached.savedShow ?? show, service: service, usesTestData: usesTestData)
    }
    func loadCatalog(show candidate: TVShow, store: LibraryStore, snapshotIsFresh: Bool = true, forceRefresh: Bool = false) async {
        generation = UUID(); let token = generation
        let epoch = MetadataRuntimeGate.credentialEpoch
        isLoading = true; errorMessage = nil
        defer { if generation == token { isLoading = false } }
        do {
            var updated = candidate
            if forceRefresh {
                guard let service else { throw MetadataError.missingCredential }
                guard store.mayRefreshMetadata(candidate.id, force: true), MetadataRuntimeGate.blockingReason == nil else { throw MetadataError.retentionBlocked }
                updated = try await service.tvShowDetails(id: candidate.id)
            } else if !snapshotIsFresh && !store.seasons(for: candidate.id).isEmpty {
                show = candidate
                return // Never replace a newer persisted catalogue with an older Library snapshot.
            } else if updated.seasons == nil {
                errorMessage = "No season catalogue is saved in these details. Refresh Seasons to retrieve it."
                return
            }
            try Task.checkCancellation()
            guard generation == token else { return }
            if MetadataPolicy.isTMDB(show.id), epoch != MetadataRuntimeGate.credentialEpoch { throw CancellationError() }
            if forceRefresh { try store.metadataRefreshSucceeded(.tvShow(updated)) }
            try store.cacheSeasonCatalog(show: updated)
            show = updated
        } catch {
            guard generation == token, !Task.isCancelled, !(error is CancellationError) else { return }
            errorMessage = error.localizedDescription
        }
    }
    func loadSeason(_ number: Int, store: LibraryStore, force: Bool = false) async {
        generation = UUID(); let token = generation
        let epoch = MetadataRuntimeGate.credentialEpoch
        isLoading = true; errorMessage = nil
        defer { if generation == token { isLoading = false } }
        do {
            guard let service else { throw MetadataError.missingCredential }
            guard !MetadataPolicy.isTMDB(show.id) || (MetadataRuntimeGate.blockingReason == nil && store.mayRefreshMetadata(show.id, scope: "season:\(number)", force: force)) else { throw MetadataError.retentionBlocked }
            if !force, let cached = store.seasons(for: show.id).first(where: { $0.number == number }),
               cached.coverageKnown && !MetadataPolicy.refreshEligible(cached.refreshedAt, at: store.metadataClock()) { return }
            let details = try await service.tvSeasonDetails(for: show.id, number: number)
            try Task.checkCancellation()
            guard generation == token else { return }
            if MetadataPolicy.isTMDB(show.id), epoch != MetadataRuntimeGate.credentialEpoch { throw CancellationError() }
            try store.cacheSeason(details, show: show)
            try store.seasonRefreshSucceeded(details)
        } catch {
            guard generation == token, !Task.isCancelled, !(error is CancellationError) else { return }
            errorMessage = error.localizedDescription
            if let failure = error as? MetadataError, failure != .missingCredential, failure != .retentionBlocked {
                try? store.metadataRefreshFailed(show.id, scope: "season:\(number)", error: failure)
            }
        }
    }
}
