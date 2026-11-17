import Foundation
import Observation

/// Ephemeral provider results only. Personal mutations remain in LibraryStore/detail actions.
@MainActor @Observable
final class ProviderBrowseModel {
    enum Category: String, CaseIterable, Identifiable {
        case trending = "Trending", popular = "Popular", topRated = "Top Rated", genres = "Genres"
        var id: Self { self }
    }
    enum Phase: Equatable { case idle, loading, chooseGenre, loaded, cancelled, failed(MetadataError) }
    struct Key: Hashable {
        let kind: MediaID.Kind
        let category: String
        let genre: String?
        let revision: Int
    }
    var kind: MediaID.Kind = .movie { didSet { if oldValue != kind { selectedGenre = nil } } }
    var category: Category = .trending
    var selectedGenre: String?
    private(set) var phase: Phase = .idle
    private(set) var genres: [MediaGenre] = []
    private(set) var genreError: MetadataError?
    private(set) var pageError: MetadataError?
    private(set) var nextPage: Int?
    private(set) var isLoadingMore = false
    private(set) var imageResolver: MetadataImageResolver?
    private var storedItems: [SearchItem] = []
    private var revision = 0
    private var generation = UUID()
    private var preparedKey: Key?
    private var epoch: Int
    private var service: (any MediaMetadataService)?
    private var configurationError: MetadataError
    private let clock: @Sendable () -> Date
    let relatedTo: MediaID?
    let language: String
    let region: String?
    @ObservationIgnored private var pageTask: Task<Void, Never>?
    private var genreCache: [MediaID.Kind: GenreLease] = [:]
    private struct GenreLease { let values: [MediaGenre]; let retrieved: Date }

    init(service: (any MediaMetadataService)?, relatedTo: MediaID? = nil,
         configurationError: MetadataError = .missingCredential,
         language: String = "en-US", region: String? = nil,
         clock: @escaping @Sendable () -> Date = { .now }) {
        self.service = service; self.relatedTo = relatedTo; self.configurationError = configurationError
        self.clock = clock; self.language = language; self.region = region
        epoch = MetadataRuntimeGate.credentialEpoch
        if let relatedTo { kind = relatedTo.kind }
    }

    var key: Key { Key(kind: kind, category: category.rawValue, genre: selectedGenre, revision: revision) }
    var items: [SearchItem] {
        guard MetadataRuntimeGate.blockingReason == nil, epoch == MetadataRuntimeGate.credentialEpoch, preparedKey == key else { return [] }
        return storedItems.filter { !MetadataPolicy.isTMDB($0.id) || MetadataPolicy.isUsable($0.metadataRetrievedAt, at: clock()) }
    }
    var heading: String { relatedTo == nil ? category.rawValue : "Similar Titles" }
    var explanation: String {
        if relatedTo != nil { return "Similar titles from TMDB, based on provider metadata. Not personalized." }
        switch category {
        case .trending: return "This week’s TMDB trending \(kind == .movie ? "movies" : "TV shows"). A single-page preview."
        case .popular: return "Popular \(kind == .movie ? "movies" : "TV shows"), ranked by TMDB."
        case .topRated: return "TMDB’s top-rated \(kind == .movie ? "movies" : "TV shows"). Provider ranking, independent of your personal ratings."
        case .genres: return "Choose a \(kind == .movie ? "movie" : "TV") genre. Results are ordered by TMDB popularity."
        }
    }
    private var request: MetadataBrowseRequest? {
        let selection: MetadataBrowseRequest.Category
        if let relatedTo { selection = .similar(relatedTo) }
        else {
            switch category {
            case .trending: selection = .trending
            case .popular: selection = .popular
            case .topRated: selection = .topRated
            case .genres:
                guard let selectedGenre else { return nil }
                selection = .genre(selectedGenre)
            }
        }
        return MetadataBrowseRequest(kind: relatedTo?.kind ?? kind, category: selection, language: language, region: region)
    }

    /// Owned by SwiftUI .task(id:). Generations also reject noncooperative transports.
    func load() async {
        expire(at: clock())
        guard preparedKey != key || phase != .loaded else { return }
        generation = UUID(); pageTask?.cancel()
        let token = generation, selection = key
        storedItems = []; nextPage = nil; pageError = nil; isLoadingMore = false
        imageResolver = nil; genres = []; genreError = nil; phase = .loading
        do {
            try checkSession()
            guard let service else { throw configurationError }
            if relatedTo == nil {
                if let cached = genreCache[kind], MetadataPolicy.isUsable(cached.retrieved, at: clock()) { genres = cached.values }
                else {
                    do {
                        let values = try await service.discoveryGenres(for: kind, language: language)
                        try check(token, selection)
                        genres = values
                        genreCache[kind] = GenreLease(values: values, retrieved: clock())
                    } catch {
                        try check(token, selection)
                        genreError = Self.error(error)
                        // Avoid another request after an authentication/network failure.
                        if category == .genres || Self.error(error) != .unsupportedDiscovery { throw error }
                    }
                }
            }
            guard let request else { phase = .chooseGenre; return }
            if category == .genres, relatedTo == nil, !genres.contains(where: { $0.id == selectedGenre }) { throw MetadataError.invalidIdentifier }
            let response = try await service.browse(request, page: 1)
            try check(token, selection)
            try append(response, requestedPage: 1, request: request)
            preparedKey = selection; phase = .loaded
            guard !storedItems.isEmpty else { return }
            // Artwork failure must not hide valid titles. Uses the shared sized resolver/loader.
            do {
                let resolver = try await service.imageResolver()
                try check(token, selection)
                if MetadataPolicy.isUsable(resolver.metadataRetrievedAt, at: clock()) { imageResolver = resolver }
            } catch { /* Accessible placeholders remain available. No automatic retry. */ }
        } catch {
            guard token == generation, selection == key else { return }
            phase = error is CancellationError ? .cancelled : .failed(Self.error(error))
        }
    }

    func loadMore() {
        guard phase == .loaded, preparedKey == key, !isLoadingMore, let page = nextPage, let request, let service else { return }
        isLoadingMore = true; pageError = nil
        let token = generation, selection = key
        pageTask = Task { [weak self] in
            guard let self else { return }
            defer { if token == generation { isLoadingMore = false } }
            do {
                try checkSession()
                let response = try await service.browse(request, page: page)
                try check(token, selection)
                try append(response, requestedPage: page, request: request)
            } catch {
                guard token == generation, selection == key else { return }
                if !(error is CancellationError) { pageError = Self.error(error) }
            }
        }
    }
    func waitForPage() async { await pageTask?.value }
    func cancelPagination() {
        generation = UUID(); pageTask?.cancel(); pageTask = nil; isLoadingMore = false
    }
    func retry() { preparedKey = nil; revision += 1 }
    func replaceService(_ service: (any MediaMetadataService)?, configurationError: MetadataError = .missingCredential) {
        clear(); self.service = service; self.configurationError = configurationError
        epoch = MetadataRuntimeGate.credentialEpoch; revision += 1
    }
    func invalidateSessionIfChanged() {
        guard epoch != MetadataRuntimeGate.credentialEpoch else { return }
        clear(); phase = .failed(.providerSessionChanged)
    }
    func clear() {
        generation = UUID(); cancelPagination(); storedItems = []; nextPage = nil; preparedKey = nil
        genres = []; genreCache = [:]; imageResolver = nil; pageError = nil; phase = .idle
    }
    func expire(at now: Date) {
        invalidateSessionIfChanged()
        if let lease = genreCache[kind], !MetadataPolicy.isUsable(lease.retrieved, at: now) {
            genres = []
            if category == .genres { clear(); phase = .failed(.metadataExpired); return }
        }
        genreCache = genreCache.filter { MetadataPolicy.isUsable($0.value.retrieved, at: now) }
        if let resolver = imageResolver, !MetadataPolicy.isUsable(resolver.metadataRetrievedAt, at: now) { imageResolver = nil }
        if storedItems.contains(where: { MetadataPolicy.isTMDB($0.id) && !MetadataPolicy.isUsable($0.metadataRetrievedAt, at: now) }) {
            clear(); phase = .failed(.metadataExpired)
        }
    }
    private func checkSession() throws {
        guard epoch == MetadataRuntimeGate.credentialEpoch else { throw MetadataError.providerSessionChanged }
        if MetadataRuntimeGate.blockingReason != nil { throw MetadataError.retentionBlocked }
        try Task.checkCancellation()
    }
    private func check(_ token: UUID, _ selection: Key) throws {
        try checkSession()
        guard token == generation, selection == key else { throw CancellationError() }
    }
    private func append(_ response: MetadataPage<MediaSearchResult>, requestedPage: Int, request: MetadataBrowseRequest) throws {
        guard response.page == requestedPage, response.totalPages >= 0, response.totalResults >= response.items.count,
              (response.totalPages == 0 ? response.items.isEmpty && response.totalResults == 0 && requestedPage == 1 : response.totalPages >= requestedPage) else { throw MetadataError.invalidPayload }
        let mapped = response.items.map(SearchItem.init)
        guard mapped.allSatisfy({ $0.id.kind == request.kind && !($0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && (!MetadataPolicy.isTMDB($0.id) || MetadataPolicy.isUsable($0.metadataRetrievedAt, at: clock())) }) else { throw MetadataError.invalidPayload }
        let limit = relatedTo == nil ? 200 : 20
        var seen = Set(storedItems.map(\.id))
        for item in mapped where item.id != relatedTo && seen.insert(item.id).inserted {
            if storedItems.count < limit { storedItems.append(item) }
        }
        nextPage = relatedTo == nil && category != .trending && storedItems.count < limit
            ? response.nextPage.flatMap { $0 <= 500 ? $0 : nil } : nil
    }
    private static func error(_ error: Error) -> MetadataError { error as? MetadataError ?? .transport }
}
