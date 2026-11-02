import Foundation
import Observation

@MainActor
@Observable
final class TVProgressModel {
    private(set) var show: TVShow
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    var canRefresh: Bool { service != nil && MetadataRuntimeGate.blockingReason == nil }
    private(set) var lastError: MetadataError?
    private(set) var isUsingSavedSeason = false
    let usesTestData: Bool
    private let configurationError: MetadataError
    private let service: (any MediaMetadataService)?
    private var generation = UUID()

    init(show: TVShow, service: (any MediaMetadataService)?, usesTestData: Bool = false, configurationError: MetadataError = .missingCredential) {
        self.configurationError = configurationError
        self.show = show; self.service = service; self.usesTestData = usesTestData
    }
    func expireMetadata(at now: Date) {
        if MetadataPolicy.isTMDB(show.id), !MetadataPolicy.isUsable(show.metadataRetrievedAt, at: now),
           case .tvShow(let placeholder) = MetadataPolicy.placeholderMedia(show.id) { show = placeholder }
    }
    func seasonModel(_ cached: StoredTVSeason) -> TVProgressModel {
        TVProgressModel(show: cached.savedShow ?? show, service: service, usesTestData: usesTestData, configurationError: configurationError)
    }
    func loadCatalog(show candidate: TVShow, store: LibraryStore, snapshotIsFresh: Bool = true, forceRefresh: Bool = false) async {
        if isLoading && !forceRefresh { return }
        generation = UUID(); let token = generation
        let epoch = MetadataRuntimeGate.credentialEpoch
        isLoading = true; errorMessage = nil; lastError = nil
        defer { if generation == token { isLoading = false } }
        do {
            var updated = candidate
            if case .tvShow(let retained) = store.preferredMetadata(.tvShow(candidate)) { updated = retained }
            if forceRefresh {
                guard let service else { throw configurationError }
                guard MetadataRuntimeGate.blockingReason == nil else { throw MetadataError.retentionBlocked }
                guard store.mayRefreshMetadata(candidate.id, force: true) else {
                    lastError = store.refreshDeferral(for: candidate.id); errorMessage = lastError?.localizedDescription
                    return
                }
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
            guard updated.id == candidate.id else { throw MetadataError.invalidPayload }
            if forceRefresh {
                guard MetadataPolicy.mayDisplay(.tvShow(updated), at: store.metadataClock()) else { throw MetadataError.invalidPayload }
                try store.metadataRefreshSucceeded(.tvShow(updated))
            }
            try store.cacheSeasonCatalog(show: updated)
            show = updated
        } catch {
            guard generation == token, !Task.isCancelled, !(error is CancellationError) else { return }
            lastError = error as? MetadataError
            errorMessage = error.localizedDescription
            if forceRefresh, let failure = lastError, !failure.isConfigurationFailure {
                try? store.metadataRefreshFailed(candidate.id, error: failure)
            }
        }
    }
    func loadSeason(_ number: Int, store: LibraryStore, force: Bool = false) async {
        if isLoading && !force { return }
        generation = UUID(); let token = generation
        let epoch = MetadataRuntimeGate.credentialEpoch
        isLoading = true; errorMessage = nil; lastError = nil; isUsingSavedSeason = false
        defer { if generation == token { isLoading = false } }
        do {
            if store.metadataPolicyEnabled { try store.maintainMetadata() }
            if !force, let cached = store.seasons(for: show.id).first(where: { $0.number == number }),
               cached.listingLoaded && MetadataPolicy.isUsable(cached.refreshedAt, at: store.metadataClock()),
               !MetadataPolicy.refreshEligible(cached.refreshedAt, at: store.metadataClock()) {
                isUsingSavedSeason = true
                return // A saved partial listing also works without credentials or a complete coverage count.
            }
            guard MetadataRuntimeGate.blockingReason == nil else { throw MetadataError.retentionBlocked }
            if !store.mayRefreshMetadata(show.id, scope: "season:\(number)", force: force) {
                lastError = store.refreshDeferral(for: show.id, scope: "season:\(number)")
                errorMessage = lastError?.localizedDescription
                return
            }
            guard let service else { throw configurationError }
            let details = try await service.tvSeasonDetails(for: show.id, number: number)
            try Task.checkCancellation()
            guard generation == token else { return }
            if MetadataPolicy.isTMDB(show.id), epoch != MetadataRuntimeGate.credentialEpoch { throw CancellationError() }
            try store.cacheSeason(details, show: show)
            try store.seasonRefreshSucceeded(details)
        } catch {
            guard generation == token, !Task.isCancelled, !(error is CancellationError) else { return }
            lastError = error as? MetadataError
            errorMessage = error.localizedDescription
            if let failure = error as? MetadataError, !failure.isConfigurationFailure {
                try? store.metadataRefreshFailed(show.id, scope: "season:\(number)", error: failure)
            }
        }
    }
}
