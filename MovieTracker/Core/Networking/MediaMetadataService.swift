import Foundation

struct MetadataPage<Item: Sendable>: Sendable {
    let items: [Item]
    let page: Int
    let totalPages: Int
    let totalResults: Int

    var nextPage: Int? { page < totalPages ? page + 1 : nil }
}

enum MediaSearchResult: Equatable, Sendable {
    case movie(Movie)
    case tvShow(TVShow)
}

protocol MediaMetadataService: Sendable {
    func searchMovies(query: String, page: Int) async throws -> MetadataPage<Movie>
    func searchTVShows(query: String, page: Int) async throws -> MetadataPage<TVShow>
    func searchAll(query: String, page: Int) async throws -> MetadataPage<MediaSearchResult>
    func movieDetails(id: MediaID) async throws -> Movie
    func tvShowDetails(id: MediaID) async throws -> TVShow
    func genres(for kind: MediaID.Kind) async throws -> [MediaGenre]
    func castPreview(for id: MediaID) async throws -> [CastMember]
    func imageResolver() async throws -> MetadataImageResolver
}

enum MetadataError: Error, Equatable, Sendable {
    case missingCredential
    case invalidQuery
    case invalidPage
    case invalidIdentifier
    case unauthorized
    case rateLimited(retryAfter: String?)
    case server(status: Int)
    case http(status: Int)
    case offline
    case timedOut
    case transport
    case invalidResponse
    case emptyResponse
    case invalidPayload
}

extension MetadataError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingCredential: "Configure an authorized metadata provider credential for local development."
        case .invalidQuery: "Enter a nonempty search query."
        case .invalidPage: "The requested results page is out of range."
        case .invalidIdentifier: "This title does not have a supported metadata identifier."
        case .unauthorized: "The metadata provider did not authorize this credential."
        case .rateLimited: "The metadata provider is busy. Try again later."
        case .server: "The metadata provider is temporarily unavailable."
        case .http: "The metadata provider could not complete this request."
        case .offline: "An internet connection is required to retrieve metadata."
        case .timedOut: "The metadata request timed out."
        case .transport: "The metadata request could not be completed."
        case .invalidResponse, .emptyResponse, .invalidPayload: "The metadata provider returned an unusable response."
        }
    }
}

// Providers/mocks without credits support may explicitly return an empty preview.
extension MediaMetadataService {
    func castPreview(for id: MediaID) async throws -> [CastMember] { [] }
}
