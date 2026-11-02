import Foundation
import Observation

@MainActor
@Observable
final class MediaDetailModel {
    let destination: MediaDestination
    let usesTestData: Bool
    private var storedSnapshot: MediaDetailCache.Snapshot?
    private let clock: @Sendable () -> Date
    var snapshot: MediaDetailCache.Snapshot? { snapshot(at: clock()) }
    func snapshot(at now: Date) -> MediaDetailCache.Snapshot? {
        guard let value = storedSnapshot else {
            return MetadataPolicy.isTMDB(destination.id) ? .init(media: MetadataPolicy.placeholderMedia(destination.id)) : nil
        }
        guard MetadataPolicy.mayDisplay(value.media, at: now) else { return .init(media: MetadataPolicy.placeholderMedia(destination.id)) }
        var visible = value
        if MetadataPolicy.isTMDB(destination.id), let resolver = visible.imageResolver, !MetadataPolicy.isUsable(resolver.metadataRetrievedAt, at: now) { visible.imageResolver = nil }
        return visible
    }
    private(set) var hasCurrentMetadata = false
    private(set) var isLoading = false
    private(set) var isLoadingExtras = false
    private(set) var error: MetadataError?
    private(set) var wasCancelled = false
    private(set) var castUnavailable = false
    private(set) var artworkUnavailable = false

    private var configurationError: MetadataError
    private var service: (any MediaMetadataService)?
    private let cache: MediaDetailCache
    private var generation = UUID()

    init(destination: MediaDestination, service: (any MediaMetadataService)?,
         cache: MediaDetailCache, usesTestData: Bool = false, configurationError: MetadataError = .missingCredential, clock: @escaping @Sendable () -> Date = { .now }) {
        self.configurationError = configurationError
        self.clock = clock
        self.destination = destination
        self.service = service
        self.cache = cache
        self.usesTestData = usesTestData
        storedSnapshot = cache.snapshot(for: destination.id)
    }

    /// SwiftUI's task owns cancellation. A generation also guards noncooperative transports.
    func load(store: LibraryStore? = nil, force: Bool = false) async {
        generation = UUID()
        let token = generation
        let credentialEpoch = MetadataRuntimeGate.credentialEpoch
        hasCurrentMetadata = false
        isLoading = true
        isLoadingExtras = false
        error = nil
        wasCancelled = false
        castUnavailable = false
        artworkUnavailable = false
        do {
            try Task.checkCancellation()
            if MetadataPolicy.isTMDB(destination.id), let store {
                try store.maintainMetadata()
                guard MetadataRuntimeGate.blockingReason == nil else { throw MetadataError.retentionBlocked }
            }
            guard let service else { throw configurationError }
            let media: MediaSearchResult
            let reuse = MetadataPolicy.isTMDB(destination.id) && !force && storedSnapshot.map { MetadataPolicy.mayDisplay($0.media, at: clock()) && !MetadataPolicy.refreshEligible($0.media.metadataRetrievedAt, at: clock()) } == true
            if reuse, let cached = storedSnapshot {
                media = cached.media
                if cached.extrasAttemptedAt != nil { hasCurrentMetadata = true; isLoading = false; return }
            } else {
                if let store, !store.mayRefreshMetadata(destination.id, force: force) { throw MetadataError.rateLimited(retryAfter: nil) }
                switch destination.id.kind {
                case .movie: media = .movie(try await service.movieDetails(id: destination.id))
                case .tvShow: media = .tvShow(try await service.tvShowDetails(id: destination.id))
                }
            }
            try Task.checkCancellation()
            guard generation == token else { return }
            if MetadataPolicy.isTMDB(destination.id), credentialEpoch != MetadataRuntimeGate.credentialEpoch { throw CancellationError() }
            guard SearchItem(media).id == destination.id else { throw MetadataError.invalidPayload }
            guard MetadataPolicy.mayDisplay(media, at: clock()) else { throw MetadataError.invalidPayload }
            if !reuse { try store?.metadataRefreshSucceeded(media) }
            var updated = reuse ? (storedSnapshot ?? .init(media: media)) : .init(media: media)
            updated.extrasAttemptedAt = clock()
            storedSnapshot = updated
            hasCurrentMetadata = true
            cache.save(updated, for: destination.id)
            isLoading = false
            isLoadingExtras = true
            let mediaID = destination.id
            let needsArtwork = Self.hasArtwork(media)
            async let cast = Self.fetchCast(service, id: mediaID)
            async let artwork = Self.fetchArtwork(service, needed: needsArtwork)
            let (castResult, artworkResult) = await (cast, artwork)
            try Task.checkCancellation()
            guard generation == token else { return }
            if MetadataPolicy.isTMDB(destination.id), credentialEpoch != MetadataRuntimeGate.credentialEpoch { throw CancellationError() }
            var completed = updated
            switch castResult {
            case .success(let members): completed.cast = members
            case .failure: castUnavailable = true
            }
            switch artworkResult {
            case .success(let resolver): completed.imageResolver = resolver
            case .failure: artworkUnavailable = true
            }
            storedSnapshot = completed
            cache.save(completed, for: destination.id)
            if !reuse { try store?.metadataRefreshSucceeded(media, posterURL: completed.imageResolver?.posterURL(reference: SearchItem(media).posterReference)) }
            isLoadingExtras = false
        } catch {
            guard generation == token else { return }
            isLoading = false
            isLoadingExtras = false
            if Task.isCancelled || error is CancellationError {
                wasCancelled = true
            } else {
                self.error = (error as? MetadataError) ?? .transport
                if let providerError = error as? MetadataError, !providerError.isConfigurationFailure {
                    try? store?.metadataRefreshFailed(destination.id, error: providerError)
                }
            }
        }
    }

    func expireMetadata(at now: Date) {
        if let value = storedSnapshot, !MetadataPolicy.mayDisplay(value.media, at: now) {
            storedSnapshot = .init(media: MetadataPolicy.placeholderMedia(destination.id))
        }
    }
    func invalidateProviderMetadata() {
        guard MetadataPolicy.isTMDB(destination.id) else { return }
        generation = UUID(); storedSnapshot = .init(media: MetadataPolicy.placeholderMedia(destination.id))
        cache.clear(); isLoading = false; isLoadingExtras = false
        let resolved = SearchLaunchConfiguration.resolveService()
        service = resolved.service; configurationError = resolved.error
    }

    func tvProgressModel(for show: TVShow) -> TVProgressModel { TVProgressModel(show: show, service: service, usesTestData: usesTestData, configurationError: configurationError) }

    private static func hasArtwork(_ media: MediaSearchResult) -> Bool {
        switch media {
        case .movie(let movie): movie.posterReference != nil || movie.backdropReference != nil
        case .tvShow(let show): show.posterReference != nil || show.backdropReference != nil
        }
    }

    private nonisolated static func fetchCast(
        _ service: any MediaMetadataService, id: MediaID
    ) async -> Result<[CastMember], MetadataError> {
        do { return .success(try await service.castPreview(for: id)) }
        catch { return .failure((error as? MetadataError) ?? .transport) }
    }

    private nonisolated static func fetchArtwork(
        _ service: any MediaMetadataService, needed: Bool
    ) async -> Result<MetadataImageResolver?, MetadataError> {
        guard needed else { return .success(nil) }
        do { return .success(try await service.imageResolver()) }
        catch { return .failure((error as? MetadataError) ?? .transport) }
    }
}
