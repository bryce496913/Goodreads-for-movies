import Foundation
import Observation

@MainActor
@Observable
final class WatchDiscoveryModel {
    var source = DiscoverySource.watchlist
    var filters = DiscoveryFilters()
    private(set) var candidates: [DiscoveryCandidate] = []
    private(set) var genres: [MediaGenre] = []
    private(set) var sourceCount = 0
    private(set) var picked: DiscoveryCandidate?
    var showingResult = false
    private(set) var isUpdating = false
    private(set) var preparedRequest: Request?
    private(set) var errorMessage: String?
    @ObservationIgnored private var cachedSource: [DiscoveryCandidate] = []
    @ObservationIgnored private var cachedKey: SourceKey?
    @ObservationIgnored private var generation = UUID()
    struct SourceKey: Hashable, Sendable { let source: DiscoverySource; let revision: Int; let date: Date }
    struct Request: Hashable, Sendable { let source: SourceKey; let filters: DiscoveryFilters }

    func request(for store: LibraryStore) -> Request {
        Request(source: SourceKey(source: source, revision: store.revision, date: store.metadataReferenceDate), filters: filters)
    }

    func update(from store: LibraryStore, request: Request) async {
        guard !Task.isCancelled, request == self.request(for: store) else { return }
        let token = UUID(); generation = token; isUpdating = true; errorMessage = nil
        defer { if generation == token { isUpdating = false } }
        picked = picked?.retained(at: request.source.date)
        guard store.loadError == nil else {
            errorMessage = "Your Library could not be loaded. Return to Library and retry. No saved data has been removed."
            candidates = []; return
        }
        let inputs: [DiscoveryInput]?
        if cachedKey != request.source {
            let ids: [MediaID]
            switch request.source.source {
            case .watchlist: ids = store.entries.filter { $0.status == LibraryStatus.watchlist.rawValue }.compactMap(\.mediaID)
            case .collection(let id): ids = store.members(of: id).compactMap(\.mediaID)
            }
            var seen: Set<MediaID> = []
            inputs = ids.filter { seen.insert($0).inserted }.map { Self.capture($0, from: store) }
        } else { inputs = nil }
        let existing = cachedSource
        let existingGenres = genres
        let existingPick = picked
        let pickedInput = cachedKey != request.source ? picked.map { Self.capture($0.id, from: store) } : nil
        let worker = Task.detached(priority: .userInitiated) {
            let source = try inputs.map { try WatchDiscoveryProjection.build($0, watchlist: request.source.source == .watchlist, at: request.source.date) } ?? existing
            let visible = try WatchDiscoveryProjection.filter(source, using: request.filters, at: request.source.date)
            let selected: DiscoveryCandidate?
            if let pickedInput {
                selected = try WatchDiscoveryProjection.build([pickedInput], watchlist: false, at: request.source.date).first
            } else { selected = existingPick?.retained(at: request.source.date) }
            if inputs == nil { return (source, visible, existingGenres, selected) }
            var byID: [String: MediaGenre] = [:]
            for value in source {
                try Task.checkCancellation()
                for genre in value.genres where byID[genre.id] == nil { byID[genre.id] = genre }
            }
            let genres = byID.values.sorted { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }
            return (source, visible, genres, selected)
        }
        do {
            let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
            try Task.checkCancellation()
            guard generation == token, request == self.request(for: store) else { return }
            cachedSource = result.0; cachedKey = request.source
            sourceCount = result.0.count; candidates = result.1; genres = result.2; preparedRequest = request
            picked = result.3
        } catch is CancellationError { /* Replaced work never publishes stale results. */ }
        catch { if generation == token { candidates = []; errorMessage = "Unable to prepare local choices. Return to Library and try again." } }
    }

    private static func capture(_ id: MediaID, from store: LibraryStore) -> DiscoveryInput {
        let entry = store.entry(for: id)
        let payloads = [entry?.snapshotData].compactMap { $0 }
            + store.events(for: id).compactMap(\.snapshotData) + store.reviews(for: id).compactMap(\.snapshotData)
        return DiscoveryInput(id: id, library: entry.map { LibraryItemInput(entry: $0) }, payloads: payloads,
                              seriesPayloads: store.seasons(for: id).compactMap(\.seriesData))
    }

    func pick(request: Request, index: (Range<Int>) -> Int = { Int.random(in: $0) }) {
        guard preparedRequest == request, request.filters == filters, request.source.source == source, !isUpdating, let value = WatchDiscoveryProjection.pick(candidates, index: index) else { return }
        picked = value; showingResult = true
    }
    func resetFilters() { filters = DiscoveryFilters() }
    func resetFlow() { source = .watchlist; resetFilters(); picked = nil; showingResult = false }
}
