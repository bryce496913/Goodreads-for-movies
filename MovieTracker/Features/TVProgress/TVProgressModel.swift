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
    func seasonModel(_ cached: StoredTVSeason) -> TVProgressModel {
        TVProgressModel(show: cached.savedShow ?? show, service: service, usesTestData: usesTestData)
    }
    func loadCatalog(show candidate: TVShow, store: LibraryStore, snapshotIsFresh: Bool = true, forceRefresh: Bool = false) async {
        generation = UUID(); let token = generation
        isLoading = true; errorMessage = nil
        defer { if generation == token { isLoading = false } }
        do {
            var updated = candidate
            if forceRefresh {
                guard let service else { throw MetadataError.missingCredential }
                updated.seasons = try await service.tvSeasons(for: candidate.id)
            } else if !snapshotIsFresh && !store.seasons(for: candidate.id).isEmpty {
                show = candidate
                return // Never replace a newer persisted catalogue with an older Library snapshot.
            } else if updated.seasons == nil {
                errorMessage = "No season catalogue is saved in these details. Refresh Seasons to retrieve it."
                return
            }
            try Task.checkCancellation()
            guard generation == token else { return }
            try store.cacheSeasonCatalog(show: updated)
            show = updated
        } catch {
            guard generation == token, !Task.isCancelled, !(error is CancellationError) else { return }
            errorMessage = error.localizedDescription
        }
    }
    func loadSeason(_ number: Int, store: LibraryStore) async {
        generation = UUID(); let token = generation
        isLoading = true; errorMessage = nil
        defer { if generation == token { isLoading = false } }
        do {
            guard let service else { throw MetadataError.missingCredential }
            let details = try await service.tvSeasonDetails(for: show.id, number: number)
            try Task.checkCancellation()
            guard generation == token else { return }
            try store.cacheSeason(details, show: show)
        } catch {
            guard generation == token, !Task.isCancelled, !(error is CancellationError) else { return }
            errorMessage = error.localizedDescription
        }
    }
}
