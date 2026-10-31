import Foundation

actor TMDBMetadataService: MediaMetadataService {
    private let configuration: TMDBConfiguration
    private let transport: any MetadataTransport
    // Share only the configuration request; no title/image response cache is introduced.
    private var configurationRequest: (id: UUID, task: Task<TMDBImageConfiguration, Error>)?

    init(configuration: TMDBConfiguration, transport: any MetadataTransport = URLSessionMetadataTransport()) {
        self.configuration = configuration
        self.transport = transport
    }

    func searchMovies(query: String, page: Int = 1) async throws -> MetadataPage<Movie> {
        let response: TMDBPage = try await search("movie", query: query, page: page)
        let result = try mappedPage(response, requestedPage: page) { try $0.movie() }
        try Task.checkCancellation()
        return result
    }

    func searchTVShows(query: String, page: Int = 1) async throws -> MetadataPage<TVShow> {
        let response: TMDBPage = try await search("tv", query: query, page: page)
        let result = try mappedPage(response, requestedPage: page) { try $0.tvShow() }
        try Task.checkCancellation()
        return result
    }

    func searchAll(query: String, page: Int = 1) async throws -> MetadataPage<MediaSearchResult> {
        let response: TMDBPage = try await search("multi", query: query, page: page)
        let result = try mappedPage(response, requestedPage: page) { record -> MediaSearchResult? in
            switch record.mediaType {
            case "movie": return .movie(try record.movie())
            case "tv": return .tvShow(try record.tvShow())
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
        let movie = try response.movie()
        try Task.checkCancellation()
        return movie
    }

    func tvShowDetails(id: MediaID) async throws -> TVShow {
        let value = try providerID(id, kind: .tvShow)
        let response: TMDBTitle = try await load("tv/\(value)")
        guard response.id == value else { throw MetadataError.invalidPayload }
        let show = try response.tvShow()
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

    func imageResolver() async throws -> MetadataImageResolver {
        try Task.checkCancellation()
        let flight: (id: UUID, task: Task<TMDBImageConfiguration, Error>)
        if let configurationRequest {
            flight = configurationRequest
        } else {
            let configuration = configuration
            let transport = transport
            flight = (UUID(), Task {
                try await Self.request("configuration", configuration: configuration, transport: transport)
            })
            configurationRequest = flight
        }
        do {
            let response = try await flight.task.value
            // A canceled consumer never publishes a result; other consumers keep the shared request.
            try Task.checkCancellation()
            return try MetadataImageResolver(
                baseURL: response.images.secureBaseURL,
                posterSizes: response.images.posterSizes, backdropSizes: response.images.backdropSizes
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
        try await Self.request(path, query: query, configuration: configuration, transport: transport)
    }

    private static func request<T: Decodable & Sendable>(
        _ path: String, query: [URLQueryItem] = [],
        configuration: TMDBConfiguration, transport: any MetadataTransport
    ) async throws -> T {
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
        let response: MetadataHTTPResponse
        do {
            response = try await transport.send(request)
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            if let urlError = error as? URLError {
                switch urlError.code {
                case .timedOut: throw MetadataError.timedOut
                case .notConnectedToInternet, .networkConnectionLost: throw MetadataError.offline
                default: throw MetadataError.transport
                }
            }
            throw (error as? MetadataError) ?? MetadataError.transport
        }
        try Task.checkCancellation()
        switch response.status {
        case 200...299: break
        case 401, 403: throw MetadataError.unauthorized
        case 429: throw MetadataError.rateLimited(retryAfter: response.retryAfter)
        case 500...599: throw MetadataError.server(status: response.status)
        default: throw MetadataError.http(status: response.status)
        }
        guard !response.data.isEmpty else { throw MetadataError.emptyResponse }
        do {
            let value = try JSONDecoder().decode(T.self, from: response.data)
            try Task.checkCancellation()
            return value
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw MetadataError.invalidPayload
        }
    }
}
