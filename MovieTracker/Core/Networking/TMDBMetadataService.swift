import Foundation

actor TMDBMetadataService: MediaMetadataService {
    private let retryPolicy: MetadataRetryPolicy
    private let wait: @Sendable (TimeInterval) async throws -> Void
    private var cooldownUntil: Date?
    private var cooldownError: MetadataError?
    private let authorization: @Sendable () async throws -> Void
    private let clock: @Sendable () -> Date
    private let configuration: TMDBConfiguration
    private let transport: any MetadataTransport
    // Share only the configuration request; no title/image response cache is introduced.
    private var configurationFetchedAt: Date?
    private var configurationRequest: (id: UUID, task: Task<(TMDBImageConfiguration, Date), Error>)?

    init(configuration: TMDBConfiguration, transport: any MetadataTransport = URLSessionMetadataTransport(), clock: @escaping @Sendable () -> Date = { .now }, authorization: @escaping @Sendable () async throws -> Void = {}, retryPolicy: MetadataRetryPolicy = .standard,
         wait: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        self.retryPolicy = retryPolicy; self.wait = wait
        self.authorization = authorization
        self.clock = clock
        self.configuration = configuration
        self.transport = transport
    }

    func searchMovies(query: String, page: Int = 1) async throws -> MetadataPage<Movie> {
        let response: TMDBPage = try await search("movie", query: query, page: page)
        let result = try mappedPage(response, requestedPage: page) { try $0.movie(retrievedAt: clock()) }
        try Task.checkCancellation()
        return result
    }

    func searchTVShows(query: String, page: Int = 1) async throws -> MetadataPage<TVShow> {
        let response: TMDBPage = try await search("tv", query: query, page: page)
        let result = try mappedPage(response, requestedPage: page) { try $0.tvShow(retrievedAt: clock()) }
        try Task.checkCancellation()
        return result
    }

    func searchAll(query: String, page: Int = 1) async throws -> MetadataPage<MediaSearchResult> {
        let response: TMDBPage = try await search("multi", query: query, page: page)
        let result = try mappedPage(response, requestedPage: page) { record -> MediaSearchResult? in
            switch record.mediaType {
            case "movie": return .movie(try record.movie(retrievedAt: clock()))
            case "tv": return .tvShow(try record.tvShow(retrievedAt: clock()))
            case "person": return nil // Multi-search includes people, outside this app's scope.
            default: throw MetadataError.invalidPayload
            }
        }
        try Task.checkCancellation()
        return result
    }

    func movieDetails(id: MediaID) async throws -> Movie {
        let value = try providerID(id, kind: .movie)
        let response: TMDBTitle = try await load("movie/\(value)")
        guard response.id == value else { throw MetadataError.invalidPayload }
        let movie = try response.movie(retrievedAt: clock())
        try Task.checkCancellation()
        return movie
    }

    func tvShowDetails(id: MediaID) async throws -> TVShow {
        let value = try providerID(id, kind: .tvShow)
        let response: TMDBTitle = try await load("tv/\(value)")
        guard response.id == value else { throw MetadataError.invalidPayload }
        let show = try response.tvShow(retrievedAt: clock())
        try Task.checkCancellation()
        return show
    }

    func genres(for kind: MediaID.Kind) async throws -> [MediaGenre] {
        let list: TMDBGenreList = try await load("genre/\(kind == .movie ? "movie" : "tv")/list")
        guard list.genres.allSatisfy({ $0.id > 0 && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw MetadataError.invalidPayload
        }
        try Task.checkCancellation()
        return list.genres.map { MediaGenre(id: "tmdb:\($0.id)", name: $0.name) }
    }

    func castPreview(for id: MediaID) async throws -> [CastMember] {
        let value = try providerID(id, kind: id.kind)
        let path = id.kind == .movie ? "movie" : "tv"
        let credits: TMDBCredits = try await load("\(path)/\(value)/credits")
        try Task.checkCancellation()
        return credits.preview()
    }

    func tvSeasons(for id: MediaID) async throws -> [TVSeasonSummary] {
        let show = try await tvShowDetails(id: id)
        guard let seasons = show.seasons else { throw MetadataError.invalidPayload }
        return seasons
    }

    func tvSeasonDetails(for id: MediaID, number: Int) async throws -> TVSeasonDetails {
        let value = try providerID(id, kind: .tvShow)
        guard number >= 0 else { throw MetadataError.invalidIdentifier }
        let response: TMDBSeasonResponse = try await load("tv/\(value)/season/\(number)")
        let season = try response.domain(seriesID: id, requested: number, retrievedAt: clock())
        try Task.checkCancellation()
        return season
    }

    func expireMetadataMemory(at now: Date) {
        if let until = cooldownUntil, until <= now { cooldownUntil = nil; cooldownError = nil }
        if let fetched = configurationFetchedAt, !MetadataPolicy.isUsable(fetched, at: now) {
            configurationRequest = nil; configurationFetchedAt = nil
        }
    }

    func imageResolver() async throws -> MetadataImageResolver {
        try await authorization()
        try Task.checkCancellation()
        expireMetadataMemory(at: clock())
        let flight: (id: UUID, task: Task<(TMDBImageConfiguration, Date), Error>)
        if let configurationRequest {
            flight = configurationRequest
        } else {
            let clock = clock
            flight = (UUID(), Task { [weak self] in
                guard let self else { throw CancellationError() }
                let response: TMDBImageConfiguration = try await self.request("configuration")
                return (response, clock())
            })
            configurationRequest = flight
        }
        do {
            let (response, fetched) = try await flight.task.value
            if configurationRequest?.id == flight.id { configurationFetchedAt = fetched }
            guard MetadataPolicy.isUsable(fetched, at: clock()) else {
                if configurationRequest?.id == flight.id { configurationRequest = nil; configurationFetchedAt = nil }
                throw MetadataError.metadataExpired
            }
            // A canceled consumer never publishes a result; other consumers keep the shared request.
            try Task.checkCancellation()
            try await authorization()
            return try MetadataImageResolver(
                baseURL: response.images.secureBaseURL,
                posterSizes: response.images.posterSizes, backdropSizes: response.images.backdropSizes, metadataRetrievedAt: configurationFetchedAt
            )
        } catch {
            if Task.isCancelled || error is CancellationError { throw CancellationError() }
            // An older failed waiter must not clear a newer configuration request.
            if configurationRequest?.id == flight.id { configurationRequest = nil }
            throw error
        }
    }

    private func search(_ kind: String, query: String, page: Int) async throws -> TMDBPage {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw MetadataError.invalidQuery }
        guard (1...500).contains(page) else { throw MetadataError.invalidPage }
        return try await load("search/\(kind)", query: [
            URLQueryItem(name: "query", value: query), URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "include_adult", value: "false")
        ])
    }

    private func providerID(_ id: MediaID, kind: MediaID.Kind) throws -> Int {
        guard id.kind == kind, id.value.hasPrefix("tmdb:"),
              let value = Int(id.value.dropFirst(5)), value > 0,
              id.value == "tmdb:\(value)" else { throw MetadataError.invalidIdentifier }
        return value
    }

    private func mappedPage<Item: Sendable>(
        _ response: TMDBPage, requestedPage: Int, map: (TMDBTitle) throws -> Item?
    ) throws -> MetadataPage<Item> {
        guard response.page == requestedPage, response.totalPages >= 0,
              response.totalResults >= response.results.count,
              (response.totalPages == 0 ? response.results.isEmpty && response.totalResults == 0 && requestedPage == 1
                                       : requestedPage <= min(response.totalPages, 500)) else {
            throw MetadataError.invalidPayload
        }
        return MetadataPage(items: try response.results.compactMap(map), page: response.page,
                            totalPages: min(response.totalPages, 500), totalResults: response.totalResults)
    }

    private func load<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await request(path, query: query)
    }

    private func request<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await authorization()
        try Task.checkCancellation()
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.themoviedb.org"
        components.path = "/3/" + path
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw MetadataError.invalidResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer " + configuration.readAccessToken, forHTTPHeaderField: "Authorization")
        request.httpMethod = "GET"
        let response = try await sendWithRetry(request, automaticRetries: path != "configuration")
        guard !response.data.isEmpty else { throw MetadataError.emptyResponse }
        do {
            let value = try JSONDecoder().decode(T.self, from: response.data)
            try await authorization()
            try Task.checkCancellation()
            return value
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as MetadataError {
            throw error
        } catch {
            throw MetadataError.invalidPayload
        }
    }

    private func sendWithRetry(_ request: URLRequest, automaticRetries: Bool) async throws -> MetadataHTTPResponse {
        var retries = 0
        var totalDelay: TimeInterval = 0
        while true {
            try Task.checkCancellation()
            try await authorization()
            try Task.checkCancellation()
            if let until = cooldownUntil {
                if until > clock() { throw cooldownError ?? MetadataError.rateLimited(retryAfter: nil) }
                cooldownUntil = nil; cooldownError = nil
            }
            do {
                let response = try await transport.send(request)
                try await authorization()
                let failure = Self.httpError(response, at: clock())
                if let failure {
                    let serverDelay = MetadataRetryPolicy.retryAfterSeconds(response.retryAfter, at: clock())
                    if response.status == 429 || serverDelay != nil {
                        let until = clock().addingTimeInterval(serverDelay ?? 1)
                        if cooldownUntil == nil || until > (cooldownUntil ?? .distantPast) { cooldownUntil = until; cooldownError = failure }
                    }
                }
                // A server throttle applies to the service even if this query became obsolete.
                try Task.checkCancellation()
                if let failure { throw failure }
                return response
            } catch {
                if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
                let mapped = Self.networkError(error)
                let remaining = max(0, cooldownUntil?.timeIntervalSince(clock()) ?? 0)
                guard automaticRetries, let delay = retryPolicy.delay(for: mapped, retries: retries, totalDelay: totalDelay, serverDelay: remaining) else { throw mapped }
                retries += 1; totalDelay += delay
                try await wait(delay)
                try Task.checkCancellation()
            }
        }
    }

    private static func httpError(_ response: MetadataHTTPResponse, at now: Date) -> MetadataError? {
        switch response.status {
        case 200...299: nil
        case 401: .unauthorized
        case 403: .forbidden
        case 404: .notFound
        case 429: .rateLimited(retryAfter: MetadataRetryPolicy.sanitizedDelay(MetadataRetryPolicy.retryAfterSeconds(response.retryAfter, at: now)))
        case 500...599: .server(status: response.status)
        default: .http(status: response.status)
        }
    }
    private static func networkError(_ error: Error) -> MetadataError {
        if let error = error as? MetadataError { return error }
        guard let error = error as? URLError else { return .transport }
        switch error.code {
        case .timedOut: return .timedOut
        case .notConnectedToInternet, .dataNotAllowed: return .offline
        case .networkConnectionLost: return .connectionLost
        case .cannotFindHost, .dnsLookupFailed: return .dnsFailure
        case .cannotConnectToHost: return .connectionFailed
        case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected,
             .clientCertificateRequired: return .secureTransport
        default: return .transport
        }
    }
}
