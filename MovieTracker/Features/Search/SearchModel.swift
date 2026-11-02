import Foundation
import Observation

@MainActor
@Observable
final class SearchModel {
    enum Phase: Equatable { case idle, loading, loaded, cancelled, failed(MetadataError) }

    var query = "" { didSet { schedule() } }
    var filter: SearchFilter = .all { didSet { schedule() } }
    private(set) var phase: Phase = .idle
    private(set) var items: [SearchItem] = []
    private(set) var nextPage: Int?
    private(set) var isLoadingMore = false
    private(set) var pageError: MetadataError?
    private(set) var imageResolver: MetadataImageResolver?
    private(set) var artworkUnavailable = false
    let usesTestData: Bool

    private struct Key: Equatable { let query: String; let filter: SearchFilter }
    @ObservationIgnored private let detailCache = MediaDetailCache()
    private let service: (any MediaMetadataService)?
    private let debounce: @Sendable () async throws -> Void
    private var currentKey: Key?
    private var generation = UUID()
    @ObservationIgnored private(set) var searchTask: Task<Void, Never>?
    @ObservationIgnored private(set) var pageTask: Task<Void, Never>?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?

    init(
        service: (any MediaMetadataService)?, usesTestData: Bool = false,
        debounce: @escaping @Sendable () async throws -> Void = {
            try await Task.sleep(for: .milliseconds(300))
        }
    ) {
        self.service = service
        self.usesTestData = usesTestData
        self.debounce = debounce
    }

    func tvProgressModel(for show: TVShow) -> TVProgressModel {
        TVProgressModel(show: show, service: service, usesTestData: usesTestData)
    }

    func detailModel(for destination: MediaDestination, savedMedia: MediaSearchResult? = nil) -> MediaDetailModel {
        if detailCache.snapshot(for: destination.id) == nil, let savedMedia, SearchItem(savedMedia).id == destination.id {
            detailCache.save(.init(media: savedMedia), for: destination.id)
        }
        return MediaDetailModel(destination: destination, service: service, cache: detailCache, usesTestData: usesTestData)
    }

    static func normalizedQuery(_ query: String) -> String {
        query.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    func retry() {
        guard let key = currentKey, !key.query.isEmpty else { return }
        start(key, debounced: false)
    }

    func loadMore() {
        guard phase == .loaded, !isLoadingMore, let page = nextPage, let key = currentKey else { return }
        let token = generation
        isLoadingMore = true // Synchronous guard protects double taps before the task starts.
        pageError = nil
        pageTask = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await fetch(key, page: page)
                try Task.checkCancellation()
                guard generation == token else { return }
                append(response.items)
                nextPage = response.nextPage
                isLoadingMore = false
                requestArtworkIfNeeded()
            } catch {
                guard generation == token else { return }
                isLoadingMore = false
                if !(error is CancellationError) { pageError = Self.error(error) }
            }
        }
    }

    func retryArtwork() {
        artworkTask = nil
        requestArtworkIfNeeded()
    }

    /// Awaitable synchronization for tests; production never blocks on this method.
    func waitForSearch() async { await searchTask?.value }
    func waitForPage() async { await pageTask?.value }

    private func schedule() {
        let key = Key(query: Self.normalizedQuery(query), filter: filter)
        guard key != currentKey else { return }
        start(key, debounced: true)
    }

    private func start(_ key: Key, debounced: Bool) {
        currentKey = key
        generation = UUID()
        let token = generation
        searchTask?.cancel()
        pageTask?.cancel()
        items = []
        nextPage = nil
        pageError = nil
        isLoadingMore = false
        guard !key.query.isEmpty else { phase = .idle; return }
        phase = .loading
        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                if debounced { try await debounce() }
                try Task.checkCancellation()
                let response = try await fetch(key, page: 1)
                try Task.checkCancellation()
                guard generation == token else { return }
                append(response.items)
                nextPage = response.nextPage
                phase = .loaded
                requestArtworkIfNeeded()
            } catch {
                guard generation == token else { return }
                phase = error is CancellationError ? .cancelled : .failed(Self.error(error))
            }
        }
    }

    private func fetch(_ key: Key, page: Int) async throws -> MetadataPage<MediaSearchResult> {
        guard let service else { throw MetadataError.missingCredential }
        let response: MetadataPage<MediaSearchResult>
        switch key.filter {
        case .all:
            response = try await service.searchAll(query: key.query, page: page)
        case .movies:
            let value = try await service.searchMovies(query: key.query, page: page)
            response = MetadataPage(items: value.items.map { .movie($0) }, page: value.page,
                                    totalPages: value.totalPages, totalResults: value.totalResults)
        case .tvShows:
            let value = try await service.searchTVShows(query: key.query, page: page)
            response = MetadataPage(items: value.items.map { .tvShow($0) }, page: value.page,
                                    totalPages: value.totalPages, totalResults: value.totalResults)
        }
        guard response.page == page else { throw MetadataError.invalidPayload }
        return response
    }

    private func append(_ results: [MediaSearchResult]) {
        var seen = Set(items.map(\.id))
        for result in results {
            let item = SearchItem(result)
            if seen.insert(item.id).inserted { items.append(item) }
        }
    }

    private func requestArtworkIfNeeded() {
        guard imageResolver == nil, artworkTask == nil,
              items.contains(where: { $0.posterReference != nil }), let service else { return }
        artworkUnavailable = false
        artworkTask = Task { [weak self] in
            do {
                let resolver = try await service.imageResolver()
                try Task.checkCancellation()
                self?.imageResolver = resolver
            } catch {
                if !(error is CancellationError) { self?.artworkUnavailable = true }
            }
        }
    }

    private static func error(_ error: Error) -> MetadataError {
        (error as? MetadataError) ?? .transport
    }
}
