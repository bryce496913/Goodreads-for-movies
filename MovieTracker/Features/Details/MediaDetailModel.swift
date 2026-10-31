import Foundation
import Observation

@MainActor
@Observable
final class MediaDetailModel {
    let destination: MediaDestination
    let usesTestData: Bool
    private(set) var snapshot: MediaDetailCache.Snapshot?
    private(set) var isLoading = false
    private(set) var isLoadingExtras = false
    private(set) var error: MetadataError?
    private(set) var wasCancelled = false
    private(set) var castUnavailable = false
    private(set) var artworkUnavailable = false

    private let service: (any MediaMetadataService)?
    private let cache: MediaDetailCache
    private var generation = UUID()

    init(destination: MediaDestination, service: (any MediaMetadataService)?,
         cache: MediaDetailCache, usesTestData: Bool = false) {
        self.destination = destination
        self.service = service
        self.cache = cache
        self.usesTestData = usesTestData
        snapshot = cache.snapshot(for: destination.id)
    }

    /// SwiftUI's task owns cancellation. A generation also guards noncooperative transports.
    func load() async {
        generation = UUID()
        let token = generation
        isLoading = true
        isLoadingExtras = false
        error = nil
        wasCancelled = false
        castUnavailable = false
        artworkUnavailable = false
        do {
            try Task.checkCancellation()
            guard let service else { throw MetadataError.missingCredential }
            let media: MediaSearchResult
            switch destination.id.kind {
            case .movie: media = .movie(try await service.movieDetails(id: destination.id))
            case .tvShow: media = .tvShow(try await service.tvShowDetails(id: destination.id))
            }
            try Task.checkCancellation()
            guard generation == token else { return }
            guard SearchItem(media).id == destination.id else { throw MetadataError.invalidPayload }
            let updated = MediaDetailCache.Snapshot(
                media: media, cast: snapshot?.cast ?? [], imageResolver: snapshot?.imageResolver
            )
            snapshot = updated
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
            var completed = updated
            switch castResult {
            case .success(let members): completed.cast = members
            case .failure: castUnavailable = true
            }
            switch artworkResult {
            case .success(let resolver): completed.imageResolver = resolver
            case .failure: artworkUnavailable = true
            }
            snapshot = completed
            cache.save(completed, for: destination.id)
            isLoadingExtras = false
        } catch {
            guard generation == token else { return }
            isLoading = false
            isLoadingExtras = false
            if Task.isCancelled || error is CancellationError {
                wasCancelled = true
            } else {
                self.error = (error as? MetadataError) ?? .transport
            }
        }
    }

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
